import Foundation
import CloudKit

protocol ReadingPlanCloudTransport: Sendable {
    func isAvailable() async throws -> Bool
    func fetchState() async throws -> StateEnvelope?
    func pushState(_ state: StateEnvelope) async throws
    func fetchImports() async throws -> [ImportedPlanRecord]
    /// Returns the accepted record, which may be a newer server revision.
    func pushImport(_ record: ImportedPlanRecord) async throws -> ImportedPlanRecord
}

enum CloudSyncError: LocalizedError, Equatable {
    case unavailable, stateTooLarge, stateNotQueued
    var errorDescription: String? {
        switch self {
        case .unavailable: return "iCloud is unavailable. Changes are saved on this device and will retry when the app becomes active."
        case .stateTooLarge: return "Reading-plan selections exceed iCloud's storage limit. Local changes are preserved."
        case .stateNotQueued: return "iCloud could not queue the progress update. It will be retried."
        }
    }
}

actor AppleReadingPlanCloud: ReadingPlanCloudTransport {
    static let containerIdentifier = "iCloud.mattgreat.house.Bible-Reading-Plan"
    static let stateKey = "readingPlanState.v2"
    private let container = CKContainer(identifier: containerIdentifier)
    private let keyValueStore = NSUbiquitousKeyValueStore.default
    private var database: CKDatabase { container.privateCloudDatabase }

    func isAvailable() async throws -> Bool {
        try await container.accountStatus() == .available
    }

    func fetchState() async throws -> StateEnvelope? {
        keyValueStore.synchronize()
        if let data = keyValueStore.data(forKey: Self.stateKey) {
            return try JSONDecoder().decode(StateEnvelope.self, from: data)
        }
        // Legacy cloud integers are only safe to associate with bundled plans.
        struct Legacy: Decodable {
            let selectedPlanIds: [Int]
            let progressByPlan: [Int: Int]
            let lastAdvancedReadingDay: String?
        }
        guard let data = keyValueStore.data(forKey: "readingPlanState") else { return nil }
        let legacy = try JSONDecoder().decode(Legacy.self, from: data)
        var state = ReadingPlanState()
        state.selectedPlanIDs = legacy.selectedPlanIds.filter { $0 == 1 || $0 == 2 }.map { "bundled:\($0)" }
        for (id, day) in legacy.progressByPlan where id == 1 || id == 2 { state.progressByPlan["bundled:\(id)"] = day }
        state.lastAdvancedReadingDay = legacy.lastAdvancedReadingDay
        return StateEnvelope(state: state, modifiedAt: Date(timeIntervalSince1970: keyValueStore.double(forKey: "readingPlanStateLastUpdated")))
    }

    func pushState(_ envelope: StateEnvelope) async throws {
        var shared = envelope
        shared.state.unresolvedSelectedIDs = []
        shared.state.unresolvedProgress = [:]
        let data = try JSONEncoder().encode(shared)
        // Leave room for the retained legacy keys in the application's 1 MB KVS quota.
        guard data.count < 900_000 else { throw CloudSyncError.stateTooLarge }
        keyValueStore.set(data, forKey: Self.stateKey)
        guard keyValueStore.synchronize() else { throw CloudSyncError.stateNotQueued }
    }

    func fetchImports() async throws -> [ImportedPlanRecord] {
        let query = CKQuery(recordType: "ImportedReadingPlan", predicate: NSPredicate(value: true))
        var page = try await database.records(matching: query, resultsLimit: 100)
        var records: [ImportedPlanRecord] = []
        while true {
            for (_, result) in page.matchResults {
                records.append(try decode(result.get()))
            }
            guard let cursor = page.queryCursor else { break }
            page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
        }
        return records
    }

    func pushImport(_ local: ImportedPlanRecord) async throws -> ImportedPlanRecord {
        let recordID = CKRecord.ID(recordName: local.id)
        for _ in 0..<3 {
            var record: CKRecord
            do {
                record = try await database.record(for: recordID)
                let remote = try decode(record)
                if remote.modifiedAt > local.modifiedAt ||
                    (remote.modifiedAt == local.modifiedAt && remote.deleted && !local.deleted) { return remote }
            } catch let error as CKError where error.code == .unknownItem {
                record = CKRecord(recordType: "ImportedReadingPlan", recordID: recordID)
            }
            record["deleted"] = NSNumber(value: local.deleted)
            record["modifiedAt"] = local.modifiedAt as NSDate
            // CKAsset must remain on disk until the awaited operation completes.
            let assetURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
            defer { try? FileManager.default.removeItem(at: assetURL) }
            if let plan = local.plan, !local.deleted {
                try JSONEncoder().encode(plan).write(to: assetURL, options: .atomic)
                record["content"] = CKAsset(fileURL: assetURL)
            } else { record["content"] = nil }
            do {
                let result = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
                guard let saved = result.saveResults[recordID] else { throw PlanError.invalidCloudRecord }
                return try decode(saved.get())
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            }
        }
        throw CKError(.serverRecordChanged)
    }

    private func decode(_ record: CKRecord) throws -> ImportedPlanRecord {
        guard record.recordID.recordName.hasPrefix("imported:"),
              let deleted = record["deleted"] as? NSNumber,
              let date = record["modifiedAt"] as? Date else { throw PlanError.invalidCloudRecord }
        var plan: ReadingPlan?
        if !deleted.boolValue {
            guard let asset = record["content"] as? CKAsset, let url = asset.fileURL else { throw PlanError.invalidCloudRecord }
            let plans = try PlanCodec.decode(Data(contentsOf: url))
            guard plans.count == 1, try PlanCodec.importedID(for: plans[0]) == record.recordID.recordName else {
                throw PlanError.invalidCloudRecord
            }
            plan = plans[0]
        }
        return ImportedPlanRecord(id: record.recordID.recordName, plan: plan, deleted: deleted.boolValue, modifiedAt: date, pending: false)
    }
}

/// Network access never holds the file lock. Acknowledgements match revisions to preserve concurrent widget edits.
struct ReadingPlanSyncCoordinator: Sendable {
    let repository: ReadingPlanRepository
    let cloud: any ReadingPlanCloudTransport

    func refresh() async throws {
        guard try await cloud.isAvailable() else { throw CloudSyncError.unavailable }
        let remoteState = try await cloud.fetchState()
        _ = try await Task.detached { try repository.merge(state: remoteState) }.value
        let records = try await cloud.fetchImports()
        _ = try await Task.detached { try repository.merge(imports: records) }.value
    }

    func uploadPending() async throws -> ReadingPlanSnapshot {
        guard try await cloud.isAvailable() else { throw CloudSyncError.unavailable }
        var snapshot = try await Task.detached { try repository.load() }.value
        for local in snapshot.imports.values.filter(\.pending).sorted(by: { $0.id < $1.id }) {
            let accepted = try await cloud.pushImport(local)
            _ = try await Task.detached { try repository.merge(imports: [accepted]) }.value
            try await Task.detached { try repository.acknowledge(import: accepted) }.value
        }
        // Tombstone application may have changed the state; never upload the pre-merge snapshot.
        snapshot = try await Task.detached { try repository.load() }.value
        if snapshot.statePending {
            // Refresh KVS again before uploading, to avoid pushing over a received newer revision.
            let remote = try await cloud.fetchState()
            snapshot = try await Task.detached { try repository.merge(state: remote) }.value
            if snapshot.statePending {
                let envelope = snapshot.envelope
                try await cloud.pushState(envelope)
                try await Task.detached { try repository.acknowledge(state: envelope) }.value
            }
        }
        return try await Task.detached { try repository.recordSuccessfulSync(Date()) }.value
    }
}

actor OfflineReadingPlanCloud: ReadingPlanCloudTransport {
    func isAvailable() async throws -> Bool { false }
    func fetchState() async throws -> StateEnvelope? { nil }
    func pushState(_ state: StateEnvelope) async throws { throw CloudSyncError.unavailable }
    func fetchImports() async throws -> [ImportedPlanRecord] { [] }
    func pushImport(_ record: ImportedPlanRecord) async throws -> ImportedPlanRecord { throw CloudSyncError.unavailable }
}
