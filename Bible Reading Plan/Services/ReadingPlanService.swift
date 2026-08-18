//
//  ReadingPlanService.swift
//  Bible Reading Plan
//
//  Created by Matt Greathouse on 2/18/25.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

enum AppGroup {
    static let suiteName = "group.bible.reading.plan.tracker"
    static let defaults = UserDefaults(suiteName: suiteName) ?? .standard
}

enum AppPreferenceKey {
    static let youVersionEnabled = "openWithYouVersionEnabled"
    static let logosEnabled = "openWithLogosEnabled"
}

struct ReadingPlanState: Codable, Equatable {
    var selectedPlanIds: [Int]
    var progressByPlan: [Int: Int]
    var lastAdvancedReadingDay: String? = nil

    static let empty = ReadingPlanState(selectedPlanIds: [], progressByPlan: [:])
}

enum ReadingPlanStateStore {
    static let stateKey = "readingPlanState"
    static let timestampKey = "readingPlanStateLastUpdated"
    private static let legacySelectedPlansKey = "selectedPlans"
    private static let legacyProgressKey = "progressByPlan"

    static func load(from defaults: UserDefaults) -> ReadingPlanState {
        if let data = defaults.data(forKey: stateKey),
           let state = decode(data) {
            return state
        }

        let ids = readLegacySelectedPlanIds(from: defaults)
        let progress = readLegacyProgressMap(from: defaults)
        let state = ReadingPlanState(selectedPlanIds: ids, progressByPlan: progress)

        if !ids.isEmpty || !progress.isEmpty {
            save(state, to: defaults)
        }

        return state
    }

    static func load(from data: Data, defaults: UserDefaults) -> ReadingPlanState {
        if let state = decode(data) {
            return state
        }
        return load(from: defaults)
    }

    static func save(_ state: ReadingPlanState, to defaults: UserDefaults, timestamp: Date = Date(), skipCloud: Bool = false) {
        if let data = encode(state) {
            defaults.set(data, forKey: stateKey)
        }
        defaults.set(timestamp.timeIntervalSince1970, forKey: timestampKey)
        // Keep legacy keys in sync for compatibility.
        if let data = try? JSONEncoder().encode(state.selectedPlanIds),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: legacySelectedPlansKey)
        }
        if let data = try? JSONEncoder().encode(state.progressByPlan),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: legacyProgressKey)
        }
        #if canImport(WidgetKit)
        if !Bundle.main.bundlePath.hasSuffix(".appex") {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
        if !skipCloud {
            ReadingPlanCloudSync.shared.pushIfNeeded(state: state, timestamp: timestamp)
        }
    }

    static func update(in defaults: UserDefaults, _ update: (inout ReadingPlanState) -> Void) {
        var state = load(from: defaults)
        update(&state)
        save(state, to: defaults)
    }

    static func decode(_ data: Data) -> ReadingPlanState? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(ReadingPlanState.self, from: data)
    }

    static func encode(_ state: ReadingPlanState) -> Data? {
        try? JSONEncoder().encode(state)
    }

    static func lastUpdatedTimestamp(in defaults: UserDefaults) -> TimeInterval {
        defaults.double(forKey: timestampKey)
    }

    private static func readLegacySelectedPlanIds(from defaults: UserDefaults) -> [Int] {
        guard let json = defaults.string(forKey: legacySelectedPlansKey),
              let data = json.data(using: .utf8),
              let ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }
        return ids
    }

    private static func readLegacyProgressMap(from defaults: UserDefaults) -> [Int: Int] {
        guard let json = defaults.string(forKey: legacyProgressKey),
              let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([Int: Int].self, from: data) else {
            return [:]
        }
        return map
    }
}

struct ReadingPlanMigration {
    struct Result {
        let selectedPlanIds: [Int]
        let progressMap: [Int: Int]
        let legacyPlanId: Int
        let legacyDay: Int
        let didMigrate: Bool
    }

    static func migrateLegacyIfNeeded(
        selectedPlanIds: [Int],
        progressMap: [Int: Int],
        legacyPlanId: Int,
        legacyDay: Int
    ) -> Result {
        var ids = selectedPlanIds
        var progress = progressMap
        var didMigrate = false

        if ids.isEmpty, legacyPlanId != 0 {
            ids = [legacyPlanId]
            progress[legacyPlanId] = legacyDay
            didMigrate = true
        }

        let shouldClearLegacy = legacyPlanId != 0 || legacyDay != 0
        let clearedLegacyPlanId = shouldClearLegacy ? 0 : legacyPlanId
        let clearedLegacyDay = shouldClearLegacy ? 0 : legacyDay

        return Result(
            selectedPlanIds: ids,
            progressMap: progress,
            legacyPlanId: clearedLegacyPlanId,
            legacyDay: clearedLegacyDay,
            didMigrate: didMigrate
        )
    }
}

final class ReadingPlanCloudSync {
    static let shared = ReadingPlanCloudSync()
    static var isEnabled = true
    static var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private let store = NSUbiquitousKeyValueStore.default
    private var isObserving = false
    private var isApplyingRemoteChange = false

    private init() {}

    func start() {
        guard Self.isEnabled, isICloudAvailable() else { return }
        if !isObserving {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleExternalChange),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: store
            )
            isObserving = true
        }
        refresh()
    }

    func refresh() {
        guard Self.isEnabled, isICloudAvailable() else { return }
        store.synchronize()
        pullFromCloudIfNewer()
    }

    func pushIfNeeded(state: ReadingPlanState, timestamp: Date) {
        guard Self.isEnabled, isICloudAvailable() else { return }
        guard !isApplyingRemoteChange else { return }
        guard let data = ReadingPlanStateStore.encode(state) else { return }
        store.set(data, forKey: ReadingPlanStateStore.stateKey)
        store.set(timestamp.timeIntervalSince1970, forKey: ReadingPlanStateStore.timestampKey)
        store.synchronize()
    }

    @objc private func handleExternalChange(_ notification: Notification) {
        pullFromCloudIfNewer()
    }

    private func pullFromCloudIfNewer() {
        guard let data = store.data(forKey: ReadingPlanStateStore.stateKey),
              let state = ReadingPlanStateStore.decode(data) else {
            return
        }

        let remoteTimestamp = store.double(forKey: ReadingPlanStateStore.timestampKey)
        let localTimestamp = ReadingPlanStateStore.lastUpdatedTimestamp(in: AppGroup.defaults)
        let localState = AppGroup.defaults.data(forKey: ReadingPlanStateStore.stateKey)
            .flatMap { ReadingPlanStateStore.decode($0) } ?? .empty
        let shouldApply: Bool
        if remoteTimestamp > localTimestamp {
            shouldApply = true
        } else if localTimestamp == 0, localState == .empty {
            shouldApply = true
        } else {
            shouldApply = false
        }

        guard shouldApply else { return }

        isApplyingRemoteChange = true
        let timestamp = remoteTimestamp > 0 ? Date(timeIntervalSince1970: remoteTimestamp) : Date()
        ReadingPlanStateStore.save(state, to: AppGroup.defaults, timestamp: timestamp, skipCloud: true)
        isApplyingRemoteChange = false
    }

    private func isICloudAvailable() -> Bool {
        Self.isAvailable
    }
}

class ReadingPlanService {
    static let shared = ReadingPlanService()
    
    private init() {}

    private enum DefaultsKey {
        static let lastCheckedDate = "lastCheckedDate"
    }

    private var appGroupDefaults: UserDefaults {
        AppGroup.defaults
    }

    private var legacyImportDirectoryURL: URL? {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("ImportedReadingPlans", isDirectory: true)
    }

    private var sharedImportDirectoryURL: URL? {
        let fm = FileManager.default
        guard let container = fm.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.suiteName) else {
            return nil
        }
        return container.appendingPathComponent("ImportedReadingPlans", isDirectory: true)
    }

    // Directory to store imported reading plan JSON files
    private var importDirectoryURL: URL? {
        let fm = FileManager.default
        guard let dir = sharedImportDirectoryURL ?? legacyImportDirectoryURL else { return nil }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    func loadReadingPlans() -> [ReadingPlan] {
        var allPlans: [ReadingPlan] = []
        // Reset sources mapping
        planSources = [:]
        migrateLegacyImportsIfNeeded()
        // Load bundled plans
        if let url = Bundle.main.url(forResource: "ReadingPlans", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            allPlans.append(contentsOf: plans)
        }

        // Load imported plans from Documents/ImportedReadingPlans
        if let dir = importDirectoryURL {
            let fm = FileManager.default
            if let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension.lowercased() == "json" {
                    if let data = try? Data(contentsOf: file) {
                        if let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
                            for p in plans { planSources[p.id] = file }
                            allPlans.append(contentsOf: plans)
                        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
                            planSources[plan.id] = file
                            allPlans.append(plan)
                        }
                    }
                }
            }
        }

        return allPlans
    }

    func advanceDailyProgressIfNeeded(now: Date = Date(), calendar: Calendar = .current, defaults: UserDefaults? = nil) {
        let usesAppGroupDefaults = defaults == nil
        let defaults = defaults ?? appGroupDefaults

        // The widget can invoke this method without the app having started iCloud sync,
        // so refresh before deciding whether today's advance has already happened.
        if usesAppGroupDefaults {
            ReadingPlanCloudSync.shared.refresh()
        }

        let todayIdentifier = readingDayIdentifier(for: now, calendar: calendar)
        var state = ReadingPlanStateStore.load(from: defaults)

        if state.lastAdvancedReadingDay == todayIdentifier {
            defaults.set(now, forKey: DefaultsKey.lastCheckedDate)
            return
        }

        // Preserve the pre-sync behavior for existing installs: a local checkpoint for
        // today means the plan has already been advanced, so seed the shared marker
        // without advancing it again.
        let legacyLastCheckedDate = defaults.object(forKey: DefaultsKey.lastCheckedDate) as? Date ?? now
        if state.lastAdvancedReadingDay == nil, calendar.isDate(legacyLastCheckedDate, inSameDayAs: now) {
            state.lastAdvancedReadingDay = todayIdentifier
            ReadingPlanStateStore.save(state, to: defaults)
            defaults.set(now, forKey: DefaultsKey.lastCheckedDate)
            return
        }

        let plans = loadReadingPlans()
        let planLengths = Dictionary(uniqueKeysWithValues: plans.map { ($0.id, max($0.days.count - 1, 0)) })

        let ids = state.selectedPlanIds
        var map = state.progressByPlan
        for id in ids {
            let current = map[id] ?? 0
            let maxIndex = planLengths[id] ?? current
            let next = min(current + 1, maxIndex)
            map[id] = next
        }

        state.progressByPlan = map
        state.lastAdvancedReadingDay = todayIdentifier
        ReadingPlanStateStore.save(state, to: defaults)

        defaults.set(now, forKey: DefaultsKey.lastCheckedDate)
    }

    private func readingDayIdentifier(for date: Date, calendar: Calendar) -> String {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        let components = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    // Import a reading plan JSON file (single plan or array of plans) and store a copy
    @discardableResult
    func importReadingPlan(from sourceURL: URL) throws -> [ReadingPlan] {
        let data = try Data(contentsOf: sourceURL)
        var imported: [ReadingPlan] = []
        if let plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            imported = plans
        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
            imported = [plan]
        } else {
            throw NSError(domain: "ReadingPlanService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format for reading plan"])
        }

        // Resolve ID conflicts against existing plans
        let existing = loadReadingPlans()
        var usedIds = Set(existing.map { $0.id })
        var adjusted: [ReadingPlan] = []
        for var p in imported {
            if usedIds.contains(p.id) {
                p = ReadingPlan(id: nextAvailableId(used: &usedIds), name: p.name, days: p.days)
            }
            usedIds.insert(p.id)
            adjusted.append(p)
        }

        // Persist adjusted data for future loads
        guard let destDir = importDirectoryURL else { return adjusted }
        let fm = FileManager.default
        let fileName = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueName = uniqueFileName(basename: fileName.isEmpty ? "ImportedPlan" : fileName, ext: "json", in: destDir)
        let destURL = destDir.appendingPathComponent(uniqueName)

        if fm.fileExists(atPath: destURL.path) {
            try? fm.removeItem(at: destURL)
        }

        let toWrite: Data
        if adjusted.count == 1, let only = adjusted.first {
            toWrite = try JSONEncoder().encode(only)
        } else {
            toWrite = try JSONEncoder().encode(adjusted)
        }
        try toWrite.write(to: destURL, options: .atomic)

        return adjusted
    }

    // Determine if a plan came from an imported file
    func isImported(planId: Int) -> Bool {
        return planSources[planId] != nil
    }

    // Delete a plan by ID. If the plan resides in a multi-plan file, remove just that plan; delete file if empty.
    @discardableResult
    func deletePlan(withId id: Int) throws -> [ReadingPlan] {
        guard let fileURL = planSources[id] else {
            throw NSError(domain: "ReadingPlanService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Plan is not imported or cannot be found"])
        }
        let fm = FileManager.default
        let data = try Data(contentsOf: fileURL)
        if var plans = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            plans.removeAll { $0.id == id }
            if plans.isEmpty {
                try fm.removeItem(at: fileURL)
            } else {
                let newData = try JSONEncoder().encode(plans)
                try newData.write(to: fileURL, options: .atomic)
            }
        } else if let plan = try? JSONDecoder().decode(ReadingPlan.self, from: data) {
            if plan.id == id {
                try fm.removeItem(at: fileURL)
            }
        } else {
            // If file is not decodable, remove it to avoid stale state
            try? fm.removeItem(at: fileURL)
        }

        // Reload to refresh planSources mapping
        return loadReadingPlans()
    }

    // MARK: - Helpers
    private var planSources: [Int: URL] = [:]

    private func migrateLegacyImportsIfNeeded() {
        guard let legacyDir = legacyImportDirectoryURL,
              let sharedDir = sharedImportDirectoryURL,
              legacyDir != sharedDir else {
            return
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyDir.path),
              let files = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil),
              !files.isEmpty else {
            return
        }

        _ = importDirectoryURL
        for file in files where file.pathExtension.lowercased() == "json" {
            let baseName = file.deletingPathExtension().lastPathComponent
            let safeBaseName = baseName.isEmpty ? "ImportedPlan" : baseName
            let destName = uniqueFileName(basename: safeBaseName, ext: "json", in: sharedDir)
            let destURL = sharedDir.appendingPathComponent(destName)
            do {
                try fm.moveItem(at: file, to: destURL)
            } catch {
                try? fm.copyItem(at: file, to: destURL)
            }
        }

        if let remaining = try? fm.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil),
           remaining.isEmpty {
            try? fm.removeItem(at: legacyDir)
        }
    }

    private func uniqueFileName(basename: String, ext: String, in directory: URL) -> String {
        let fm = FileManager.default
        var attempt = 0
        var candidate: String { attempt == 0 ? "\(basename).\(ext)" : "\(basename)-\(attempt).\(ext)" }
        while fm.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            attempt += 1
        }
        return candidate
    }

    private func nextAvailableId(used: inout Set<Int>) -> Int {
        var candidate = (used.max() ?? 0) + 1
        while used.contains(candidate) { candidate += 1 }
        return candidate
    }
}
