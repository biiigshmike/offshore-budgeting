import XCTest

#if OFFSHORE_SCREENSHOTS
/// Run only with OffshoreBudgeting-Screenshots. The app must not need launch arguments
/// to select screenshot mode, and tests must never erase or provision a simulator.
@MainActor
final class ScreenshotModeLaunchUITests: XCTestCase {
    private var fixtureValidation: String?

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Reset only the dedicated screenshot app's disposable store. Individual
        // repeated-launch checks below deliberately run without reset arguments.
        let app = makeApp(arguments: ["-resetSeed"])
        app.launch()
        openDiagnostics(app)
        fixtureValidation = assertScreenshotSession(app)
        app.terminate()
    }

    func testTwentyConsecutiveLaunchesWithoutModeArgumentsKeepValidatedScreenshotStore() {
        let app = makeApp()
        var firstWorkspaceValidation: String?
        for cycle in 1...20 {
            XCTContext.runActivity(named: "Screenshot launch \(cycle) of 20, without launch arguments") { _ in
                app.launch()
                XCTAssertTrue(app.launchArguments.isEmpty)
                openDiagnostics(app)
                let validation = assertScreenshotSession(app)
                if let firstWorkspaceValidation {
                    XCTAssertEqual(validation, firstWorkspaceValidation, "Launch \(cycle) changed the seeded workspace without a reset request")
                } else {
                    firstWorkspaceValidation = validation
                }
                app.terminate()
            }
        }
    }

    func testExplicitResetRebuildsOnlyScreenshotWorkspace() {
        let app = makeApp()
        app.launch()
        openDiagnostics(app)
        let originalValidation = assertScreenshotSession(app)
        app.terminate()
        app.launchArguments = ["-resetSeed"]
        app.launch()
        openDiagnostics(app)
        let resetValidation = assertScreenshotSession(app)
        XCTAssertNotEqual(resetValidation, originalValidation)
        app.terminate()
        app.launchArguments = []
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(assertScreenshotSession(app), resetValidation)
    }

    func testBackgroundActivationAndRelaunchKeepScreenshotSession() {
        let app = makeApp()
        app.launch()
        openDiagnostics(app)
        let originalValidation = assertScreenshotSession(app)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(assertScreenshotSession(app), originalValidation)
        app.terminate()
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(assertScreenshotSession(app), originalValidation)
    }

    func testOpenFailureShowsErrorAndNeverNormalData() {
        assertFaultIsContained(stage: "Open")
    }

    func testSaveFailureShowsErrorAndNeverNormalData() {
        assertFaultIsContained(stage: "Save")
    }

    func testValidationFailureShowsErrorAndNeverNormalData() {
        assertFaultIsContained(stage: "Validation")
    }

    func testRepeatOnboardingKeepsScreenshotStoreAndSampleWorkspace() {
        let app = makeApp()
        app.launch()
        openDiagnostics(app)
        let originalValidation = assertScreenshotSession(app)
        app.navigationBars["Startup Diagnostics"].buttons["About"].tap()
        app.navigationBars["About"].buttons["Settings"].tap()
        let general = element("settings_general", in: app)
        reveal(general, in: app)
        general.tap()
        let maintenance = app.buttons["Maintenance"].firstMatch
        reveal(maintenance, in: app)
        maintenance.tap()
        let repeatOnboarding = app.buttons["Repeat Onboarding"].firstMatch
        reveal(repeatOnboarding, in: app)
        repeatOnboarding.tap()
        let confirm = app.alerts["Repeat Onboarding?"].buttons["Go"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        let getStarted = app.buttons["Get Started"].firstMatch
        XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
        getStarted.tap()
        let next = app.buttons["Next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["iCloud"].exists)
        XCTAssertFalse(app.buttons["Use iCloud"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Personal")).firstMatch.exists)
        for _ in 0..<4 {
            XCTAssertTrue(next.waitForExistence(timeout: 5))
            next.tap()
        }
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        openDiagnostics(app)
        XCTAssertEqual(assertScreenshotSession(app), originalValidation)
    }

    private func makeApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        // The screenshot scheme also hosts unit tests; UI app launches must not
        // inherit the unit host's in-memory/Color.clear opt-in.
        app.launchEnvironment["OFFSHORE_UNIT_TEST_HOST"] = "0"
        return app
    }

    private func assertFaultIsContained(stage: String) {
        var arguments = ["-uiTesting", "-screenshotTestFail\(stage)"]
        if stage == "Save" { arguments.append("-resetSeed") }
        let app = makeApp(arguments: arguments)
        app.launch()
        let error = element("screenshotSetupError", in: app)
        XCTAssertTrue(error.waitForExistence(timeout: 15))
        XCTAssertTrue(readableText(error).contains(stage))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertFalse(app.buttons["home.reviewToday"].exists)
        let retry = app.buttons["screenshotSetupRetry"]
        XCTAssertTrue(retry.exists)
        retry.tap()
        XCTAssertTrue(error.waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        app.terminate()
        app.launchArguments = []
        app.launch()
        openDiagnostics(app)
        XCTAssertEqual(assertScreenshotSession(app), fixtureValidation, "A failed setup must preserve the existing saved screenshot workspace")
    }

    @discardableResult
    private func assertScreenshotSession(_ app: XCUIApplication) -> String {
        XCTAssertFalse(element("screenshotSetupError", in: app).exists)
        let mode = element("screenshotDiagnosticsMode", in: app)
        reveal(mode, in: app, direction: .down)
        XCTAssertTrue(readableText(mode).contains("Screenshots (compiled)"))
        let store = element("screenshotDiagnosticsStore", in: app)
        reveal(store, in: app)
        let storeText = readableText(store)
        XCTAssertTrue(storeText.contains("Screenshots.store"), storeText)
        XCTAssertFalse(storeText.contains("Local.store"), storeText)
        XCTAssertFalse(storeText.contains("Cloud.store"), storeText)
        let validation = element("screenshotDiagnosticsValidation", in: app)
        reveal(validation, in: app)
        let validationText = readableText(validation)
        XCTAssertTrue(validationText.contains("Valid ("), validationText)
        let shareLog = element("shareStartupDiagnostics", in: app)
        reveal(shareLog, in: app)
        XCTAssertTrue(shareLog.exists)
        return validationText
    }

    private func openDiagnostics(_ app: XCUIApplication) {
        dismissKnownPrompts(app)
        if app.navigationBars["Startup Diagnostics"].waitForExistence(timeout: 1) { return }
        if !app.navigationBars["Settings"].waitForExistence(timeout: 1) {
            let tab = app.tabBars.buttons["Settings"]
            if tab.waitForExistence(timeout: 3) {
                tab.tap()
            } else {
                let settings = app.buttons["Settings"].firstMatch
                if settings.waitForExistence(timeout: 3), settings.isHittable {
                    settings.tap()
                } else {
                    let sidebar = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "sidebar")).firstMatch
                    if sidebar.exists { sidebar.tap() }
                    let sidebarSettings = app.staticTexts["Settings"].firstMatch
                    XCTAssertTrue(sidebarSettings.waitForExistence(timeout: 5))
                    sidebarSettings.tap()
                }
            }
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        dismissKnownPrompts(app)
        let about = element("settings_about", in: app)
        reveal(about, in: app)
        about.tap()
        let diagnostics = element("startupDiagnosticsLink", in: app)
        reveal(diagnostics, in: app)
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["Startup Diagnostics"].waitForExistence(timeout: 5))
    }

    private func dismissKnownPrompts(_ app: XCUIApplication) {
        for _ in 0..<4 {
            let releaseTitle = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "What’s New in ")
            ).firstMatch
            let helpGuide = app.buttons["Open Help Guide"].firstMatch
            let proceed = app.buttons["Continue"].firstMatch
            let isReleasePrompt = releaseTitle.waitForExistence(timeout: 1)
            guard isReleasePrompt || (helpGuide.exists && proceed.exists) else { return }
            guard proceed.waitForExistence(timeout: 3), proceed.isHittable else { return }
            proceed.tap()
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func readableText(_ element: XCUIElement) -> String {
        element.label + " " + (element.value as? String ?? "")
    }

    private enum ScrollDirection { case up, down }

    private func reveal(_ target: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up) {
        for _ in 0..<6 {
            if target.exists, target.isHittable { return }
            if direction == .up { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5) && target.isHittable)
    }
}
#endif
