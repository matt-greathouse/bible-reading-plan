//
//  Bible_Reading_PlanTests.swift
//  Bible Reading PlanTests
//
//  Created by Matt Greathouse on 2/17/25.
//

import XCTest
@testable import Bible_Reading_Plan

final class Bible_Reading_PlanTests: XCTestCase {

    func testReadingPlanLoading() throws {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "ReadingPlans", withExtension: "json") else {
            XCTFail("Missing file: ReadingPlans.json")
            return
        }

        let data = try Data(contentsOf: url)
        let plans = try JSONDecoder().decode([ReadingPlan].self, from: data)

        XCTAssertEqual(plans.count, 2)
        XCTAssertEqual(plans.first?.name, "Plan 1")
    }

    func testDaySelectionPersistence() throws {
        let userDefaults = UserDefaults.standard
        userDefaults.set(2, forKey: "currentDay")

        let currentDay = userDefaults.integer(forKey: "currentDay")
        XCTAssertEqual(currentDay, 2)
    func testPersistenceOfSelectedPlanAndCurrentDay() throws {
        let userDefaults = UserDefaults.standard
        userDefaults.set("Plan 1", forKey: "selectedPlanName")
        userDefaults.set(1, forKey: "currentDay")

        let selectedPlanName = userDefaults.string(forKey: "selectedPlanName")
        let currentDay = userDefaults.integer(forKey: "currentDay")

        XCTAssertEqual(selectedPlanName, "Plan 1")
        XCTAssertEqual(currentDay, 1)
    }

    func testDailyIncrementLogic() throws {
        let userDefaults = UserDefaults.standard
        userDefaults.set("Plan 1", forKey: "selectedPlanName")
        userDefaults.set(1, forKey: "currentDay")

        let app = Bible_Reading_PlanApp()
        app.incrementDayIfNeeded()

        let currentDay = userDefaults.integer(forKey: "currentDay")
        XCTAssertEqual(currentDay, 2)
    }
}
