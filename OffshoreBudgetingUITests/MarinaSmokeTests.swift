import XCTest

final class MarinaSmokeTests: XCTestCase {
    @MainActor
    func testHomeOpensMarinaAndConversationHistory() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Marina requires iOS 26") }
        let app = XCUIApplication()
        // Existing screenshot mode uses an isolated local store and synthetic records.
        app.launchArguments = [
            "-screenshotMode", "-resetSeed", "-didCompleteOnboarding", "YES",
            "-icloud_useCloud", "NO", "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1",
            "-releaseLogs_seenReleaseIDs", "2.4.1-22,2.4-21",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let home = app.tabBars.buttons["Home"].firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        home.tap()
        let marina = app.buttons["home.marina"]
        XCTAssertTrue(marina.waitForExistence(timeout: 10))
        marina.tap()
        let composer = app.textFields["marina.composer"].firstMatch
        let multilineComposer = app.textViews["marina.composer"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5) || multilineComposer.waitForExistence(timeout: 5))
        let history = app.buttons["marina.history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Marina conversation"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        history.tap()
        XCTAssertTrue(app.staticTexts["No conversations yet"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["marina.newConversation"].tap()
        XCTAssertTrue(app.staticTexts["Understand your budget"].exists)
    }
}
