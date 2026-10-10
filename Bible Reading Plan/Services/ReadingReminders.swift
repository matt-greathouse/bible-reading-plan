import Foundation
import UserNotifications
import Combine

struct PlanReminder: Codable, Equatable {
    var enabled = false
    var hour = 8
    var minute = 0
    var weekdays: Set<Int> = Set(1...7)

    var isValid: Bool {
        (0...23).contains(hour) && (0...59).contains(minute) &&
        weekdays.isSubset(of: Set(1...7)) && (!enabled || !weekdays.isEmpty)
    }

    var scheduleDescription: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let time = Calendar.current.date(from: components)?.formatted(date: .omitted, time: .shortened) ?? ""
        let symbols = Calendar.current.shortWeekdaySymbols
        let days = weekdays.count == 7 ? "Every day" : weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
        return "\(days), \(time)"
    }

    func requests(planID: String, name: String, app: BibleApp) -> [UNNotificationRequest] {
        guard enabled, isValid else { return [] }
        let days: [Int?] = weekdays.count == 7 ? [nil] : weekdays.sorted().map { Optional($0) }
        return days.map { weekday in
            let content = UNMutableNotificationContent()
            content.title = name
            content.body = "Open your reading in \(app.title)."
            content.userInfo = ["planID": planID]
            content.threadIdentifier = planID
            content.interruptionLevel = .active
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.weekday = weekday
            return UNNotificationRequest(identifier: ReadingReminderManager.prefix + planID + "." + (weekday.map(String.init) ?? "daily"),
                                         content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        }
    }
}

struct ReminderAuthorization {
    var status: UNAuthorizationStatus
    var alertsEnabled: Bool
    var permitsDelivery: Bool {
        alertsEnabled && (status == .authorized || status == .provisional || status == .ephemeral)
    }
}

@MainActor
protocol ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization
    func requestPermission() async throws
    func pending() async -> [UNNotificationRequest]
    func add(_ request: UNNotificationRequest) async throws
    func remove(_ ids: [String])
    func removeDelivered(_ ids: [String])
}

@MainActor
final class SystemReminderNotificationClient: ReminderNotificationClient {
    private let center = UNUserNotificationCenter.current()
    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        return ReminderAuthorization(status: settings.authorizationStatus, alertsEnabled: settings.alertSetting == .enabled)
    }
    func requestPermission() async throws { _ = try await center.requestAuthorization(options: [.alert]) }
    func pending() async -> [UNNotificationRequest] { await center.pendingNotificationRequests() }
    func add(_ request: UNNotificationRequest) async throws { try await center.add(request) }
    func remove(_ ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func removeDelivered(_ ids: [String]) { center.removeDeliveredNotifications(withIdentifiers: ids) }
}

/// Used by previews and UI tests; never asks for system permissions or sends real notifications.
@MainActor
final class PreviewReminderNotificationClient: ReminderNotificationClient {
    var requests: [String: UNNotificationRequest] = [:]
    func authorization() async -> ReminderAuthorization { ReminderAuthorization(status: .authorized, alertsEnabled: true) }
    func requestPermission() async throws {}
    func pending() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws { requests[request.identifier] = request }
    func remove(_ ids: [String]) { ids.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ ids: [String]) {}
}

@MainActor
final class ReadingReminderManager: ObservableObject {
    nonisolated static let prefix = "reading-reminder."
    static let preferenceKey = "planReminders.v1"
    @Published private(set) var configurations: [String: PlanReminder]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var blocked = false
    @Published private(set) var scheduledPlanIDs: Set<String> = []
    private let preferences: UserDefaults
    private let client: any ReminderNotificationClient
    private var queue: Task<Void, Never>?

    init(preferences: UserDefaults, client: any ReminderNotificationClient) {
        self.preferences = preferences
        self.client = client
        let decoded = preferences.data(forKey: Self.preferenceKey).flatMap { try? JSONDecoder().decode([String: PlanReminder].self, from: $0) } ?? [:]
        configurations = decoded.filter { $0.value.isValid }
    }

    func configuration(for id: String) -> PlanReminder { configurations[id] ?? PlanReminder() }

    func save(_ configuration: PlanReminder, for id: String) async throws {
        guard configuration.isValid else { throw ReminderError.invalidSchedule }
        var updated = configurations
        updated[id] = configuration
        preferences.set(try JSONEncoder().encode(updated), forKey: Self.preferenceKey)
        configurations = updated
        if configuration.enabled {
            let authorization = await client.authorization()
            if authorization.status == .notDetermined { try await client.requestPermission() }
        }
    }

    func reconcile(plans: [CatalogPlan], selected: [String], deleted: Set<String>, app: BibleApp) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await performReconcile(plans: plans, selected: selected, deleted: deleted, app: app)
        }
        queue = task
        await task.value
    }

    private func performReconcile(plans: [CatalogPlan], selected: [String], deleted: Set<String>, app: BibleApp) async {
        if !deleted.isEmpty {
            configurations = configurations.filter { !deleted.contains($0.key) }
            if let data = try? JSONEncoder().encode(configurations) { preferences.set(data, forKey: Self.preferenceKey) }
        }
        errors = [:]
        scheduledPlanIDs = []
        let authorization = await client.authorization()
        blocked = authorization.status == .denied || (authorization.status != .notDetermined && !authorization.permitsDelivery)
        let pending = await client.pending()
        let owned = pending.filter { $0.identifier.hasPrefix(Self.prefix) }
        let active = plans.filter { selected.contains($0.id) && configuration(for: $0.id).enabled }
        let desired = authorization.permitsDelivery ? active.flatMap { configuration(for: $0.id).requests(planID: $0.id, name: $0.plan.name, app: app) } : []
        let desiredIDs = Set(desired.map(\.identifier))
        let obsolete = owned.filter { !desiredIDs.contains($0.identifier) }.map(\.identifier)
        client.remove(obsolete)
        client.removeDelivered(obsolete)
        // Includes requests belonging to other features; never silently discard a user's schedule.
        guard desired.count + pending.filter({ !$0.identifier.hasPrefix(Self.prefix) }).count <= 64 else {
            for plan in active {
                let expected = desired.filter { ($0.content.userInfo["planID"] as? String) == plan.id }
                if !expected.isEmpty && expected.allSatisfy({ request in
                    Self.matches(owned.first { $0.identifier == request.identifier }, request)
                }) {
                    scheduledPlanIDs.insert(plan.id)
                } else {
                    errors[plan.id] = "Too many reminders are scheduled. Turn off another reminder or select fewer weekdays."
                    client.remove(owned.filter { ($0.content.userInfo["planID"] as? String) == plan.id }.map(\.identifier))
                }
            }
            return
        }
        guard authorization.permitsDelivery else { return }
        for plan in active {
            let requests = desired.filter { ($0.content.userInfo["planID"] as? String) == plan.id }
            do {
                for request in requests {
                    let existing = owned.first { $0.identifier == request.identifier }
                    if !Self.matches(existing, request) { try await client.add(request) }
                }
            } catch {
                client.remove(requests.map(\.identifier))
                errors[plan.id] = "Unable to schedule this reminder: \(error.localizedDescription)"
            }
        }
        let registered = await client.pending()
        for plan in active where errors[plan.id] == nil {
            let expected = configuration(for: plan.id).requests(planID: plan.id, name: plan.plan.name, app: app)
            if !expected.isEmpty && expected.allSatisfy({ request in
                Self.matches(registered.first { $0.identifier == request.identifier }, request)
            }) {
                scheduledPlanIDs.insert(plan.id)
            } else {
                client.remove(expected.map(\.identifier))
                errors[plan.id] = "This reminder was not registered. Please try saving it again."
            }
        }
    }

    private static func matches(_ existing: UNNotificationRequest?, _ desired: UNNotificationRequest) -> Bool {
        guard let existing, let trigger = existing.trigger as? UNCalendarNotificationTrigger,
              let desiredTrigger = desired.trigger as? UNCalendarNotificationTrigger else { return false }
        return existing.content.title == desired.content.title && existing.content.body == desired.content.body &&
            existing.content.userInfo["planID"] as? String == desired.content.userInfo["planID"] as? String &&
            existing.content.sound == nil && existing.content.badge == nil && existing.content.interruptionLevel == .active &&
            trigger.repeats && trigger.dateComponents == desiredTrigger.dateComponents
    }
}

enum ReminderError: LocalizedError {
    case invalidSchedule
    var errorDescription: String? { "Choose a valid time and at least one weekday." }
}
