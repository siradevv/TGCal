import XCTest

final class TGCalUITests: XCTestCase {
    func testLaunchAndTabBarVisible() {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launched and the tab bar is visible
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5),
                      "Tab bar should be visible after launch")
    }
}
