import Foundation
import Darwin
import CryptoKit

// Shared state lives in one atomically replaced snapshot, protected across app/widget processes.
enum AppGroup {
    static let suiteName = "group.bible.reading.plan.tracker"
    static let defaults = UserDefaults(suiteName: suiteName)!
    static var container: URL? { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName) }
}

enum AppPreferenceKey {
    static let youVersionEnabled = "openWithYouVersionEnabled"
    static let logosEnabled = "openWithLogosEnabled"
}

final class ReadingPlanRepository: @unchecked Sendable {
    let directory: URL?
    let bundled: [ReadingPlan]
    private let legacyDefaults: UserDefaults?
    private let legacyDirectories: [URL]
    private let clock: @Sendable () -> Date
    private let calendar: Calendar

    init(directory: URL?, bundled: [ReadingPlan], legacyDefaults: UserDefaults? = nil,
         legacyDirectories: [URL] = [], calendar: Calendar = .current,
         clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.bundled = bundled
        self.legacyDefaults = legacyDefaults
        self.legacyDirectories = legacyDirectories
        self.calendar = calendar
        self.clock = clock
    }

    static func live(isWidget: Bool = false) throws -> ReadingPlanRepository {
        guard let container = AppGroup.container,
              let url = Bundle.main.url(forResource: "ReadingPlans", withExtension: "json") else {
            throw PlanError.storageUnavailable
        }
        let bundled = try PlanCodec.decode(Data(contentsOf: url))
        var legacy = [container.appendingPathComponent("ImportedReadingPlans")]
        if !isWidget, let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            legacy.append(documents.appendingPathComponent("ImportedReadingPlans"))
        }
        return ReadingPlanRepository(directory: container.appendingPathComponent("ReadingPlanStoreV2"),
                                     bundled: bundled, legacyDefaults: AppGroup.defaults, legacyDirectories: legacy)
    }

    func load() throws -> ReadingPlanSnapshot { try transaction { _ in } }

    @discardableResult
    func updateState(_ edit: (inout ReadingPlanState) -> Void) throws -> ReadingPlanSnapshot {
        try transaction { snapshot in
            let previous = snapshot.envelope.state
            edit(&snapshot.envelope.state)
            normalize(&snapshot)
            if previous != snapshot.envelope.state { markStateChanged(&snapshot) }
        }
    }

    func advance(now: Date, calendar: Calendar = .current) throws -> ReadingPlanSnapshot {
        try advanceLocked(now: now, calendar: calendar)
    }

    fileprivate func advanceLocked(now: Date, calendar: Calendar) throws -> ReadingPlanSnapshot {
        try transaction { snapshot in
            let previous = snapshot.envelope.state
            DailyProgress.advance(&snapshot.envelope.state, catalog: snapshot.catalog(bundled: bundled), now: now, calendar: calendar)
            if previous != snapshot.envelope.state { markStateChanged(&snapshot) }
        }
    }

    @discardableResult
    func importData(_ data: Data) throws -> ReadingPlanSnapshot {
        let plans = try PlanCodec.decode(data)
        let records = try plans.map { (try PlanCodec.importedID(for: $0), $0) }
        return try transaction { snapshot in
            for (id, plan) in records {
                // A duplicate active import is a no-op; reimporting a tombstone is intentional restoration.
                if let old = snapshot.imports[id], !old.deleted { continue }
                let date = nextDate(after: snapshot.imports[id]?.modifiedAt)
                snapshot.imports[id] = ImportedPlanRecord(id: id, plan: plan, deleted: false, modifiedAt: date, pending: true)
            }
        }
    }

    @discardableResult
    func delete(id: String) throws -> ReadingPlanSnapshot {
        try transaction { snapshot in
            guard let old = snapshot.imports[id] else { throw PlanError.invalidPlan("Only imported plans can be deleted.") }
            guard !old.deleted else { return }
            snapshot.imports[id] = ImportedPlanRecord(id: id, plan: nil, deleted: true,
                                                      modifiedAt: nextDate(after: old.modifiedAt), pending: true)
            removeSelection(id, from: &snapshot)
        }
    }

    func merge(state remote: StateEnvelope?) throws -> ReadingPlanSnapshot {
        try transaction { snapshot in
            guard var remote else { return }
            if remote.modifiedAt < snapshot.envelope.modifiedAt {
                // Repair a late delivery of an older cloud value, even if our earlier upload was acknowledged.
                snapshot.statePending = true
                return
            }
            guard remote.modifiedAt > snapshot.envelope.modifiedAt else { return }
            // Unknown legacy entries are local and must not acquire another device's integer mapping.
            remote.state.unresolvedSelectedIDs = snapshot.envelope.state.unresolvedSelectedIDs
            remote.state.unresolvedProgress = snapshot.envelope.state.unresolvedProgress
            snapshot.envelope = remote
            snapshot.statePending = false
            let before = snapshot.envelope.state
            normalize(&snapshot)
            if before != snapshot.envelope.state { markStateChanged(&snapshot) }
        }
    }

    func merge(imports records: [ImportedPlanRecord]) throws -> ReadingPlanSnapshot {
        // Verify all downloads before entering the transaction, so malformed remote content cannot replace local data.
        for record in records where !record.deleted {
            guard let plan = record.plan, try PlanCodec.importedID(for: plan) == record.id else {
                throw PlanError.invalidCloudRecord
            }
        }
        return try transaction { snapshot in
            for var record in records {
                if let old = snapshot.imports[record.id] {
                    guard record.modifiedAt > old.modifiedAt ||
                            (record.modifiedAt == old.modifiedAt && record.deleted && !old.deleted) else { continue }
                }
                record.pending = false
                snapshot.imports[record.id] = record
            }
            let before = snapshot.envelope.state
            normalize(&snapshot)
            if before != snapshot.envelope.state { markStateChanged(&snapshot) }
        }
    }

    func acknowledge(import record: ImportedPlanRecord) throws {
        _ = try transaction { snapshot in
            guard snapshot.imports[record.id]?.modifiedAt == record.modifiedAt,
                  snapshot.imports[record.id]?.deleted == record.deleted else { return }
            snapshot.imports[record.id]?.pending = false
        }
    }

    func acknowledge(state envelope: StateEnvelope) throws {
        _ = try transaction { snapshot in
            if snapshot.envelope == envelope { snapshot.statePending = false }
        }
    }

    func requeueState() throws -> ReadingPlanSnapshot {
        try transaction { $0.statePending = true }
    }

    func recordSuccessfulSync(_ date: Date) throws -> ReadingPlanSnapshot {
        try transaction { $0.lastSuccessfulSync = date }
    }

    private func markStateChanged(_ snapshot: inout ReadingPlanSnapshot) {
        snapshot.envelope.modifiedAt = nextDate(after: snapshot.envelope.modifiedAt)
        snapshot.statePending = true
    }

    private func nextDate(after old: Date?) -> Date {
        max(clock(), (old ?? .distantPast).addingTimeInterval(0.001))
    }

    private func removeSelection(_ id: String, from snapshot: inout ReadingPlanSnapshot) {
        let before = snapshot.envelope.state
        snapshot.envelope.state.selectedPlanIDs.removeAll { $0 == id }
        snapshot.envelope.state.progressByPlan.removeValue(forKey: id)
        if before != snapshot.envelope.state { markStateChanged(&snapshot) }
    }

    private func normalize(_ snapshot: inout ReadingPlanSnapshot) {
        var seen = Set<String>()
        snapshot.envelope.state.selectedPlanIDs = snapshot.envelope.state.selectedPlanIDs.filter { seen.insert($0).inserted }
        for item in snapshot.catalog(bundled: bundled) {
            if let value = snapshot.envelope.state.progressByPlan[item.id] {
                snapshot.envelope.state.progressByPlan[item.id] = min(max(0, value), max(0, item.plan.days.count - 1))
            }
        }
        for record in snapshot.imports.values where record.deleted {
            snapshot.envelope.state.selectedPlanIDs.removeAll { $0 == record.id }
            snapshot.envelope.state.progressByPlan.removeValue(forKey: record.id)
        }
    }

    /// The lock inode is never replaced. Each call opens a separate descriptor, including within one process.
    private func transaction(_ edit: (inout ReadingPlanSnapshot) throws -> Void) throws -> ReadingPlanSnapshot {
        guard let directory else { throw PlanError.storageUnavailable }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(descriptor, LOCK_UN) }
        let file = directory.appendingPathComponent("snapshot.json")
        var snapshot: ReadingPlanSnapshot
        let exists = fm.fileExists(atPath: file.path)
        if exists {
            snapshot = try JSONDecoder().decode(ReadingPlanSnapshot.self, from: Data(contentsOf: file))
            guard snapshot.version == 2 else { throw PlanError.invalidPlan("Unsupported reading-plan storage version.") }
        } else {
            snapshot = try migrate(directory: directory)
        }
        let previous = snapshot
        try migrateAdditionalDirectories(&snapshot, directory: directory)
        try edit(&snapshot)
        if !exists || snapshot != previous {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: file, options: .atomic)
        }
        return snapshot
    }

    private func migrate(directory: URL) throws -> ReadingPlanSnapshot {
        var snapshot = ReadingPlanSnapshot()
        guard let defaults = legacyDefaults else { return snapshot }
        let keys = ["readingPlanState", "readingPlanStateLastUpdated", "selectedPlans", "progressByPlan", "savedPlan", "savedDay", "lastCheckedDate"]
        var backup: [String: Any] = [:]
        for key in keys { backup[key] = defaults.object(forKey: key) }
        let backupDir = directory.appendingPathComponent("LegacyBackup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let backupURL = backupDir.appendingPathComponent("defaults.plist")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try PropertyListSerialization.data(fromPropertyList: backup, format: .binary, options: 0).write(to: backupURL, options: .atomic)
        }
        struct Legacy: Decodable {
            var selectedPlanIds: [Int]
            var progressByPlan: [Int: Int]
            var lastAdvancedReadingDay: String?
        }
        let legacy = defaults.data(forKey: "readingPlanState").flatMap { try? JSONDecoder().decode(Legacy.self, from: $0) }
        func read<T: Decodable>(_ key: String, as: T.Type) -> T? {
            defaults.string(forKey: key).flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
        }
        var ids = legacy?.selectedPlanIds ?? read("selectedPlans", as: [Int].self) ?? []
        var progress = legacy?.progressByPlan ?? read("progressByPlan", as: [Int: Int].self) ?? [:]
        if ids.isEmpty, defaults.integer(forKey: "savedPlan") != 0 {
            let id = defaults.integer(forKey: "savedPlan")
            ids = [id]; progress[id] = defaults.integer(forKey: "savedDay")
        }
        snapshot.envelope.state.unresolvedSelectedIDs = ids
        snapshot.envelope.state.unresolvedProgress = progress
        snapshot.envelope.state.lastAdvancedReadingDay = legacy?.lastAdvancedReadingDay
        if snapshot.envelope.state.lastAdvancedReadingDay == nil,
           let checkpoint = defaults.object(forKey: "lastCheckedDate") as? Date {
            snapshot.envelope.state.lastAdvancedReadingDay = DailyProgress.dayIdentifier(checkpoint, calendar: calendar)
        }
        snapshot.envelope.modifiedAt = Date(timeIntervalSince1970: defaults.double(forKey: "readingPlanStateLastUpdated"))
        snapshot.statePending = !ids.isEmpty || !progress.isEmpty
        // Local imports must be loaded before resolving their legacy integer IDs.
        try migrateAdditionalDirectories(&snapshot, directory: directory, isInitial: true)
        resolveLegacy(&snapshot)
        normalize(&snapshot)
        return snapshot
    }

    private func migrateAdditionalDirectories(_ snapshot: inout ReadingPlanSnapshot, directory: URL, isInitial: Bool = false) throws {
        let previousState = snapshot.envelope.state
        let fm = FileManager.default
        var didScan = false
        for source in legacyDirectories where fm.fileExists(atPath: source.path) {
            // Per-source marker also permits the app to migrate Documents after a widget initialized storage.
            let digest = SHA256.hash(data: Data(source.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
            guard !snapshot.migratedSources.contains(source.path) else { continue }
            try fm.createDirectory(at: directory.appendingPathComponent("LegacyBackup"), withIntermediateDirectories: true)
            let backup = directory.appendingPathComponent("LegacyBackup/imports-" + String(digest.suffix(12)))
            if !fm.fileExists(atPath: backup.path) { try fm.copyItem(at: source, to: backup) }
            let files = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            for file in files where file.pathExtension.lowercased() == "json" {
                do {
                    for plan in try PlanCodec.decode(Data(contentsOf: file)) {
                        let id = try PlanCodec.importedID(for: plan)
                        if !(snapshot.legacyAliases[plan.id] ?? []).contains(id) {
                            snapshot.legacyAliases[plan.id, default: []].append(id)
                        }
                        if snapshot.imports[id] == nil {
                            // Migrating an old copy must not make it newer than an existing cloud tombstone.
                            let attributes = try fm.attributesOfItem(atPath: file.path)
                            let modifiedAt = attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
                            snapshot.imports[id] = ImportedPlanRecord(id: id, plan: plan, deleted: false,
                                                                      modifiedAt: modifiedAt, pending: true)
                        }
                    }
                } catch {
                    let message = "Could not load \(file.lastPathComponent): \(error.localizedDescription) Your saved copy was preserved; fix the JSON file and import it again."
                    if !snapshot.loadErrors.contains(message) { snapshot.loadErrors.append(message) }
                }
            }
            // The migration marker is part of the same atomic commit as the imported plans.
            snapshot.migratedSources.append(source.path)
            didScan = true
        }
        if didScan {
            resolveLegacy(&snapshot)
            normalize(&snapshot)
            if !isInitial, snapshot.envelope.state != previousState { markStateChanged(&snapshot) }
        }
    }

    private func resolveLegacy(_ snapshot: inout ReadingPlanSnapshot) {
        func resolve(_ id: Int) -> String? {
            var candidates = Set(snapshot.legacyAliases[id] ?? [])
            if bundled.contains(where: { $0.id == id }) { candidates.insert("bundled:\(id)") }
            return candidates.count == 1 ? candidates.first : nil
        }
        var unresolved: [Int] = []
        for id in snapshot.envelope.state.unresolvedSelectedIDs {
            if let stableID = resolve(id) {
                if !snapshot.envelope.state.selectedPlanIDs.contains(stableID) { snapshot.envelope.state.selectedPlanIDs.append(stableID) }
            } else { unresolved.append(id) }
        }
        snapshot.envelope.state.unresolvedSelectedIDs = unresolved
        var migratedProgress: [String: Int] = [:]
        for (id, progress) in snapshot.envelope.state.unresolvedProgress {
            if let stableID = resolve(id) {
                migratedProgress[stableID] = max(migratedProgress[stableID] ?? 0, progress)
                snapshot.envelope.state.unresolvedProgress.removeValue(forKey: id)
            }
        }
        // Consolidate duplicate legacy copies deterministically; do not overwrite newer known progress.
        for (id, progress) in migratedProgress where snapshot.envelope.state.progressByPlan[id] == nil {
            snapshot.envelope.state.progressByPlan[id] = progress
        }
    }
}
