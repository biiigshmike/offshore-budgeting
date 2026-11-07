import CoreLocation
import XCTest

/// Real location callbacks and local notifications; only merchant discovery is a fixture.
@MainActor
final class ExcursionFiveStopUITests: XCTestCase {
    private var application: XCUIApplication?
    private let longitude = -118.3528396
    private var locationSample = 0

    private struct Diagnostics: Decodable {
        let events: [String]
        let scheduledIDs: [String]
        let deliveredIDs: [String]
        let candidateIDs: [String]
        let sessionIDs: [String]
        let workspaceIDs: [String]
        let fixtureEnabled: Bool
        let fixCount: Int
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        executionTimeAllowance = 1_800
    }

    override func tearDownWithError() throws {
        if let app = application {
            attachEvidence(app, name: "Final route evidence")
            let cancel = app.buttons["Cancel"]
            if cancel.exists && cancel.isHittable { cancel.tap() }
            if app.tabBars.buttons["Settings"].exists { returnToExcursion(app) }
            let stop = app.buttons["Stop Excursion Mode"]
            if stop.exists && stop.isHittable { stop.tap() }
            app.terminate()
        }
        XCUIDevice.shared.location = nil
    }

    func testDiagnosticsSurviveLocationPermissionSetup() throws {
        let (app, _) = try startExcursionWithLocationConsent()
        app.tabBars.buttons["Home"].tap()
        returnToExcursion(app)
        let snapshot = try diagnostics(app)
        XCTAssertTrue(snapshot.scheduledIDs.isEmpty)
        XCTAssertTrue(snapshot.deliveredIDs.isEmpty)
    }

    func testFiveStopsClusterAndReturnProduceSixVisibleNotifications() async throws {
        let (app, springboard) = try startExcursionWithLocationConsent()

        var lastDelivery: Date?
        var firstDelivery: Date?
        for (ordinal, stop) in [0, 1, 2, 3, 4, 0].enumerated() {
            if let lastDelivery {
                // The midpoint is outside both 100 m stop radii. Keep fresh departure
                // evidence flowing while the production global cooldown elapses.
                let departureLatitude = 33.8550064 + Double(stop) * 0.005 - 0.0025
                try await observeWithoutDelivery(app, latitude: departureLatitude,
                    until: max(Date().addingTimeInterval(30), lastDelivery.addingTimeInterval(130)),
                    expectedCount: ordinal)
            }
            if ordinal == 5, let firstDelivery {
                XCTAssertGreaterThan(Date().timeIntervalSince(firstDelivery), 480,
                    "Return to A must exercise the real eight-minute merchant cooldown")
            }
            let latitude = 33.8550064 + Double(stop) * 0.005
            let arrival = Date()
            let before = try diagnostics(app)
            setLocation(latitude: latitude)
            try await observeWithoutDelivery(app, latitude: latitude,
                until: arrival.addingTimeInterval(35), expectedCount: ordinal)
            XCTAssertGreaterThan(try diagnostics(app).fixCount, before.fixCount,
                "Location delivery: simulator fixes did not reach the service")

            let body = stop == 2
                ? "Near a few places? Record an expense if you made a purchase."
                : "Near Route \(["A", "B", "C", "D", "E"][stop])? Record an expense if you made a purchase."
            // SpringBoard may expose a notification as one combined accessibility
            // element containing app/time/body rather than a separate static text.
            let banner = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", body)).firstMatch
            var nextFix = Date.distantPast
            let deadline = arrival.addingTimeInterval(100)
            while !banner.exists && Date() < deadline {
                if Date() >= nextFix {
                    setLocation(latitude: latitude)
                    nextFix = Date().addingTimeInterval(10)
                }
                try await Task.sleep(for: .seconds(1))
            }
            XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(arrival), 45,
                "Detection: a visible reminder must not precede the full default dwell")
            let snapshot = try diagnostics(app)
            attachEvidence(app, name: "Stop \(ordinal + 1) banner")
            XCTAssertEqual(snapshot.scheduledIDs.count, ordinal + 1,
                "Detection/scheduling: expected one new request; inspect trace")
            XCTAssertEqual(snapshot.deliveredIDs.count, ordinal + 1,
                "Delivery: expected one foreground notification callback")
            XCTAssertTrue(banner.exists && banner.isHittable,
                "Presentation: scheduled/delivered diagnostics alone do not prove a visible banner")
            if stop == 2 {
                XCTAssertEqual(Set(snapshot.candidateIDs), Set(["route-C1", "route-C2", "route-C3"]),
                    "Detection: all three cluster merchants must be in the actual suggestion")
            } else {
                XCTAssertEqual(snapshot.candidateIDs, ["route-\(["A", "B", "C", "D", "E"][stop])"],
                    "Detection: each isolated stop must suggest only its fixture merchant")
            }
            lastDelivery = Date()
            if firstDelivery == nil { firstDelivery = lastDelivery }
            banner.tap()
            if stop == 2 {
                XCTAssertTrue(app.navigationBars["Nearby Places"].waitForExistence(timeout: 8),
                    "Navigation: cluster reminder should open merchant chooser")
                for name in ["Route C1", "Route C2", "Route C3", "Other"] {
                    XCTAssertTrue(app.buttons[name].exists)
                }
                app.buttons["Route C2"].tap()
            }
            XCTAssertTrue(app.navigationBars["Add Expense"].waitForExistence(timeout: 8))
            let description = app.textFields["Description"]
            XCTAssertEqual(description.value as? String,
                stop == 2 ? "Route C2" : "Route \(["A", "B", "C", "D", "E"][stop])")
            if stop == 2 {
                description.tap()
                description.typeText(" corrected")
                XCTAssertEqual(description.value as? String, "Route C2 corrected")
            }
            app.buttons["Cancel"].tap()
            XCTAssertTrue(app.navigationBars["Add Expense"].waitForNonExistence(timeout: 5))
            // Notification routing may select another tab. Return to the status
            // surface without restarting the session or replacing its workspace.
            returnToExcursion(app)
            if stop == 2 {
                let clusterFixCount = try diagnostics(app).fixCount
                // Move ~60m within the overlapping saved regions for longer than
                // the global cooldown. Small location changes must not repeat C.
                try await observeWithoutDelivery(app, latitude: latitude,
                    until: Date().addingTimeInterval(135), expectedCount: ordinal + 1,
                    shiftWithinCluster: true)
                XCTAssertGreaterThanOrEqual(try diagnostics(app).fixCount - clusterFixCount, 8,
                    "Location delivery: cluster suppression needs fresh movement evidence")
                attachEvidence(app, name: "Cluster duplicate suppression")
            }
        }
        let final = try diagnostics(app)
        XCTAssertEqual(Set(final.sessionIDs).count, 1, "All suggestions must retain one session")
        XCTAssertEqual(Set(final.workspaceIDs).count, 1, "All suggestions must retain one workspace")
        XCTAssertEqual(final.deliveredIDs.count, 6)
        XCTAssertEqual(Set(final.deliveredIDs).count, 6)
        XCTAssertEqual(Set(final.scheduledIDs), Set(final.deliveredIDs))
        try await observeWithoutDelivery(app, latitude: 33.8550064,
            until: Date().addingTimeInterval(30), expectedCount: 6)
    }

    private func startExcursionWithLocationConsent() throws -> (XCUIApplication, XCUIApplication) {
        // Start outside every fixture radius so permission setup cannot establish dwell.
        setLocation(latitude: 33.8525)
        let (app, springboard) = openExcursionWithNotificationConsent()
        application = app
        XCTAssertTrue(try diagnostics(app).fixtureEnabled)
        let existingSession = app.buttons["Stop Excursion Mode"]
        if existingSession.exists {
            reveal(existingSession, app: app)
            existingSession.tap()
        }
        XCTAssertTrue(app.buttons["Start Excursion Mode"].waitForExistence(timeout: 5))
        app.buttons["Start Excursion Mode"].tap()
        app.alerts["Get nearby reminders while you’re out"].buttons["Continue"].tap()
        let whileUsing = springboard.alerts.buttons["Allow While Using App"]
        XCTAssertTrue(whileUsing.waitForExistence(timeout: 8), "Location permission prompt missing")
        whileUsing.tap()
        let keepWhileUsing = springboard.alerts.buttons["Keep Only While Using"]
        XCTAssertTrue(keepWhileUsing.waitForExistence(timeout: 8), "Always upgrade prompt missing")
        keepWhileUsing.tap()
        XCTAssertTrue(app.buttons["Stop Excursion Mode"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["excursionLocationStatus"].label, "Works while Offshore is open.")
        XCTAssertEqual(try diagnostics(app).deliveredIDs.count, 0)

        return (app, springboard)
    }

    private func observeWithoutDelivery(_ app: XCUIApplication, latitude: Double, until end: Date,
                                       expectedCount: Int, shiftWithinCluster: Bool = false) async throws {
        var nextFix = Date.distantPast
        var sample = 0
        while Date() < end {
            if Date() >= nextFix {
                setLocation(latitude: latitude,
                    longitudeOffset: shiftWithinCluster ? Double(sample % 3 - 1) * 0.00065 : 0)
                sample += 1
                nextFix = Date().addingTimeInterval(10)
            }
            let current = try diagnostics(app)
            XCTAssertEqual(current.scheduledIDs.count, expectedCount,
                "Detection/scheduling: premature or duplicate reminder")
            XCTAssertEqual(current.deliveredIDs.count, expectedCount,
                "Delivery: unexpected notification during suppression window")
            try await Task.sleep(for: .seconds(1))
        }
    }

    private func setLocation(latitude: Double, longitudeOffset: Double = 0) {
        // Reassigning exactly the same coordinate may not emit a new Core Location
        // callback in Simulator. Sub-meter jitter stays within the same stop while
        // requiring the real location manager to provide fresh dwell evidence.
        locationSample += 1
        let jitter = locationSample.isMultiple(of: 2) ? 0.000005 : -0.000005
        XCUIDevice.shared.location = XCUILocation(location: CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude + longitudeOffset + jitter),
            altitude: 0, horizontalAccuracy: 10, verticalAccuracy: 10,
            course: 0, speed: 0, timestamp: Date()))
    }

    private enum DiagnosticsError: Error { case missingStatus, invalidSnapshot }

    private func diagnostics(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws -> Diagnostics {
        let element = app.staticTexts["excursionStatus"]
        guard element.waitForExistence(timeout: 5) else {
            attachEvidence(app, name: "Missing Excursion status diagnostics")
            XCTFail("Excursion status unavailable while reading diagnostics; inspect the attached screen hierarchy", file: file, line: line)
            throw DiagnosticsError.missingStatus
        }
        guard let json = element.value as? String,
              let snapshot = try? JSONDecoder().decode(Diagnostics.self, from: Data(json.utf8)) else {
            attachEvidence(app, name: "Invalid Excursion status diagnostics")
            XCTFail("Excursion status is present but DEBUG test diagnostics are unavailable", file: file, line: line)
            throw DiagnosticsError.invalidSnapshot
        }
        XCTAssertTrue(snapshot.fixtureEnabled, "Five-stop merchant fixture is not enabled; check the app launch flags", file: file, line: line)
        return snapshot
    }

    private func attachEvidence(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let element = app.staticTexts["excursionStatus"]
        let trace = XCTAttachment(string: element.exists ? (element.value as? String ?? element.label) : app.debugDescription)
        trace.name = name + " diagnostics"
        trace.lifetime = .keepAlways
        add(trace)
    }

    private func openExcursionWithNotificationConsent() -> (XCUIApplication, XCUIApplication) {
        let app = XCUIApplication()
        application = app
        app.launchArguments = [
            "-uiTesting", "-uiTestingReset", "-uiTestScenarioWorkspaceProgress", "-uiTestExcursionFiveStops",
            "-tips_seenKeys", "tip.home.v1,tip.budgets.v1,tip.cards.v1,tip.income.v1,tip.budgetdetail.v1",
            "-tips_resetToken", "0", "-tips_seen_lastResetToken", "0",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.resetAuthorizationStatus(for: .location)
        app.launch()
        let springboard = ExcursionUITestNavigation.allowNotificationsAndOpenExcursion(app)
        return (app, springboard)
    }

    private func returnToExcursion(_ app: XCUIApplication) {
        ExcursionUITestNavigation.openExcursion(app)
        XCTAssertTrue(app.staticTexts["excursionStatus"].waitForExistence(timeout: 5))
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        ExcursionUITestNavigation.reveal(element, in: app)
    }
}
