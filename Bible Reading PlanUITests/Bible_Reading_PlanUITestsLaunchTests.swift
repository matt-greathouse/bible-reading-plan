import XCTest

final class Bible_Reading_PlanUITestsLaunchTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testLaunchAndManagePlansScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-state"]
        app.launchEnvironment["UITEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["Select Reading Plans"].waitForExistence(timeout: 10))
        let empty = XCTAttachment(screenshot: app.screenshot())
        empty.name = "Empty reading plan screen"
        empty.lifetime = .keepAlways
        add(empty)
        app.buttons["manage-plans"].tap()
        XCTAssertTrue(app.switches["select-bundled:1"].waitForExistence(timeout: 5))
        let manage = XCTAttachment(screenshot: app.screenshot())
        manage.name = "Manage Plans"
        manage.lifetime = .keepAlways
        add(manage)
    }
    @MainActor
    func testWidgetReadingPreviews() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--reset-test-state", "--widget-previews"]
        app.launchEnvironment["UITEST_SESSION"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.staticTexts["Widget Previews"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["John 2"].exists)
        XCTAssertTrue(app.staticTexts["Psalms 3–4"].exists)
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Small, medium, and empty widget previews"
        preview.lifetime = .keepAlways
        add(preview)
    }

}
