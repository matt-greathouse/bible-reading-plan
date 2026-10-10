import XCTest
import UserNotifications
@testable import Bible_Reading_Plan

@MainActor
private final class FakeNotificationClient: ReminderNotificationClient {
    var auth = ReminderAuthorization.allowed
    var requests: [String: UNNotificationRequest] = [:]
    var permissionRequests = 0
    var authorizationReads = 0
    var additions = 0
    var failure = false
    var silentlyDrop = false
    var removedDelivered: [String] = []
    var onAdd: (() async -> Void)?
    func authorization() async -> ReminderAuthorization { authorizationReads += 1; return auth }
    func requestPermission() async throws { permissionRequests += 1; auth = .blocked }
    func pending() async -> [UNNotificationRequest] { Array(requests.values) }
    func add(_ request: UNNotificationRequest) async throws {
        additions += 1
        let callback = onAdd
        onAdd = nil
        await callback?()
        if failure { throw NSError(domain: "Tests", code: 1) }
        if !silentlyDrop { requests[request.identifier] = request }
    }
    func remove(_ ids: [String]) { ids.forEach { requests.removeValue(forKey: $0) } }
    func removeDelivered(_ ids: [String]) { removedDelivered += ids }
}

@MainActor
private final class FakeURLOpener {
    var result = false
    var urls: [URL] = []
    func open(_ url: URL) async -> Bool { urls.append(url); return result }
}

@MainActor
final class ReadingReminderTests: XCTestCase {
    private var preferences: UserDefaults!
    private var suite: String!
    private var client: FakeNotificationClient!
    private var manager: ReadingReminderManager!
    private var plans: [CatalogPlan] { ReadingPlan.previewPlans.map { CatalogPlan(id: "bundled:\($0.id)", plan: $0) } }

    override func setUp() async throws {
        suite = "ReminderTests." + UUID().uuidString
        preferences = UserDefaults(suiteName: suite)!
        client = FakeNotificationClient()
        manager = ReadingReminderManager(preferences: preferences, client: client)
    }
    override func tearDown() async throws { preferences.removePersistentDomain(forName: suite) }

    private func reconcile(selected: [String] = ["bundled:1", "bundled:2"], deleted: Set<String> = [], app: BibleApp = .youVersion) async {
        await manager.reconcile(plans: plans, selected: selected, deleted: deleted, app: app)
    }

    func testDefaultsPersistenceAndScheduleValidation() async throws {
        XCTAssertEqual(manager.configuration(for: "bundled:1"), PlanReminder())
        let configuration = PlanReminder(enabled: true, hour: 19, minute: 30, weekdays: [2, 4, 6])
        try await manager.save(configuration, for: "bundled:1")
        let restored = ReadingReminderManager(preferences: preferences, client: client)
        XCTAssertEqual(restored.configuration(for: "bundled:1"), configuration)
        XCTAssertNil(preferences.object(forKey: "progressByPlan"))
        do {
            try await manager.save(PlanReminder(enabled: true, weekdays: []), for: "bundled:2")
            XCTFail("Empty weekdays must not save")
        } catch { XCTAssertTrue(error is ReminderError) }
    }

    func testIndependentSchedulesAndIdempotentReconciliation() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        try await manager.save(PlanReminder(enabled: true, hour: 19, weekdays: [2, 4, 6]), for: "bundled:2")
        await reconcile()
        XCTAssertEqual(client.requests.count, 4)
        XCTAssertEqual(manager.scheduledPlanIDs, ["bundled:1", "bundled:2"])
        let daily = try XCTUnwrap(client.requests[ReadingReminderManager.prefix + "bundled:1.daily"])
        let trigger = try XCTUnwrap(daily.trigger as? UNCalendarNotificationTrigger)
        XCTAssertTrue(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.hour, 8)
        XCTAssertNil(trigger.dateComponents.weekday)
        XCTAssertNil(trigger.dateComponents.timeZone)
        XCTAssertNil(daily.content.sound)
        XCTAssertNil(daily.content.badge)
        XCTAssertEqual(daily.content.interruptionLevel, .active)
        XCTAssertEqual(daily.content.userInfo["planID"] as? String, "bundled:1")
        XCTAssertFalse(daily.content.body.contains("John"))
        await reconcile()
        XCTAssertEqual(client.additions, 4)
        let weekly = try XCTUnwrap(client.requests[ReadingReminderManager.prefix + "bundled:2.4"])
        XCTAssertEqual((weekly.trigger as? UNCalendarNotificationTrigger)?.dateComponents.weekday, 4)
    }

    func testDeselectionPausesReselectionResumesAndDeletionRemovesPreferences() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        await reconcile()
        await reconcile(selected: [])
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(manager.configuration(for: "bundled:1").enabled)
        await reconcile()
        XCTAssertEqual(client.requests.count, 1)
        await reconcile(selected: [], deleted: ["bundled:1"])
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertNil(manager.configurations["bundled:1"])
        XCTAssertFalse(client.removedDelivered.isEmpty)
    }

    func testEditsCancelOldDaysAndUpdateDestinationCopy() async throws {
        try await manager.save(PlanReminder(enabled: true, weekdays: [2, 4]), for: "bundled:1")
        await reconcile()
        try await manager.save(PlanReminder(enabled: true, hour: 10, weekdays: [6]), for: "bundled:1")
        await reconcile(app: .logos)
        XCTAssertEqual(client.requests.count, 1)
        let request = try XCTUnwrap(client.requests.values.first)
        XCTAssertTrue(request.content.body.contains("Logos"))
        XCTAssertEqual((request.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 10)
        try await manager.save(PlanReminder(), for: "bundled:1")
        await reconcile()
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testPermissionIsOnlyRequestedOnExplicitEnabledSaveAndDeniedScheduleIsRetained() async throws {
        client.auth = .notDetermined
        await reconcile()
        XCTAssertEqual(client.permissionRequests, 0)
        try await manager.save(PlanReminder(), for: "bundled:1")
        XCTAssertEqual(client.permissionRequests, 0)
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        await reconcile()
        XCTAssertEqual(client.permissionRequests, 1)
        XCTAssertTrue(manager.blocked)
        XCTAssertTrue(manager.configuration(for: "bundled:1").enabled)
        XCTAssertTrue(client.requests.isEmpty)
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        XCTAssertEqual(client.permissionRequests, 1)
        client.auth = .allowed
        await reconcile()
        XCTAssertEqual(manager.scheduledPlanIDs, ["bundled:1"])
        client.auth = .blocked
        await reconcile()
        XCTAssertTrue(manager.blocked)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testSchedulingFailuresAndSilentDropsAreNotReportedAsScheduled() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        client.failure = true
        await reconcile()
        XCTAssertNotNil(manager.errors["bundled:1"])
        XCTAssertTrue(manager.scheduledPlanIDs.isEmpty)
        client.failure = false
        client.silentlyDrop = true
        await reconcile()
        XCTAssertNotNil(manager.errors["bundled:1"])
        XCTAssertTrue(manager.scheduledPlanIDs.isEmpty)
    }

    func testSilentlyDroppedUpdateCannotReportOldTimeAsScheduled() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        await reconcile()
        client.silentlyDrop = true
        try await manager.save(PlanReminder(enabled: true, hour: 11), for: "bundled:1")
        await reconcile()
        XCTAssertNotNil(manager.errors["bundled:1"])
        XCTAssertTrue(manager.scheduledPlanIDs.isEmpty)
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testConcurrentReconciliationsEndWithLatestSelectionAndApp() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        async let first: Void = manager.reconcile(plans: plans, selected: ["bundled:1"], deleted: [], app: .youVersion)
        await Task.yield()
        await manager.reconcile(plans: plans, selected: [], deleted: [], app: .logos)
        await first
        // Repeat the authoritative state after competing callers, as app activation does.
        await reconcile(selected: [])
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(manager.scheduledPlanIDs.isEmpty)
    }

    func testSaveDuringSchedulingDoesNotPublishOrVerifyAgainstChangedConfiguration() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        client.onAdd = { [self] in
            try? await manager.save(PlanReminder(enabled: true, hour: 11), for: "bundled:1")
        }
        await reconcile()
        XCTAssertEqual(manager.configuration(for: "bundled:1").hour, 11)
        XCTAssertEqual((client.requests.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 8)
        XCTAssertTrue(manager.scheduledPlanIDs.isEmpty, "The old pass must not claim the new configuration is scheduled")
        XCTAssertNil(manager.errors["bundled:1"], "Do not verify an old request against the new configuration")
        await reconcile()
        XCTAssertEqual((client.requests.values.first?.trigger as? UNCalendarNotificationTrigger)?.dateComponents.hour, 11)
        XCTAssertEqual(manager.scheduledPlanIDs, ["bundled:1"])
    }

    func testCapacityGuardPreservesUnrelatedRequests() async throws {
        for index in 0..<64 {
            let request = UNNotificationRequest(identifier: "other.\(index)", content: UNMutableNotificationContent(), trigger: nil)
            client.requests[request.identifier] = request
        }
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        await reconcile()
        XCTAssertEqual(client.requests.count, 64)
        XCTAssertEqual(client.additions, 0)
        XCTAssertNotNil(manager.errors["bundled:1"])
    }

    func testCapacityFailureKeepsExistingValidReminder() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "bundled:1")
        await reconcile()
        for index in 0..<63 {
            let request = UNNotificationRequest(identifier: "other.\(index)", content: UNMutableNotificationContent(), trigger: nil)
            client.requests[request.identifier] = request
        }
        try await manager.save(PlanReminder(enabled: true), for: "bundled:2")
        await reconcile()
        XCTAssertEqual(client.requests.count, 64)
        XCTAssertEqual(manager.scheduledPlanIDs, ["bundled:1"])
        XCTAssertNil(manager.errors["bundled:1"])
        XCTAssertNotNil(manager.errors["bundled:2"])
    }

    func testUnavailablePlansDoNotSchedule() async throws {
        try await manager.save(PlanReminder(enabled: true), for: "missing")
        await reconcile(selected: ["missing"])
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertTrue(manager.configuration(for: "missing").enabled)
    }

    func testMigrationAndURLs() async throws {
        XCTAssertEqual(BibleApp.migrate(in: preferences), .youVersion)
        preferences.removeObject(forKey: BibleApp.preferenceKey)
        preferences.set(false, forKey: AppPreferenceKey.youVersionEnabled)
        preferences.set(true, forKey: AppPreferenceKey.logosEnabled)
        XCTAssertEqual(BibleApp.migrate(in: preferences), .logos)
        preferences.set(true, forKey: AppPreferenceKey.youVersionEnabled)
        XCTAssertEqual(BibleApp.migrate(in: preferences), .logos, "Migration must not overwrite a chosen app")
        preferences.removeObject(forKey: BibleApp.preferenceKey)
        XCTAssertEqual(BibleApp.migrate(in: preferences), .youVersion, "Both enabled defaults to YouVersion")
        let day = Day(book: "JHN", startChapter: 3, endChapter: 5)
        XCTAssertEqual(BibleApp.youVersion.url(for: day)?.absoluteString, "youversion://bible?reference=JHN.3")
        XCTAssertEqual(BibleApp.logos.url(for: day)?.absoluteString, "logosres:esv?ref=Bible.John.3")
    }

    func testFailedOpeningIsReturnedAndAlternateCanSucceed() async {
        let opener = FakeURLOpener()
        let launcher = BibleReadingLauncher(openURL: opener.open)
        let day = Day(book: "JHN", startChapter: 3, endChapter: 3)
        let failure = await launcher.open(day, in: .youVersion)
        XCTAssertFalse(failure)
        opener.result = true
        let success = await launcher.open(day, in: .logos)
        XCTAssertTrue(success)
        XCTAssertEqual(opener.urls.count, 2)
    }

    func testRouteRoundTripInvalidURLsAndRepeatedTaps() async throws {
        let id = "imported:abc + / ? &"
        let url = try XCTUnwrap(ReadingRoute.url(planID: id))
        XCTAssertEqual(ReadingRoute.planID(from: url), id)
        XCTAssertNil(ReadingRoute.planID(from: URL(string: "https://reading?planID=abc")!))
        XCTAssertNil(ReadingRoute.planID(from: URL(string: "biblereadingplan://reading?planID=")!))
        let router = ReadingRouteHandler()
        router.open(url: url)
        XCTAssertEqual(router.pending?.planID, id)
        let token = router.pending?.token
        router.open(url: url)
        XCTAssertNotEqual(router.pending?.token, token)
    }

    func testConsumedRouteCannotReplayAndDoesNotClearANewerRequest() async throws {
        let router = ReadingRouteHandler()
        router.open(planID: "bundled:1")
        let first = try XCTUnwrap(router.pending)
        router.open(planID: "bundled:2")
        let second = try XCTUnwrap(router.pending)
        router.consume(first)
        XCTAssertEqual(router.pending?.token, second.token)
        router.consume(second)
        XCTAssertNil(router.pending)
        router.open(planID: "bundled:2")
        XCTAssertNotEqual(router.pending?.token, second.token)
    }

    func testActivationReconcilesOnceAndProgressChangesDoNotReconcile() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReadingPlanRepository(directory: root, bundled: ReadingPlan.previewPlans)
        _ = try repository.updateState { $0.selectedPlanIDs = ["bundled:1"] }
        let store = ReadingPlanStore(repository: repository, cloud: OfflineReadingPlanCloud(), preferences: preferences, notificationClient: client)
        await store.activate()
        XCTAssertEqual(client.authorizationReads, 1)
        await store.setDay(1, for: "bundled:1")
        await Task.yield()
        XCTAssertEqual(client.authorizationReads, 1)
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 1)
    }

    func testRoutingRefreshesLocalReadingWithoutCloudActivation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = ReadingPlanRepository(directory: root, bundled: ReadingPlan.previewPlans)
        _ = try repository.updateState {
            $0.selectedPlanIDs = ["bundled:1"]
            $0.progressByPlan = ["bundled:1": 0]
            $0.lastAdvancedReadingDay = "2000-01-01"
        }
        let store = ReadingPlanStore(repository: repository, cloud: OfflineReadingPlanCloud(), preferences: preferences, notificationClient: client)
        await store.prepareReadingRoute()
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 1)
        await store.prepareReadingRoute()
        XCTAssertEqual(store.reading(for: "bundled:1")?.dayIndex, 1)
        XCTAssertNil(store.reading(for: "missing"))
    }
}
