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
    func testBibleAppPreferencesRemainDeviceLocal() throws {
        let app = launch()
        app.buttons["manage-plans"].tap()
        let youVersion = app.switches["YouVersion"]
        XCTAssertTrue(youVersion.waitForExistence(timeout: 5))
        XCTAssertEqual(youVersion.value as? String, "1")
        youVersion.switches.firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["manage-plans"].tap()
        XCTAssertEqual(app.switches["YouVersion"].value as? String, "0")
    }
}
