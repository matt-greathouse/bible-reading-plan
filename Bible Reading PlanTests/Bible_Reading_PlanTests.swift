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

    func testAdvanceDailyProgressUsesSharedMarkerToPreventSecondDeviceAdvance() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()
        guard let plan = plans.first else {
            XCTFail("No reading plans loaded")
            return
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 300000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let todayIdentifier = readingDayIdentifier(for: now, calendar: calendar)

        setState(
            ReadingPlanState(
                selectedPlanIds: [plan.id],
                progressByPlan: [plan.id: 5],
                lastAdvancedReadingDay: todayIdentifier
            ),
            in: defaults
        )
        defaults.set(yesterday, forKey: "lastCheckedDate")

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: defaults)

        XCTAssertEqual(readProgressMap(from: defaults)[plan.id], 5)
        XCTAssertEqual(ReadingPlanStateStore.load(from: defaults).lastAdvancedReadingDay, todayIdentifier)
    }

    func testLegacySameDayCheckpointSeedsSharedMarkerWithoutAdvancing() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()
        guard let plan = plans.first else {
            XCTFail("No reading plans loaded")
            return
        }

        let (defaults, suiteName) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 400000)
        let todayIdentifier = readingDayIdentifier(for: now, calendar: calendar)
        setState(ReadingPlanState(selectedPlanIds: [plan.id], progressByPlan: [plan.id: 4]), in: defaults)
        defaults.set(now, forKey: "lastCheckedDate")

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: defaults)

        XCTAssertEqual(readProgressMap(from: defaults)[plan.id], 4)
        XCTAssertEqual(ReadingPlanStateStore.load(from: defaults).lastAdvancedReadingDay, todayIdentifier)
    }

    func testTwoDevicesAdvancingFromSamePriorDayProduceSameProgress() throws {
        let plans = ReadingPlanService.shared.loadReadingPlans()
        guard let plan = plans.first else {
            XCTFail("No reading plans loaded")
            return
        }

        let (firstDefaults, firstSuiteName) = makeTestDefaults()
        let (secondDefaults, secondSuiteName) = makeTestDefaults()
        defer {
            firstDefaults.removePersistentDomain(forName: firstSuiteName)
            secondDefaults.removePersistentDomain(forName: secondSuiteName)
        }

        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSinceReferenceDate: 500000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let startingState = ReadingPlanState(selectedPlanIds: [plan.id], progressByPlan: [plan.id: 2])
        setState(startingState, in: firstDefaults)
        setState(startingState, in: secondDefaults)
        firstDefaults.set(yesterday, forKey: "lastCheckedDate")
        secondDefaults.set(yesterday, forKey: "lastCheckedDate")

        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: firstDefaults)
        ReadingPlanService.shared.advanceDailyProgressIfNeeded(now: now, calendar: calendar, defaults: secondDefaults)

        XCTAssertEqual(readProgressMap(from: firstDefaults)[plan.id], 3)
        XCTAssertEqual(readProgressMap(from: secondDefaults)[plan.id], 3)
        XCTAssertEqual(
            ReadingPlanStateStore.load(from: firstDefaults).lastAdvancedReadingDay,
            ReadingPlanStateStore.load(from: secondDefaults).lastAdvancedReadingDay
        )
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
        ReadingPlanStateStore.save(state, to: defaults, skipCloud: true)
    }

    private func readProgressMap(from defaults: UserDefaults) -> [Int: Int] {
        ReadingPlanStateStore.load(from: defaults).progressByPlan
    }

    private func readingDayIdentifier(for date: Date, calendar: Calendar) -> String {
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone
        let components = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
