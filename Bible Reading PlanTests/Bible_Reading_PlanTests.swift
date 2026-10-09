import Foundation
import XCTest
@testable import Bible_Reading_Plan

final class Bible_Reading_PlanTests: XCTestCase {
    private var root: URL!
    private let plans = ReadingPlan.previewPlans
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private let today = Date(timeIntervalSince1970: 1_791_540_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func repository(_ name: String = "store", defaults: UserDefaults? = nil,
                            sources: [URL] = [], clock: Date? = nil) -> ReadingPlanRepository {
        let date = clock ?? today
        return ReadingPlanRepository(directory: root.appendingPathComponent(name), bundled: plans,
                                     legacyDefaults: defaults, legacyDirectories: sources, calendar: calendar,
                                     clock: { date })
    }
    private func defaults() -> (UserDefaults, String) {
        let name = "BibleReadingPlanTests." + UUID().uuidString
        return (UserDefaults(suiteName: name)!, name)
    }
    private func importPlan(_ repository: ReadingPlanRepository, name: String = "Custom", id: Int = 1) throws -> String {
        let plan = ReadingPlan(id: id, name: name, days: plans[0].days)
        _ = try repository.importData(JSONEncoder().encode(plan))
        return try PlanCodec.importedID(for: plan)
    }
    private func seed(_ repository: ReadingPlanRepository, day: Int = 0, previousDate: Date? = nil) throws {
        _ = try repository.updateState {
            $0.selectedPlanIDs = ["bundled:1"]
            $0.progressByPlan = ["bundled:1": day]
            $0.lastAdvancedReadingDay = DailyProgress.dayIdentifier(previousDate ?? today.addingTimeInterval(-86400), calendar: calendar)
        }
    }

    func testBundledPlansDecodeAndHaveUniqueIDs() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ReadingPlans", withExtension: "json"))
        let bundled = try PlanCodec.decode(Data(contentsOf: url))
        XCTAssertFalse(bundled.isEmpty)
        XCTAssertEqual(Set(bundled.map(\.id)).count, bundled.count)
    }

    func testIdentityIgnoresIntegerIDAndNormalizesBookCode() throws {
        let a = ReadingPlan(id: 1, name: "Same", days: [Day(book: "jhn", startChapter: 1, endChapter: 1)])
        let b = ReadingPlan(id: 999, name: "Same", days: [Day(book: "JHN", startChapter: 1, endChapter: 1)])
        XCTAssertEqual(try PlanCodec.importedID(for: a), try PlanCodec.importedID(for: b))
        XCTAssertNotEqual(try PlanCodec.importedID(for: a), try PlanCodec.importedID(for: plans[0]))
    }

    func testSingleAndArrayUseSameDecoder() throws {
        XCTAssertEqual(try PlanCodec.decode(JSONEncoder().encode(plans[0])), [plans[0]])
        XCTAssertEqual(try PlanCodec.decode(JSONEncoder().encode(plans)), plans)
    }

    func testInvalidImportsAreRejectedWithoutWrites() throws {
        let repo = repository()
        let before = try repo.load()
        let invalid = [
            Data("[]".utf8), Data("garbage".utf8),
            try JSONEncoder().encode(ReadingPlan(id: 1, name: " ", days: plans[0].days)),
            try JSONEncoder().encode(ReadingPlan(id: 1, name: "Empty", days: [])),
            try JSONEncoder().encode(ReadingPlan(id: 1, name: "Bad book", days: [Day(book: "XXX", startChapter: 1, endChapter: 2)])),
            try JSONEncoder().encode(ReadingPlan(id: 1, name: "Bad chapter", days: [Day(book: "GEN", startChapter: 0, endChapter: 1)])),
            try JSONEncoder().encode(ReadingPlan(id: 1, name: "Backwards", days: [Day(book: "GEN", startChapter: 2, endChapter: 1)]))
        ]
        for data in invalid { XCTAssertThrowsError(try repo.importData(data)) }
        XCTAssertEqual(try repo.load(), before)
    }

    func testCollidingIDsRemainDistinctAndDuplicatesDoNotWrite() throws {
        let repo = repository()
        let first = try importPlan(repo, name: "First", id: 1)
        let second = try importPlan(repo, name: "Second", id: 1)
        XCTAssertNotEqual(first, second)
        let before = try repo.load()
        _ = try importPlan(repo, name: "First", id: 9)
        XCTAssertEqual(try repo.load(), before)
        XCTAssertEqual(before.catalog(bundled: plans).count, 4)
    }

    func testDeleteOnePlanFromArrayKeepsTheOther() throws {
        let repo = repository()
        _ = try repo.importData(JSONEncoder().encode(plans))
        let first = try PlanCodec.importedID(for: plans[0])
        let second = try PlanCodec.importedID(for: plans[1])
        _ = try repo.updateState { $0.selectedPlanIDs = [first, second]; $0.progressByPlan = [first: 1, second: 2] }
        let deleted = try repo.delete(id: first)
        XCTAssertEqual(deleted.envelope.state.selectedPlanIDs, [second])
        XCTAssertNil(deleted.envelope.state.progressByPlan[first])
        XCTAssertEqual(deleted.imports[first]?.deleted, true)
        XCTAssertEqual(deleted.imports[second]?.deleted, false)
        XCTAssertThrowsError(try repo.delete(id: "bundled:1"))
    }

    func testUnavailableOrUnwritableStorageDoesNotReportImportSuccess() throws {
        let noDirectory = ReadingPlanRepository(directory: nil, bundled: plans)
        XCTAssertThrowsError(try noDirectory.importData(JSONEncoder().encode(plans)))
        let file = root.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let invalid = ReadingPlanRepository(directory: file, bundled: plans)
        XCTAssertThrowsError(try invalid.importData(JSONEncoder().encode(plans)))
    }

    func testFirstLaunchSeedsDayWithoutAdvancing() throws {
        let repo = repository()
        _ = try repo.updateState { $0.selectedPlanIDs = ["bundled:1"]; $0.progressByPlan = ["bundled:1": 0] }
        XCTAssertEqual(try repo.advance(now: today, calendar: calendar).envelope.state.progressByPlan["bundled:1"], 0)
    }

    func testAdvancesOncePerDayAndNoOpLeavesFileUnchanged() throws {
        let repo = repository()
        try seed(repo)
        let result = try repo.advance(now: today, calendar: calendar)
        XCTAssertEqual(result.envelope.state.progressByPlan["bundled:1"], 1)
        let url = repo.directory!.appendingPathComponent("snapshot.json")
        let bytes = try Data(contentsOf: url)
        XCTAssertEqual(try repo.advance(now: today, calendar: calendar), result)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

    func testMissedDaysAdvanceOnlyOnceAndFinalDayCaps() throws {
        let repo = repository()
        try seed(repo, previousDate: today.addingTimeInterval(-86400 * 5))
        XCTAssertEqual(try repo.advance(now: today, calendar: calendar).envelope.state.progressByPlan["bundled:1"], 1)
        _ = try repo.updateState { $0.progressByPlan["bundled:1"] = 2 }
        XCTAssertEqual(try repo.advance(now: today.addingTimeInterval(86400), calendar: calendar).envelope.state.progressByPlan["bundled:1"], 2)
    }

    func testManualChangesAreClampedAndNotAdvancedAgainToday() throws {
        let repo = repository()
        try seed(repo)
        _ = try repo.advance(now: today, calendar: calendar)
        _ = try repo.updateState { $0.progressByPlan["bundled:1"] = -100 }
        XCTAssertEqual(try repo.advance(now: today, calendar: calendar).envelope.state.progressByPlan["bundled:1"], 0)
        _ = try repo.updateState { $0.progressByPlan["bundled:1"] = Int.max }
        XCTAssertEqual(try repo.load().envelope.state.progressByPlan["bundled:1"], 2)
    }

    func testMissingPlansKeepSelectionAndSkipAdvancement() throws {
        let repo = repository()
        try seed(repo)
        _ = try repo.updateState { $0.selectedPlanIDs.append("imported:missing"); $0.progressByPlan["imported:missing"] = 8 }
        let state = try repo.advance(now: today, calendar: calendar).envelope.state
        XCTAssertTrue(state.selectedPlanIDs.contains("imported:missing"))
        XCTAssertEqual(state.progressByPlan["imported:missing"], 8)
    }

    func testMigrationBacksUpStateAndFilesAndPreservesCheckpoint() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(42, forKey: "savedPlan"); prefs.set(1, forKey: "savedDay"); prefs.set(today, forKey: "lastCheckedDate")
        let imports = root.appendingPathComponent("Legacy")
        try FileManager.default.createDirectory(at: imports, withIntermediateDirectories: true)
        let plan = ReadingPlan(id: 42, name: "Legacy", days: plans[0].days)
        let file = imports.appendingPathComponent("plans.json")
        try JSONEncoder().encode(plan).write(to: file)
        let repo = repository(defaults: prefs, sources: [imports])
        let migrated = try repo.load()
        let id = try PlanCodec.importedID(for: plan)
        XCTAssertEqual(migrated.envelope.state.selectedPlanIDs, [id])
        XCTAssertEqual(migrated.envelope.state.progressByPlan[id], 1)
        XCTAssertEqual(try repo.advance(now: today, calendar: calendar).envelope.state.progressByPlan[id], 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo.directory!.appendingPathComponent("LegacyBackup/defaults.plist").path))
        XCTAssertEqual(prefs.integer(forKey: "savedPlan"), 42)
        XCTAssertEqual(try repo.load().imports.count, 1)
    }

    func testLegacyV1MarkerIsNotLostAndUnknownOrAmbiguousIDsAreRetained() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        let marker = DailyProgress.dayIdentifier(today, calendar: calendar)
        let json = "{\"selectedPlanIds\":[1,99],\"progressByPlan\":{\"1\":1,\"99\":6},\"lastAdvancedReadingDay\":\"\(marker)\"}"
        prefs.set(Data(json.utf8), forKey: "readingPlanState")
        let source = root.appendingPathComponent("Legacy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try JSONEncoder().encode(ReadingPlan(id: 1, name: "Conflicting", days: plans[0].days)).write(to: source.appendingPathComponent("a.json"))
        let repo = repository(defaults: prefs, sources: [source])
        let snapshot = try repo.load()
        XCTAssertEqual(snapshot.envelope.state.lastAdvancedReadingDay, marker)
        XCTAssertEqual(snapshot.envelope.state.unresolvedSelectedIDs, [1,99])
        XCTAssertEqual(snapshot.envelope.state.unresolvedProgress[99], 6)
        _ = try importPlan(repo, name: "Unrelated", id: 99)
        XCTAssertEqual(try repo.load().envelope.state.unresolvedSelectedIDs, [1,99])
    }

    func testLegacyJSONStringStorageAndSelectionOrder() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set("[2,1]", forKey: "selectedPlans"); prefs.set("{\"1\":1,\"2\":2}", forKey: "progressByPlan")
        let state = try repository(defaults: prefs).load().envelope.state
        XCTAssertEqual(state.selectedPlanIDs, ["bundled:2", "bundled:1"])
        XCTAssertEqual(state.progressByPlan["bundled:1"], 1)
    }

    func testCorruptLegacyImportIsPreservedAndReported() throws {
        let source = root.appendingPathComponent("Legacy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let file = source.appendingPathComponent("broken.json")
        try Data("broken".utf8).write(to: file)
        let repo = repository(sources: [source])
        XCTAssertEqual(try repo.load().loadErrors.count, 1)
        XCTAssertEqual(try Data(contentsOf: file), Data("broken".utf8))
        XCTAssertEqual(try repo.load().loadErrors.count, 1)
    }

    func testFailedMigrationCanRetryWithoutLosingLegacyData() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(1, forKey: "savedPlan")
        let directory = root.appendingPathComponent("store")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("LegacyBackup"))
        let repo = repository(defaults: prefs)
        XCTAssertThrowsError(try repo.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot.json").path))
        try FileManager.default.removeItem(at: directory.appendingPathComponent("LegacyBackup"))
        XCTAssertEqual(try repo.load().envelope.state.selectedPlanIDs, ["bundled:1"])
    }

    func testAppCanMigrateDocumentsAfterWidgetInitializedTheStore() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(42, forKey: "savedPlan")
        let widgetRepo = repository(defaults: prefs)
        let widgetSnapshot = try widgetRepo.load()
        XCTAssertEqual(widgetSnapshot.envelope.state.unresolvedSelectedIDs, [42])
        try widgetRepo.acknowledge(state: widgetSnapshot.envelope)
        let source = root.appendingPathComponent("DocumentsImports")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let plan = ReadingPlan(id: 42, name: "Later", days: plans[0].days)
        try JSONEncoder().encode(plan).write(to: source.appendingPathComponent("plan.json"))
        let appRepo = repository(defaults: prefs, sources: [source])
        let migrated = try appRepo.load()
        XCTAssertEqual(migrated.envelope.state.selectedPlanIDs, [try PlanCodec.importedID(for: plan)])
        XCTAssertTrue(migrated.statePending)
    }

    func testLastWriteWinsAndStaleAcknowledgementDoesNotClearNewEdits() throws {
        let repo = repository()
        try seed(repo)
        let local = try repo.load().envelope
        var remote = local
        remote.modifiedAt = local.modifiedAt.addingTimeInterval(10)
        remote.state.progressByPlan["bundled:1"] = 2
        XCTAssertEqual(try repo.merge(state: remote).envelope.state.progressByPlan["bundled:1"], 2)
        XCTAssertEqual(try repo.merge(state: local).envelope.state.progressByPlan["bundled:1"], 2)
        _ = try repo.updateState { $0.progressByPlan["bundled:1"] = 0 }
        try repo.acknowledge(state: remote)
        XCTAssertTrue(try repo.load().statePending)
    }

    func testTombstoneWinsOverStaleOfflineCopyAndReimportRestores() throws {
        let repo = repository()
        let id = try importPlan(repo)
        let original = try XCTUnwrap(repo.load().imports[id])
        _ = try repo.updateState { $0.selectedPlanIDs = [id]; $0.progressByPlan[id] = 1 }
        let deleted = try repo.delete(id: id)
        let tombstone = try XCTUnwrap(deleted.imports[id])
        XCTAssertTrue(try repo.merge(imports: [original]).imports[id]!.deleted)
        _ = try importPlan(repo)
        let restored = try XCTUnwrap(repo.load().imports[id])
        XCTAssertFalse(restored.deleted)
        XCTAssertGreaterThan(restored.modifiedAt, tombstone.modifiedAt)
        XCTAssertFalse(try repo.merge(imports: [tombstone]).imports[id]!.deleted)
    }

    func testCloudContentIsVerifiedBeforeReplacingCache() throws {
        let repo = repository()
        let id = try importPlan(repo)
        var corrupt = try XCTUnwrap(repo.load().imports[id])
        corrupt.plan = plans[1]
        corrupt.modifiedAt = today.addingTimeInterval(1)
        XCTAssertThrowsError(try repo.merge(imports: [corrupt]))
        XCTAssertEqual(try repo.load().imports[id]?.plan?.name, "Custom")
    }

    func testConcurrentAppAndWidgetMutationsAreAtomic() throws {
        let repo = repository()
        let widget = repository()
        try seed(repo)
        let failures = LockedFailures()
        DispatchQueue.concurrentPerform(iterations: 50) { index in
            do {
                if index.isMultiple(of: 2) {
                    _ = try repo.updateState { $0.progressByPlan["pending:\(index)"] = index }
                } else { _ = try widget.advance(now: today, calendar: calendar) }
            } catch { failures.add(error) }
        }
        XCTAssertEqual(failures.count, 0)
        let snapshot = try repo.load()
        XCTAssertEqual(snapshot.envelope.state.progressByPlan["bundled:1"], 1)
        XCTAssertEqual(snapshot.envelope.state.progressByPlan.keys.filter { $0.hasPrefix("pending:") }.count, 25)
    }

    func testFormattingAndReadingSnapshotBounds() {
        XCTAssertEqual(plans[0].days[0].toString(), "John 1")
        XCTAssertEqual(plans[1].days[0].toString(), "Psalms 1–2")
        let catalog = ReadingPlanSnapshot().catalog(bundled: plans)
        var state = ReadingPlanState()
        state.progressByPlan["bundled:1"] = -2
        XCTAssertEqual(ReadingSnapshot.resolve(id: "bundled:1", state: state, catalog: catalog)?.dayIndex, 0)
        state.progressByPlan["bundled:1"] = 999
        XCTAssertEqual(ReadingSnapshot.resolve(id: "bundled:1", state: state, catalog: catalog)?.progress, 1)
    }

    func testCloudStateArrivesBeforeContentAndOfflineRetryCompletes() async throws {
        let repo = repository()
        let cloud = FakeReadingPlanCloud()
        let id = try PlanCodec.importedID(for: plans[0])
        var state = ReadingPlanState()
        state.selectedPlanIDs = [id]; state.progressByPlan[id] = 1
        await cloud.setState(StateEnvelope(state: state, modifiedAt: today.addingTimeInterval(1)))
        let coordinator = ReadingPlanSyncCoordinator(repository: repo, cloud: cloud)
        try await coordinator.refresh()
        let before = try repo.load()
        XCTAssertEqual(before.envelope.state.selectedPlanIDs, [id])
        XCTAssertNil(ReadingSnapshot.resolve(id: id, state: before.envelope.state, catalog: before.catalog(bundled: plans)))
        await cloud.setImports([ImportedPlanRecord(id: id, plan: plans[0], deleted: false, modifiedAt: today, pending: false)])
        try await coordinator.refresh()
        XCTAssertEqual(try repo.load().imports[id]?.plan, plans[0])
        let localID = try importPlan(repo, name: "Offline")
        await cloud.setAvailable(false)
        do { _ = try await coordinator.uploadPending(); XCTFail("Expected unavailable cloud") } catch {}
        XCTAssertTrue(try repo.load().imports[localID]!.pending)
        await cloud.setAvailable(true)
        let synced = try await coordinator.uploadPending()
        XCTAssertEqual(synced.pendingCount, 0)
        XCTAssertNotNil(synced.lastSuccessfulSync)
        let uploads = await cloud.importUploads
        XCTAssertTrue(uploads.contains(localID))
    }

    func testCloudUploadFailureRetainsQueueAndDoesNotClaimSuccessfulSync() async throws {
        let repo = repository()
        _ = try importPlan(repo)
        let cloud = FakeReadingPlanCloud()
        await cloud.setFailUploads(true)
        let coordinator = ReadingPlanSyncCoordinator(repository: repo, cloud: cloud)
        do { _ = try await coordinator.uploadPending(); XCTFail("Expected upload failure") } catch {}
        XCTAssertNil(try repo.load().lastSuccessfulSync)
        XCTAssertEqual(try repo.load().pendingCount, 1)
        await cloud.setFailUploads(false)
        let retried = try await coordinator.uploadPending()
        XCTAssertEqual(retried.pendingCount, 0)
    }

    func testCloudDeletionRemovesSelectionAcrossDevices() async throws {
        let first = repository("first")
        let second = repository("second")
        let id = try importPlan(first)
        let cloud = FakeReadingPlanCloud()
        let a = ReadingPlanSyncCoordinator(repository: first, cloud: cloud)
        let b = ReadingPlanSyncCoordinator(repository: second, cloud: cloud)
        _ = try first.updateState { $0.selectedPlanIDs = [id]; $0.progressByPlan[id] = 1 }
        _ = try await a.uploadPending()
        try await b.refresh()
        XCTAssertEqual(try second.load().envelope.state.selectedPlanIDs, [id])
        _ = try first.delete(id: id)
        _ = try await a.uploadPending()
        try await b.refresh()
        XCTAssertTrue(try second.load().imports[id]!.deleted)
        XCTAssertTrue(try second.load().envelope.state.selectedPlanIDs.isEmpty)
    }

    func testOlderCloudDeliveryRequeuesAlreadyAcknowledgedNewerState() throws {
        let repo = repository()
        try seed(repo)
        let newer = try repo.load().envelope
        try repo.acknowledge(state: newer)
        XCTAssertFalse(try repo.load().statePending)
        var older = newer
        older.modifiedAt = newer.modifiedAt.addingTimeInterval(-1)
        older.state.progressByPlan["bundled:1"] = 2
        let repaired = try repo.merge(state: older)
        XCTAssertEqual(repaired.envelope, newer)
        XCTAssertTrue(repaired.statePending)
    }

    func testStaleImportAcknowledgementCannotClearQueuedDeletion() throws {
        let repo = repository()
        let id = try importPlan(repo)
        let uploaded = try XCTUnwrap(repo.load().imports[id])
        _ = try repo.delete(id: id)
        try repo.acknowledge(import: uploaded)
        XCTAssertTrue(try repo.load().imports[id]!.deleted)
        XCTAssertTrue(try repo.load().imports[id]!.pending)
    }

    func testMigrationDeduplicatesContentButKeepsBothLegacyAliases() throws {
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set("[42,43]", forKey: "selectedPlans")
        prefs.set("{\"42\":1,\"43\":2}", forKey: "progressByPlan")
        let source = root.appendingPathComponent("DuplicateLegacy")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let first = ReadingPlan(id: 42, name: "Same content", days: plans[0].days)
        let second = ReadingPlan(id: 43, name: first.name, days: first.days)
        try JSONEncoder().encode([first, second]).write(to: source.appendingPathComponent("plans.json"))
        let snapshot = try repository(defaults: prefs, sources: [source]).load()
        XCTAssertEqual(snapshot.imports.count, 1)
        XCTAssertEqual(snapshot.envelope.state.selectedPlanIDs, [try PlanCodec.importedID(for: first)])
        XCTAssertTrue(snapshot.envelope.state.unresolvedSelectedIDs.isEmpty)
        XCTAssertEqual(snapshot.envelope.state.progressByPlan[try PlanCodec.importedID(for: first)], 2)
    }

    func testDailyIdentifierUsesLocalDayAcrossDST() {
        let formatter = ISO8601DateFormatter()
        let beforeMidnight = formatter.date(from: "2026-11-01T03:59:00Z")!
        let afterMidnight = formatter.date(from: "2026-11-01T04:01:00Z")!
        XCTAssertEqual(DailyProgress.dayIdentifier(beforeMidnight, calendar: calendar), "2026-10-31")
        XCTAssertEqual(DailyProgress.dayIdentifier(afterMidnight, calendar: calendar), "2026-11-01")
        XCTAssertEqual(calendar.dateInterval(of: .day, for: afterMidnight)?.duration, 25 * 3600)
    }

    @MainActor
    func testRapidPickerGesturesPublishImmediatelyAndPersistLatestDay() async throws {
        let repo = repository()
        try seed(repo, previousDate: today)
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        let store = ReadingPlanStore(repository: repo, cloud: FakeReadingPlanCloud(), preferences: prefs)
        await store.activate(now: today, calendar: calendar)
        store.chooseDay(1, for: "bundled:1")
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 1)
        store.chooseDay(0, for: "bundled:1")
        store.chooseDay(2, for: "bundled:1")
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 2)
        await Task.yield()
        await store.activate(now: today, calendar: calendar)
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 2)
        XCTAssertEqual(try repo.load().envelope.state.progressByPlan["bundled:1"], 2)
    }

    @MainActor
    func testStoreActivationAcrossMidnightAndOverlappingCalls() async throws {
        let repo = repository()
        try seed(repo, previousDate: today)
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        var reloads = 0
        let store = ReadingPlanStore(repository: repo, cloud: FakeReadingPlanCloud(), preferences: prefs, reloadWidgets: { reloads += 1 })
        await store.activate(now: today, calendar: calendar)
        XCTAssertEqual(store.state.progressByPlan["bundled:1"], 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        async let first: Void = store.activate(now: tomorrow, calendar: calendar)
        async let second: Void = store.activate(now: tomorrow, calendar: calendar)
        _ = await (first, second)
        XCTAssertEqual(store.state.progressByPlan["bundled:1"], 1)
        let count = reloads
        await store.activate(now: tomorrow, calendar: calendar)
        XCTAssertEqual(reloads, count)
        await store.setDay(0, for: "bundled:1")
        XCTAssertEqual(store.state.progressByPlan["bundled:1"], 0)
        await store.activate(now: tomorrow, calendar: calendar)
        XCTAssertEqual(store.state.progressByPlan["bundled:1"], 0)
    }

    @MainActor
    func testStoreImportsThroughFileAndPublishesOfflineStatus() async throws {
        let repo = repository()
        let (prefs, name) = defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        let store = ReadingPlanStore(repository: repo, cloud: OfflineReadingPlanCloud(), preferences: prefs)
        await store.activate(now: today, calendar: calendar)
        let url = root.appendingPathComponent("fixture.json")
        try JSONEncoder().encode(plans[0]).write(to: url)
        await store.importPlan(from: url)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.plans.filter(\.isImported).count, 1)
        XCTAssertEqual(store.syncStatus, "Unavailable")
        XCTAssertGreaterThan(store.pendingCount, 0)
        XCTAssertNil(store.lastSuccessfulSync)
        let id = try PlanCodec.importedID(for: plans[0])
        await store.select(id, enabled: true)
        XCTAssertTrue(store.state.selectedPlanIDs.contains(id))
        await store.delete(id)
        XCTAssertFalse(store.state.selectedPlanIDs.contains(id))
    }
}

private final class LockedFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [Error] = []
    func add(_ error: Error) { lock.lock(); defer { lock.unlock() }; errors.append(error) }
    var count: Int { lock.lock(); defer { lock.unlock() }; return errors.count }
}

actor FakeReadingPlanCloud: ReadingPlanCloudTransport {
    private var available = true
    private var failUploads = false
    private var state: StateEnvelope?
    private var imports: [ImportedPlanRecord] = []
    private(set) var importUploads: [String] = []
    func setAvailable(_ available: Bool) { self.available = available }
    func setFailUploads(_ fail: Bool) { failUploads = fail }
    func setState(_ state: StateEnvelope) { self.state = state }
    func setImports(_ imports: [ImportedPlanRecord]) { self.imports = imports }
    func isAvailable() async throws -> Bool { available }
    func fetchState() async throws -> StateEnvelope? { state }
    func pushState(_ state: StateEnvelope) async throws {
        if failUploads { throw CloudSyncError.stateNotQueued }
        self.state = state
    }
    func fetchImports() async throws -> [ImportedPlanRecord] { imports }
    func pushImport(_ record: ImportedPlanRecord) async throws -> ImportedPlanRecord {
        if failUploads { throw CloudSyncError.unavailable }
        importUploads.append(record.id)
        if let remote = imports.first(where: { $0.id == record.id }), remote.modifiedAt > record.modifiedAt { return remote }
        imports.removeAll { $0.id == record.id }
        imports.append(record)
        return record
    }
}
