import Foundation
import SwiftUI
import Combine
import CloudKit
import WidgetKit

@MainActor
final class ReadingPlanStore: ObservableObject {
    @Published private(set) var plans: [CatalogPlan] = []
    @Published private(set) var state = ReadingPlanState()
    @Published private(set) var syncStatus = "Not checked"
    @Published private(set) var lastSuccessfulSync: Date?
    @Published private(set) var pendingCount = 0
    @Published private(set) var loadErrors: [String] = []
    @Published var errorMessage: String?
    @Published private(set) var isWorking = false

    let preferences: UserDefaults
    let repository: ReadingPlanRepository?
    private let coordinator: ReadingPlanSyncCoordinator?
    private let reloadWidgets: () -> Void
    private var queue: Task<Void, Never>?
    private var observers: Set<AnyCancellable> = []
    private var lastSnapshot: ReadingPlanSnapshot?
    private var isPreview = false
    private var pendingPickerDays: [String: (index: Int, token: UUID)] = [:]
    let uiTesting: Bool

    init(repository: ReadingPlanRepository?, cloud: any ReadingPlanCloudTransport,
         preferences: UserDefaults, observeCloud: Bool = false, uiTesting: Bool = false,
         reloadWidgets: @escaping () -> Void = {}) {
        self.repository = repository
        self.preferences = preferences
        self.reloadWidgets = reloadWidgets
        self.uiTesting = uiTesting
        coordinator = repository.map { ReadingPlanSyncCoordinator(repository: $0, cloud: cloud) }
        if observeCloud {
            for name in [NSUbiquitousKeyValueStore.didChangeExternallyNotification, Notification.Name.CKAccountChanged] {
                NotificationCenter.default.publisher(for: name).receive(on: DispatchQueue.main).sink { [weak self] notification in
                    if let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int,
                       reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                        Task { await self?.handleQuotaFailure() }
                        return
                    }
                    Task { await self?.activate() }
                }.store(in: &observers)
            }
        }
    }

    static func live() -> ReadingPlanStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") || NSClassFromString("XCTestCase") != nil {
            let name = ProcessInfo.processInfo.environment["UITEST_SESSION"] ?? UUID().uuidString
            let prefs = UserDefaults(suiteName: "BibleReadingPlan.UITests." + name)!
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("UITest-" + name)
            if ProcessInfo.processInfo.arguments.contains("--reset-test-state") {
                try? FileManager.default.removeItem(at: root)
                prefs.removePersistentDomain(forName: "BibleReadingPlan.UITests." + name)
            }
            let repository = ReadingPlanRepository(directory: root, bundled: ReadingPlan.previewPlans)
            return ReadingPlanStore(repository: repository, cloud: OfflineReadingPlanCloud(), preferences: prefs, uiTesting: true)
        }
        #endif
        do {
            return ReadingPlanStore(repository: try .live(), cloud: AppleReadingPlanCloud(),
                                    preferences: AppGroup.defaults, observeCloud: true,
                                    reloadWidgets: { WidgetCenter.shared.reloadAllTimelines() })
        } catch {
            let store = ReadingPlanStore(repository: nil, cloud: OfflineReadingPlanCloud(), preferences: AppGroup.defaults)
            store.errorMessage = error.localizedDescription
            return store
        }
    }

    static func preview(selected: Bool = true) -> ReadingPlanStore {
        let preferences = UserDefaults(suiteName: "BibleReadingPlan.Preview." + UUID().uuidString)!
        let store = ReadingPlanStore(repository: nil, cloud: OfflineReadingPlanCloud(), preferences: preferences)
        store.isPreview = true
        store.plans = ReadingPlan.previewPlans.map { CatalogPlan(id: "bundled:\($0.id)", plan: $0) }
        if selected {
            store.state.selectedPlanIDs = store.plans.map(\.id)
            for plan in store.plans { store.state.progressByPlan[plan.id] = 1 }
        }
        store.syncStatus = "Preview"
        return store
    }

    func reading(for id: String) -> ReadingSnapshot? { ReadingSnapshot.resolve(id: id, state: state, catalog: plans) }

    func activate(now: Date = Date(), calendar: Calendar = .current) async {
        guard !isPreview else { return }
        await enqueue { store in
            guard let repository = store.repository, let coordinator = store.coordinator else { return }
            store.isWorking = true
            defer { store.isWorking = false }
            do {
                store.publish(try await Task.detached { try repository.load() }.value)
                store.syncStatus = "Syncing…"
                var syncError: Error?
                do { try await coordinator.refresh() } catch { syncError = error }
                store.publish(try await Task.detached { try repository.advance(now: now, calendar: calendar) }.value)
                if syncError == nil {
                    do { store.publish(try await coordinator.uploadPending()) } catch { syncError = error }
                }
                store.finishSync(error: syncError)
            } catch { store.errorMessage = error.localizedDescription; store.syncStatus = "Unable to load" }
        }
    }

    func select(_ id: String, enabled: Bool) async {
        if isPreview { Self.editSelection(&state, id: id, enabled: enabled); return }
        await mutate { repository in
            try repository.updateState { Self.editSelection(&$0, id: id, enabled: enabled) }
        }
    }

    /// Picker bindings need a synchronous value while persistence/network work is queued.
    /// Preserve the most recent gesture across publications from earlier queued edits.
    func chooseDay(_ index: Int, for id: String) {
        guard let plan = plans.first(where: { $0.id == id })?.plan else { return }
        let day = min(max(0, index), max(0, plan.days.count - 1))
        guard state.progressByPlan[id] != day else { return }
        let token = UUID()
        pendingPickerDays[id] = (day, token)
        state.progressByPlan[id] = day
        Task {
            if !isPreview {
                await mutate({ repository in
                    try repository.updateState { $0.progressByPlan[id] = day }
                }, onlyIf: { $0.pendingPickerDays[id]?.token == token })
            }
            if pendingPickerDays[id]?.token == token {
                pendingPickerDays.removeValue(forKey: id)
                if let snapshot = lastSnapshot { publish(snapshot) }
            }
        }
    }

    func setDay(_ index: Int, for id: String) async {
        if isPreview { state.progressByPlan[id] = index; return }
        await mutate { repository in try repository.updateState { $0.progressByPlan[id] = index } }
    }

    func importPlan(from url: URL) async {
        await mutate { repository in
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            return try repository.importData(Data(contentsOf: url))
        }
    }

    // UI automation imports a fixture through the same codec, persistence, and coordinator path.
    func importTestFixture() async {
        guard uiTesting else { return }
        let plan = ReadingPlan(id: 1, name: "Imported UI Test Plan", days: ReadingPlan.previewPlans[0].days)
        await mutate { try $0.importData(JSONEncoder().encode(plan)) }
    }

    func delete(_ id: String) async {
        await mutate { try $0.delete(id: id) }
    }

    private nonisolated static func editSelection(_ state: inout ReadingPlanState, id: String, enabled: Bool) {
        if enabled {
            if !state.selectedPlanIDs.contains(id) { state.selectedPlanIDs.append(id) }
            if state.progressByPlan[id] == nil { state.progressByPlan[id] = 0 }
        } else {
            state.selectedPlanIDs.removeAll { $0 == id }
            state.progressByPlan.removeValue(forKey: id)
        }
    }

    private func mutate(_ operation: @escaping @Sendable (ReadingPlanRepository) throws -> ReadingPlanSnapshot,
                        onlyIf shouldRun: @escaping @MainActor (ReadingPlanStore) -> Bool = { _ in true }) async {
        await enqueue { store in
            guard shouldRun(store), let repository = store.repository else { return }
            store.isWorking = true
            defer { store.isWorking = false }
            do {
                let snapshot = try await Task.detached { try operation(repository) }.value
                let changed = store.lastSnapshot?.envelope != snapshot.envelope || store.lastSnapshot?.imports != snapshot.imports
                store.publish(snapshot)
                guard changed, let coordinator = store.coordinator else { return }
                store.syncStatus = "Syncing…"
                do {
                    try await coordinator.refresh()
                    store.publish(try await coordinator.uploadPending())
                    store.finishSync(error: nil)
                } catch {
                    store.publish(try await Task.detached { try repository.load() }.value)
                    store.finishSync(error: error)
                }
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func enqueue(_ operation: @escaping @MainActor (ReadingPlanStore) async -> Void) async {
        let previous = queue
        let task = Task { @MainActor in
            await previous?.value
            await operation(self)
        }
        queue = task
        await task.value
    }

    private func publish(_ snapshot: ReadingPlanSnapshot) {
        let newPlans = snapshot.catalog(bundled: repository?.bundled ?? [])
        var visibleState = snapshot.envelope.state
        for (id, pending) in pendingPickerDays where visibleState.selectedPlanIDs.contains(id) && newPlans.contains(where: { $0.id == id }) {
            visibleState.progressByPlan[id] = pending.index
        }
        let changed = lastSnapshot?.envelope.state != snapshot.envelope.state || plans != newPlans
        if state != visibleState { state = visibleState }
        if plans != newPlans { plans = newPlans }
        if lastSuccessfulSync != snapshot.lastSuccessfulSync { lastSuccessfulSync = snapshot.lastSuccessfulSync }
        if pendingCount != snapshot.pendingCount { pendingCount = snapshot.pendingCount }
        if loadErrors != snapshot.loadErrors { loadErrors = snapshot.loadErrors }
        lastSnapshot = snapshot
        if changed { reloadWidgets() }
    }

    private func handleQuotaFailure() async {
        await enqueue { store in
            guard let repository = store.repository else { return }
            do {
                store.publish(try await Task.detached { try repository.requeueState() }.value)
                store.syncStatus = "iCloud storage limit reached"
                store.syncFailure = CloudSyncError.stateTooLarge.localizedDescription
            } catch { store.errorMessage = error.localizedDescription }
        }
    }

    private func finishSync(error: Error?) {
        if let error {
            syncStatus = (error as? CloudSyncError) == .unavailable ? "Unavailable" : "Sync failed"
            // Keep network failures inline; importing/deleting is still successful locally.
            syncFailure = error.localizedDescription
        } else {
            let missingContent = state.selectedPlanIDs.contains { id in !plans.contains(where: { $0.id == id }) }
            syncStatus = missingContent ? "Waiting for plans" : (pendingCount == 0 ? "Up to date" : "Changes pending")
            syncFailure = missingContent ? "Selected plan content is unavailable. The app will retry downloading it when it becomes active." : nil
        }
    }

    @Published private(set) var syncFailure: String?
}
