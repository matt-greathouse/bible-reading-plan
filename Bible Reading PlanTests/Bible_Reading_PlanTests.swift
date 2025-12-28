//
//  Bible_Reading_PlanTests.swift
//  Bible Reading PlanTests
//
//  Created by Matt Greathouse on 2/17/25.
//

import Foundation
import XCTest
@testable import Bible_Reading_Plan

final class Bible_Reading_PlanTests: XCTestCase {

    func testReadingPlanServiceLoadsPlans() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()

        XCTAssertFalse(plans.isEmpty)
        XCTAssertTrue(plans.allSatisfy { !$0.name.isEmpty && !$0.days.isEmpty })
        XCTAssertEqual(Set(plans.map { $0.id }).count, plans.count)
    }

    func testAdvanceDailyProgressIncrementsOncePerDay() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()
        guard let plan = plans.first else {
            XCTFail("No reading plans loaded")
            return
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        setState(ReadingPlanState(selectedPlanIds: [plan.id], progressByPlan: [plan.id: 0]), in: defaults)

        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 100000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        defaults.set(yesterday, forKey: "lastCheckedDate")

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(readProgressMap(from: defaults)[plan.id], 1)

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(readProgressMap(from: defaults)[plan.id], 1)
    }

    func testAdvanceDailyProgressCapsAtLastDay() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()
        guard let plan = plans.first else {
            XCTFail("No reading plans loaded")
            return
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let lastIndex = max(plan.days.count - 1, 0)
        setState(ReadingPlanState(selectedPlanIds: [plan.id], progressByPlan: [plan.id: lastIndex]), in: defaults)

        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 200000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        defaults.set(yesterday, forKey: "lastCheckedDate")

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: defaults)
        XCTAssertEqual(readProgressMap(from: defaults)[plan.id], lastIndex)
    }

    func testLegacyMigrationMovesAndClears() {
        let result = ReadingPlanMigration.migrateLegacyIfNeeded(
            selectedPlanIds: [],
            progressMap: [:],
            legacyPlanId: 42,
            legacyDay: 3
        )

        XCTAssertEqual(result.selectedPlanIds, [42])
        XCTAssertEqual(result.progressMap[42], 3)
        XCTAssertEqual(result.legacyPlanId, 0)
        XCTAssertEqual(result.legacyDay, 0)
        XCTAssertTrue(result.didMigrate)
    }

    func testLegacyMigrationDoesNotOverrideExistingSelection() {
        let result = ReadingPlanMigration.migrateLegacyIfNeeded(
            selectedPlanIds: [1],
            progressMap: [1: 5],
            legacyPlanId: 99,
            legacyDay: 2
        )

        XCTAssertEqual(result.selectedPlanIds, [1])
        XCTAssertEqual(result.progressMap[1], 5)
        XCTAssertEqual(result.legacyPlanId, 0)
        XCTAssertEqual(result.legacyDay, 0)
        XCTAssertFalse(result.didMigrate)
    }

    private func makeTestDefaults() -> (UserDefaults, String) {
        let suiteName = "BibleReadingPlanTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func setState(_ state: ReadingPlanState, in defaults: UserDefaults) {
        ReadingPlanStateStore.save(state, to: defaults)
    }

    private func readProgressMap(from defaults: UserDefaults) -> [Int: Int] {
        ReadingPlanStateStore.load(from: defaults).progressByPlan
    }
}
