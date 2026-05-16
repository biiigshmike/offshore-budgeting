import XCTest

@MainActor
struct MarinaUITestDriver {
    let app: XCUIApplication
    let testCase: XCTestCase
    let traceOutputURL: URL

    init(app: XCUIApplication, testCase: XCTestCase) {
        self.app = app
        self.testCase = testCase
        self.traceOutputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("marina-ui-trace-\(UUID().uuidString).jsonl")
    }

    func launchHarness() {
        try? FileManager.default.removeItem(at: traceOutputURL)
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingReset",
            "-uiTestingMarinaHarness",
            MarinaRuntimeLaunchArgument.sharedPipelineEnabled,
            MarinaRuntimeLaunchArgument.nlqDisabled,
            MarinaRuntimeLaunchArgument.aiOptInDisabled
        ]
        app.launchEnvironment = [
            "MARINA_UI_TRACE_OUTPUT_PATH": traceOutputURL.path,
            "MARINA_UI_FIXED_NOW_ISO8601": "2026-05-15T12:00:00Z"
        ]
        app.launch()

        if promptField().waitForExistence(timeout: 8) == false {
            let openButton = app.buttons["home.assistant.openButton"].firstMatch
            if openButton.waitForExistence(timeout: 5) {
                openButton.tap()
            } else if app.buttons["Open Assistant"].firstMatch.exists {
                app.buttons["Open Assistant"].firstMatch.tap()
            }
        }
        XCTAssertTrue(promptField().waitForExistence(timeout: 8), "Marina prompt field did not appear in harness mode.")
    }

    func submit(_ prompt: String) {
        let field = promptField()
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Marina prompt field was not visible.")
        field.tap()
        field.typeText(prompt)

        let submit = app.buttons["marina.submitButton"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 5), "Marina submit button was not visible.")
        submit.tap()
    }

    func runPrompt(
        _ prompt: String,
        expectation: MarinaPromptExpectation? = nil,
        timeout: TimeInterval = 15
    ) -> MarinaSurfaceReport {
        let previousTraceCount = readTraceLines().count
        submit(prompt)

        let trace = waitForTrace(prompt: prompt, previousTraceCount: previousTraceCount, timeout: timeout)
        let appeared = trace != nil || waitUntil(timeout: min(timeout, 2)) {
            answerElements().isEmpty == false
        }
        let answer = latestVisibleAnswer()
        let chips = chipTitles(for: expectation)
        let result = classify(
            prompt: prompt,
            expectation: expectation,
            answerAppeared: appeared,
            answer: answer,
            trace: trace,
            chips: chips
        )

        return MarinaSurfaceReport(
            model: expectation?.model,
            prompt: prompt,
            expectedOutcome: expectation?.outcome.rawValue,
            expectedResponseShape: expectation?.responseShape?.rawValue,
            visibleAnswer: answer,
            responseKind: trace?.responseType,
            clarificationChips: chips.clarification,
            recoveryChips: chips.recovery,
            followUpChips: chips.followUp,
            runtimePath: trace?.routingMode,
            selectedRoute: trace?.selectedRoute,
            interpreter: trace?.sharedPipelineInterpreterSource,
            turnClassification: trace?.turnClassification,
            priorContextUsed: trace?.priorContextIncluded,
            executorRoute: trace?.sharedPipelineExecutorSummary,
            trace: trace,
            result: result
        )
    }

    func tapFirstClarificationChip() -> Bool {
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "marina.clarificationChip.")).firstMatch
        guard chip.waitForExistence(timeout: 5) else { return false }
        chip.tap()
        return true
    }

    func tapFirstClarificationChipAndWaitForResume(timeout: TimeInterval = 15) -> MarinaTraceSnapshot? {
        let previousTraceCount = traceCount()
        guard tapFirstClarificationChip() else { return nil }
        return waitForNewTrace(after: previousTraceCount, timeout: timeout) {
            $0.turnClassification == "clarificationAnswer"
        }
    }

    func traceCount() -> Int {
        readTraceLines().count
    }

    func latestTrace() -> MarinaTraceSnapshot? {
        readTraceLines().last
    }

    func clarificationChipTitles() -> [String] {
        titles(forIdentifierPrefix: "marina.clarificationChip.")
    }

    private func promptField() -> XCUIElement {
        let identified = app.textFields["marina.promptField"].firstMatch
        if identified.exists { return identified }
        return app.textFields["Message Marina"].firstMatch
    }

    private func latestVisibleAnswer() -> MarinaVisibleAnswer {
        guard let latestIndex = answerIndices().max() else {
            return MarinaVisibleAnswer(title: nil, value: "", label: "", text: "")
        }
        let title = app.staticTexts["marina.answer.\(latestIndex).title"].firstMatch
        let primaryValue = app.staticTexts["marina.answer.\(latestIndex).primaryValue"].firstMatch
        let narrative = app.staticTexts["marina.answer.\(latestIndex).narrative"].firstMatch
        let rowTexts = app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "marina.answer.\(latestIndex).row."))
            .allElementsBoundByIndex
            .filter(\.exists)
            .map(\.label)
        let parts = [
            title.exists ? title.label : nil,
            primaryValue.exists ? primaryValue.label : nil,
            narrative.exists ? narrative.label : nil
        ]
        .compactMap { $0 } + rowTexts

        return MarinaVisibleAnswer(
            title: title.exists ? title.label : nil,
            value: primaryValue.exists ? primaryValue.label : "",
            label: parts.joined(separator: "\n"),
            text: parts.joined(separator: "\n")
        )
    }

    private func answerElements() -> [Int] {
        answerIndices()
    }

    private func answerIndices() -> [Int] {
        let identifiers = app.staticTexts
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "marina.answer."))
            .allElementsBoundByIndex
            .map(\.identifier)

        let indices = identifiers.compactMap { identifier -> Int? in
            guard let range = identifier.range(of: #"^marina\.answer\.([0-9]+)"#, options: .regularExpression) else {
                return nil
            }
            let match = String(identifier[range])
            return match.split(separator: ".").last.flatMap { Int($0) }
        }
        return Array(Set(indices)).sorted()
    }

    private func chipTitles(
        for expectation: MarinaPromptExpectation?
    ) -> (clarification: [String], recovery: [String], followUp: [String]) {
        let needsClarificationChips = expectation?.outcome == .clarification
        let needsRecoveryChips = expectation?.outcome == .typedUnsupported
        return (
            needsClarificationChips ? titles(forIdentifierPrefix: "marina.clarificationChip.") : [],
            needsRecoveryChips ? titles(forIdentifierPrefix: "marina.recoveryChip.") : [],
            [String]()
        )
    }

    private func titles(forIdentifierPrefix prefix: String) -> [String] {
        app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            .allElementsBoundByIndex
            .filter(\.exists)
            .map(\.label)
    }

    private func waitForTrace(
        prompt: String,
        previousTraceCount: Int,
        timeout: TimeInterval
    ) -> MarinaTraceSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: MarinaTraceSnapshot?
        while Date() < deadline {
            let traces = readTraceLines()
            latest = traces.last
            if traces.count > previousTraceCount {
                let newTraces = traces.dropFirst(previousTraceCount)
                if let matching = newTraces.last(where: {
                    $0.originalPrompt == prompt || $0.originalPrompt.localizedCaseInsensitiveContains(prompt)
                }) {
                    return matching
                }
                return newTraces.last
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let traceElement = app.staticTexts["marina.trace.latest"].firstMatch
        if traceElement.exists {
            return MarinaTraceSnapshot(accessibilityValue: traceElement.value as? String ?? "")
        }
        return latest
    }

    private func waitForNewTrace(
        after previousTraceCount: Int,
        timeout: TimeInterval,
        matching predicate: (MarinaTraceSnapshot) -> Bool
    ) -> MarinaTraceSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latest: MarinaTraceSnapshot?
        while Date() < deadline {
            let traces = readTraceLines()
            latest = traces.last
            let newTraces = traces.dropFirst(previousTraceCount)
            if let matching = newTraces.last(where: predicate) {
                return matching
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return latest
    }

    private func readTraceLines() -> [MarinaTraceSnapshot] {
        guard let raw = try? String(contentsOf: traceOutputURL, encoding: .utf8), raw.isEmpty == false else {
            return []
        }
        return raw
            .split(separator: "\n")
            .compactMap { line in
                try? JSONDecoder().decode(MarinaTraceSnapshot.self, from: Data(line.utf8))
            }
    }

    private func classify(
        prompt: String,
        expectation: MarinaPromptExpectation?,
        answerAppeared: Bool,
        answer: MarinaVisibleAnswer,
        trace: MarinaTraceSnapshot?,
        chips: (clarification: [String], recovery: [String], followUp: [String])
    ) -> MarinaSurfaceResult {
        guard answerAppeared else {
            return MarinaSurfaceResult(passed: false, category: .noVisibleAnswer, reason: "No new answer appeared for prompt.")
        }
        guard answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return MarinaSurfaceResult(passed: false, category: .noVisibleAnswer, reason: "Latest answer had no readable text.")
        }
        guard let trace else {
            return MarinaSurfaceResult(passed: false, category: .traceUnavailable, reason: "No Marina trace was exported or surfaced.")
        }
        if trace.originalPrompt != prompt {
            return MarinaSurfaceResult(
                passed: false,
                category: .promptNotSubmitted,
                reason: "Expected trace prompt '\(prompt)', saw '\(trace.originalPrompt)'."
            )
        }
        guard trace.routingMode == "shared_pipeline" else {
            return MarinaSurfaceResult(passed: false, category: .wrongRuntimeRoute, reason: "Expected shared_pipeline, saw \(trace.routingMode).")
        }
        if trace.selectedRoute == "shared_fallback" || trace.sharedPipelinePath == "legacy" {
            return MarinaSurfaceResult(passed: false, category: .legacyRouteInterception, reason: "Prompt fell through to legacy path.")
        }
        if trace.turnClassification == "freshQuestion", trace.priorContextIncluded == true {
            return MarinaSurfaceResult(passed: false, category: .stalePriorContext, reason: "Fresh question included prior context.")
        }
        let bridge = trace.sharedPipelineResponseBridgeSummary ?? ""
        let isUnsupported = bridge.localizedCaseInsensitiveContains("responseShape=unsupported")
            || answer.text.localizedCaseInsensitiveContains("different way")
            || answer.text.localizedCaseInsensitiveContains("Reason\nunsupported")
        let isClarification = bridge.localizedCaseInsensitiveContains("responseShape=clarification")
            || answer.title?.localizedCaseInsensitiveContains("choice") == true
        if expectation?.outcome == .handled, isUnsupported {
            return MarinaSurfaceResult(passed: false, category: .unsupportedDespiteSemanticSupport, reason: "Supported prompt returned typed unsupported.")
        }
        if expectation?.outcome == .handled, isClarification {
            return MarinaSurfaceResult(passed: false, category: .unexpectedClarification, reason: "Supported prompt unexpectedly asked for clarification.")
        }
        if expectation?.outcome == .clarification, chips.clarification.isEmpty {
            return MarinaSurfaceResult(passed: false, category: .missingClarificationChips, reason: "Expected actionable clarification chips.")
        }
        if let expectedShape = expectation?.responseShape,
           bridge.isEmpty == false,
           bridge.localizedCaseInsensitiveContains("responseShape=\(expectedShape.rawValue)") == false {
            return MarinaSurfaceResult(
                passed: false,
                category: .responseShapeMismatch,
                reason: "Expected responseShape=\(expectedShape.rawValue), saw \(bridge)."
            )
        }
        if let missing = expectation?.requiredVisibleText.first(where: { answer.text.localizedCaseInsensitiveContains($0) == false }) {
            return MarinaSurfaceResult(
                passed: false,
                category: .responseBridgeMismatch,
                reason: "Expected visible answer to include '\(missing)'."
            )
        }
        if let forbidden = expectation?.forbiddenVisibleText.first(where: { answer.text.localizedCaseInsensitiveContains($0) }) {
            return MarinaSurfaceResult(
                passed: false,
                category: .responseBridgeMismatch,
                reason: "Visible answer included forbidden generic text '\(forbidden)'."
            )
        }
        if answer.text.localizedCaseInsensitiveContains("different way"),
           trace.responseType != "message" {
            return MarinaSurfaceResult(passed: false, category: .responseBridgeMismatch, reason: "Visible unsupported-style text did not match message response type.")
        }
        return MarinaSurfaceResult(passed: true, category: .pass, reason: "Surface response and trace were captured.")
    }

    private func waitUntil(timeout: TimeInterval, predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return predicate()
    }
}

enum MarinaRuntimeLaunchArgument {
    static let sharedPipelineEnabled = "debug_marina_shared_pipeline_enabled"
    static let nlqDisabled = "debug_marina_nlq_v1_enabled=false"
    static let aiOptInDisabled = "marina_ai_opt_in_enabled=false"
}

struct MarinaPromptExpectation {
    let model: String
    let outcome: Outcome
    let responseShape: ResponseShape?
    let requiredVisibleText: [String]
    let forbiddenVisibleText: [String]

    init(
        model: String,
        outcome: Outcome,
        responseShape: ResponseShape?,
        requiredVisibleText: [String] = [],
        forbiddenVisibleText: [String] = []
    ) {
        self.model = model
        self.outcome = outcome
        self.responseShape = responseShape
        self.requiredVisibleText = requiredVisibleText
        self.forbiddenVisibleText = forbiddenVisibleText
    }

    enum Outcome: String {
        case handled
        case clarification
        case typedUnsupported
    }

    enum ResponseShape: String {
        case summaryCard
        case relationshipList
        case membershipStatus
        case rankedList
        case scalarCurrency
        case groupedBreakdown
        case clarification
        case unsupported
    }
}
