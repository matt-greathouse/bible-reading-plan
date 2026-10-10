import XCTest

final class Bible_Reading_PlanUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-state"]
        app.launchEnvironment["UITEST_SESSION"] = UUID().uuidString
        app.launch()
        return app
    }

    @MainActor
    func testSelectionDayImportAndDeletion() throws {
        let app = launch()
        let manage = app.buttons["manage-plans"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        manage.tap()
        let select = app.switches["select-bundled:1"]
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        select.switches.firstMatch.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 5))
        wheel.adjust(toPickerWheelValue: "Day 3: John 3")
        let selectedDay = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Day 3: John 3"), object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedDay], timeout: 5), .completed)

        let fixture = app.buttons["import-test-fixture"]
        for _ in 0..<5 where !fixture.isHittable { app.swipeUp() }
        XCTAssertTrue(fixture.isHittable)
        fixture.tap()
        let imported = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH %@", "select-imported:")).firstMatch
        for _ in 0..<5 where !imported.isHittable { app.swipeDown() }
        XCTAssertTrue(imported.waitForExistence(timeout: 5))
        imported.switches.firstMatch.tap()
        imported.swipeLeft()
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirmation = app.alerts["Delete Imported Plan?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Delete"].tap()
        XCTAssertTrue(imported.waitForNonExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["John 3"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Today’s Readings after manual day change"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testPreferredBibleAppPersistsAndChangesReadingAction() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        app.switches["select-bundled:1"].switches.firstMatch.tap()
        let picker = app.buttons["preferred-bible-app"]
        for _ in 0..<5 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons["Logos"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Read in Logos"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-test-state" }
        app.launch()
        XCTAssertTrue(app.buttons["Read in Logos"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testReadingActionKeepsPassageVisibleWhenBibleAppCannotOpen() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        app.switches["select-bundled:1"].switches.firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let read = app.buttons["Read in YouVersion"]
        XCTAssertTrue(read.waitForExistence(timeout: 5))
        read.tap()
        XCTAssertTrue(app.staticTexts["Couldn’t open YouVersion. Try another Bible app or copy the passage."].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["John 1"].exists)
        XCTAssertTrue(app.buttons["Open in Logos"].exists)
        XCTAssertTrue(app.buttons["Copy Passage"].exists)
        app.buttons["Copy Passage"].tap()
    }

    @MainActor
    func testReminderSaveCancelAndWeekdayValidation() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        app.switches["select-bundled:1"].switches.firstMatch.tap()
        let reminder = app.buttons["reminder-bundled:1"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        reminder.tap()
        let toggle = app.switches["reminder-enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        app.buttons["Cancel"].tap()
        reminder.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        for day in 1...7 {
            let weekday = app.switches["reminder-weekday-\(day)"]
            for _ in 0..<3 where !weekday.isHittable { app.swipeUp() }
            weekday.switches.firstMatch.tap()
        }
        XCTAssertFalse(app.buttons["save-reminder"].isEnabled)
        app.switches["reminder-weekday-7"].switches.firstMatch.tap()
        app.buttons["save-reminder"].tap()
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Reading Reminder"].waitForNonExistence(timeout: 5))
        reminder.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertEqual(app.switches["reminder-weekday-7"].value as? String, "1")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    func testWarmRouteDismissesManagePlansAndFocusesSelectedReading() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        app.switches["select-bundled:1"].switches.firstMatch.tap()
        let second = app.switches["select-bundled:2"]
        for _ in 0..<4 where !second.isHittable { app.swipeUp() }
        second.switches.firstMatch.tap()
        let route = app.buttons["open-test-reading-route"]
        for _ in 0..<8 where !route.isHittable { app.swipeUp() }
        route.tap()
        XCTAssertTrue(app.buttons["manage-plans"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Psalms and Proverbs"].isHittable)
        XCTAssertTrue(app.buttons["Read in YouVersion"].firstMatch.exists)
    }

    @MainActor
    func testColdRouteReturnsToReadingAndMissingRouteExplainsFailure() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        app.switches["select-bundled:1"].switches.firstMatch.tap()
        let second = app.switches["select-bundled:2"]
        for _ in 0..<4 where !second.isHittable { app.swipeUp() }
        second.switches.firstMatch.tap()
        app.terminate()
        app.launchArguments.removeAll { $0 == "--reset-test-state" }
        app.launchEnvironment["UITEST_READING_ROUTE"] = "bundled:2"
        app.launch()
        XCTAssertTrue(app.staticTexts["Psalms and Proverbs"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Psalms and Proverbs"].isHittable)
        XCTAssertTrue(app.buttons["Read in YouVersion"].firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
        app.terminate()
        app.launchEnvironment["UITEST_READING_ROUTE"] = "missing"
        app.launch()
        XCTAssertTrue(app.alerts["Reading Plan Error"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.alerts.staticTexts["This plan is no longer selected or is unavailable. Open Manage Plans to check it."].exists)
    }
}
