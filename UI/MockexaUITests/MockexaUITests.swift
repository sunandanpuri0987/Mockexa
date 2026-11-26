import XCTest

final class MockexaUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOCKEXA_UI_TESTING"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
    }

    func testAuthenticationEntryFlow() {
        openAuthentication()

        XCTAssertTrue(app.staticTexts["Welcome to Mockexa"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Email"].exists)
        XCTAssertTrue(app.staticTexts["Password"].exists)
        XCTAssertTrue(app.buttons["Log In"].exists)

        let modeToggle = app.buttons["auth.mode_toggle"]
        XCTAssertTrue(modeToggle.waitForExistence(timeout: 5))
        modeToggle.tap()

        XCTAssertTrue(app.staticTexts["Create Account"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Full Name"].exists)
        XCTAssertTrue(app.staticTexts["Age"].exists)
        XCTAssertTrue(app.buttons["Sign Up"].exists)
    }

    private func openAuthentication() {
        let getStarted = app.buttons["welcome.get_started"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: 20))
        getStarted.tap()
    }
}
