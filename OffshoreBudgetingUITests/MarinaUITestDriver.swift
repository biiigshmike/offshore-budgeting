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

    func launchHarness(
        fakeAI: Bool = true,
        aiOptIn: Bool? = nil
    ) {
        try? FileManager.default.removeItem(at: traceOutputURL)
        app.launchArguments = [
            "-uiTesting",
            "-uiTestingReset",
            "-uiTestingMarinaHarness"
        ]
        if aiOptIn == false {
            app.launchArguments.append("-uiTestingMarinaAIOptOutDefault")
        }
        var environment = [
            "MARINA_UI_TRACE_OUTPUT_PATH": traceOutputURL.path,
            "MARINA_UI_FIXED_NOW_ISO8601": "2026-05-15T12:00:00Z"
        ]
        if fakeAI {
            environment["MARINA_UI_FAKE_AI_INTERPRETER"] = "1"
        }
        if let aiOptIn, aiOptIn {
            environment["marina_ai_opt_in_enabled"] = aiOptIn ? "1" : "0"
        }
        app.launchEnvironment = environment
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
        runPrompt(
            prompt,
            expectation: expectation,
            timeout: timeout,
            allowCommandOrUnsupportedTrace: false
        )
    }

    func runCommandOrUnsupportedPrompt(
        _ prompt: String,
        expectation: MarinaPromptExpectation,
        timeout: TimeInterval = 15
    ) -> MarinaSurfaceReport {
        runPrompt(
            prompt,
            expectation: expectation,
            timeout: timeout,
            allowCommandOrUnsupportedTrace: true
        )
    }

    private func runPrompt(
        _ prompt: String,
        expectation: MarinaPromptExpectation?,
        timeout: TimeInterval,
        allowCommandOrUnsupportedTrace: Bool
    ) -> MarinaSurfaceReport {
        let previousTraceCount = readTraceLines().count
        submit(prompt)

        let trace = waitForTrace(prompt: prompt, previousTraceCount: previousTraceCount, timeout: timeout)
        let expectedAnswerIndex = answerIndex(for: prompt, preferredIndex: previousTraceCount)
        let appeared = trace != nil || waitUntil(timeout: min(timeout, 2)) {
            answerExists(at: expectedAnswerIndex)
        }
        if let requiredText = expectation?.requiredVisibleText, requiredText.isEmpty == false {
            _ = waitUntil(timeout: min(timeout, 4)) {
                visibleAnswer(
                    preferredIndex: expectedAnswerIndex,
                    requiredText: requiredText
                ).containsAll(requiredText)
            }
        }
        let answer = visibleAnswer(
            preferredIndex: expectedAnswerIndex,
            requiredText: expectation?.requiredVisibleText ?? []
        )
        let chips = chipTitles(for: expectation)
        let result = classify(
            prompt: prompt,
            expectation: expectation,
            answerAppeared: appeared,
            answer: answer,
            trace: trace,
            chips: chips,
            allowCommandOrUnsupportedTrace: allowCommandOrUnsupportedTrace
        )

        return MarinaSurfaceReport(
            model: expectation?.model,
            prompt: prompt,
            expectedOutcome: expectation?.outcome.rawValue,
            expectedRequestShape: expectation?.requestShape?.rawValue,
            expectedResponseShape: expectation?.responseShape?.rawValue,
            visibleAnswer: answer,
            responseKind: trace?.responseType,
            clarificationChips: chips.clarification,
            recoveryChips: chips.recovery,
            followUpChips: chips.followUp,
            runtimePath: trace?.routingMode,
            selectedRoute: trace?.selectedRoute,
            interpreter: trace?.foundationPipelineInterpreterSource,
            turnClassification: trace?.turnClassification,
            priorContextUsed: trace?.priorContextIncluded,
            executorRoute: trace?.foundationPipelineExecutorSummary,
            diagnostics: diagnostics(from: trace),
            trace: trace,
            result: result
        )
    }

    func tapFirstClarificationChip() -> Bool {
        let chip = app.buttons["marina.clarificationChip.0"].firstMatch
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

    func typeClarificationReplyAndWaitForResume(
        _ reply: String,
        timeout: TimeInterval = 15
    ) -> MarinaTraceSnapshot? {
        let previousTraceCount = traceCount()
        submit(reply)
        return waitForNewTrace(after: previousTraceCount, timeout: timeout) {
            $0.turnClassification == "clarificationAnswer"
        }
    }

    func traceCount() -> Int {
        readTraceLines().count
    }

    func latestTrace() -> MarinaTraceSnapshot? {
        readTraceLines().last ?? latestTraceFromAccessibility()
    }

    func clarificationChipTitles() -> [String] {
        titles(forIdentifierPrefix: "marina.clarificationChip.")
    }

    private func promptField() -> XCUIElement {
        let identified = app.textFields["marina.promptField"].firstMatch
        if identified.exists { return identified }
        return app.textFields["Message Marina"].firstMatch
    }

    private func latestVisibleAnswer(preferredIndex: Int) -> MarinaVisibleAnswer {
        guard answerExists(at: preferredIndex) else {
            return MarinaVisibleAnswer(title: nil, value: "", label: "", text: "", rowTitles: [], rowValues: [])
        }
        let container = app.descendants(matching: .any)["marina.answer.\(preferredIndex)"].firstMatch
        let title = app.descendants(matching: .any)["marina.answer.\(preferredIndex).title"].firstMatch
        let primaryValue = app.descendants(matching: .any)["marina.answer.\(preferredIndex).primaryValue"].firstMatch
        let narrative = app.descendants(matching: .any)["marina.answer.\(preferredIndex).narrative"].firstMatch
        let rows = boundedAnswerRows(answerIndex: preferredIndex)
        let attachmentRows = boundedAttachmentRows(answerIndex: preferredIndex)
        let visibleStaticTexts = visibleStaticTextLabels(in: container)
        let rowTexts = rows.flatMap { row in
            [row.title, row.value].compactMap { $0 }
        }
        let attachmentRowTexts = attachmentRows.flatMap { row in
            [row.title, row.value].compactMap { $0 }
        }
        let attachmentText = attachmentText(in: container, answerIndex: preferredIndex)
        let containerText = [
            container.exists ? container.label : nil,
            container.exists ? container.value as? String : nil
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let parts = [
            title.exists ? title.label : nil,
            primaryValue.exists ? primaryValue.label : nil,
            narrative.exists ? narrative.label : nil
        ]
        .compactMap { $0 } + rowTexts + attachmentRowTexts + attachmentText + visibleStaticTexts + containerText
        let text = deduped(parts).joined(separator: "\n")
        let inferredRowTitles = inferredRowTitles(
            from: visibleStaticTexts,
            title: title.exists ? title.label : nil,
            primaryValue: primaryValue.exists ? primaryValue.label : nil,
            narrative: narrative.exists ? narrative.label : nil
        )

        return MarinaVisibleAnswer(
            title: title.exists ? title.label : nil,
            value: primaryValue.exists ? primaryValue.label : "",
            label: text,
            text: text,
            rowTitles: rows.map { $0.title } + attachmentRows.map { $0.title } + inferredRowTitles,
            rowValues: rows.compactMap { $0.value } + attachmentRows.compactMap { $0.value }
        )
    }

    private func attachmentText(in container: XCUIElement, answerIndex: Int) -> [String] {
        let identifiers = [
            "marina.answer.\(answerIndex).attachmentText",
            "marina.cardSummary",
            "marina.entitySummary",
            "marina.rowList",
            "marina.metricSummary",
            "marina.comparisonSummary",
            "marina.breakdownList",
            "marina.trendChart",
            "marina.formulaContract",
            "marina.clarification",
            "marina.deadEnd",
            "marina.genericSummary"
        ]
        return deduped(identifiers.flatMap { identifier in
            elementText(scopedElement(identifier, in: container, fallbackToGlobal: false))
        })
    }

    private func elementText(_ element: XCUIElement) -> [String] {
        guard element.exists else { return [] }
        return [
            element.label,
            element.value as? String
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    private func scopedElement(
        _ identifier: String,
        in container: XCUIElement,
        fallbackToGlobal: Bool = true
    ) -> XCUIElement {
        if container.exists {
            let scoped = container.descendants(matching: .any)[identifier].firstMatch
            if scoped.exists { return scoped }
        }
        guard fallbackToGlobal else {
            return app.descendants(matching: .any)["__missing__\(identifier)"].firstMatch
        }
        return app.descendants(matching: .any)[identifier].firstMatch
    }

    private func visibleAnswer(preferredIndex: Int, requiredText: [String]) -> MarinaVisibleAnswer {
        if requiredText.isEmpty == false,
           let matchingAnswer = answerContainingAll(requiredText, around: preferredIndex) {
            return matchingAnswer
        }
        return latestVisibleAnswer(preferredIndex: preferredIndex)
    }

    private func answerContainingAll(_ requiredText: [String], around preferredIndex: Int) -> MarinaVisibleAnswer? {
        let upperBound = max(preferredIndex + 8, 8)
        for index in stride(from: upperBound, through: 0, by: -1) {
            guard answerExists(at: index) else { continue }
            let answer = latestVisibleAnswer(preferredIndex: index)
            if answer.containsAll(requiredText) {
                return answer
            }
        }
        return nil
    }

    private func answerIndex(for prompt: String, preferredIndex: Int) -> Int {
        let upperBound = max(preferredIndex + 5, 5)
        for index in stride(from: upperBound, through: 0, by: -1) {
            let userMessage = app.descendants(matching: .any)["marina.userMessage.\(index)"].firstMatch
            if userMessage.exists,
               userMessage.label.trimmingCharacters(in: .whitespacesAndNewlines) == prompt {
                return index
            }
        }
        if answerExists(at: preferredIndex) {
            return preferredIndex
        }
        return latestExistingAnswerIndex(maxIndex: upperBound) ?? preferredIndex
    }

    private func latestExistingAnswerIndex(maxIndex: Int) -> Int? {
        for index in stride(from: maxIndex, through: 0, by: -1) {
            if answerExists(at: index) {
                return index
            }
        }
        return nil
    }

    private func answerExists(at index: Int) -> Bool {
        let answer = app.descendants(matching: .any)["marina.answer.\(index)"].firstMatch
        if answer.exists { return true }
        return app.descendants(matching: .any)["marina.answer.\(index).title"].firstMatch.exists
    }

    private func boundedAnswerRows(answerIndex: Int, limit: Int = 16) -> [(title: String, value: String?)] {
        var rows: [(title: String, value: String?)] = []
        for rowIndex in 0..<limit {
            let title = app.descendants(matching: .any)["marina.answer.\(answerIndex).row.\(rowIndex).title"].firstMatch
            let value = app.descendants(matching: .any)["marina.answer.\(answerIndex).row.\(rowIndex).value"].firstMatch
            let titleExists = title.exists
            let valueExists = value.exists
            if titleExists {
                rows.append((title.label, valueExists ? value.label : nil))
            } else if valueExists {
                rows.append((value.label, nil))
            }
            if titleExists == false, valueExists == false, rows.isEmpty == false {
                break
            }
        }
        return rows
    }

    private func boundedAttachmentRows(answerIndex: Int, limit: Int = 16) -> [(title: String, value: String?)] {
        let prefixes = [
            "marina.answer.\(answerIndex).attachment",
            "marina.answer.\(answerIndex).metricSummary",
            "marina.answer.\(answerIndex).comparisonSummary",
            "marina.answer.\(answerIndex).breakdownList",
            "marina.answer.\(answerIndex).formulaContract",
            "marina.answer.\(answerIndex).clarification",
            "marina.answer.\(answerIndex).deadEnd",
            "marina.answer.\(answerIndex).genericSummary"
        ]
        return prefixes.flatMap { prefix in
            boundedAttachmentRows(prefix: prefix, limit: limit)
        }
    }

    private func boundedAttachmentRows(
        prefix: String,
        limit: Int
    ) -> [(title: String, value: String?)] {
        var rows: [(title: String, value: String?)] = []
        for rowIndex in 0..<limit {
            let title = app.descendants(matching: .any)["\(prefix).row.\(rowIndex).title"].firstMatch
            let value = app.descendants(matching: .any)["\(prefix).row.\(rowIndex).value"].firstMatch
            let titleExists = title.exists
            let valueExists = value.exists
            if titleExists {
                rows.append((title.label, valueExists ? value.label : nil))
            } else if valueExists {
                rows.append((value.label, nil))
            }
            if titleExists == false, valueExists == false, rows.isEmpty == false {
                break
            }
        }
        return rows
    }

    private func visibleStaticTextLabels(in container: XCUIElement) -> [String] {
        guard container.exists else { return [] }
        let frame = container.frame
        guard frame.isEmpty == false else { return [] }

        return deduped(
            app.staticTexts.allElementsBoundByIndex.compactMap { element in
                guard element.exists else { return nil }
                let elementFrame = element.frame
                guard elementFrame.isEmpty == false else { return nil }
                let midpoint = CGPoint(x: elementFrame.midX, y: elementFrame.midY)
                guard frame.contains(midpoint) else { return nil }
                let label = element.label.trimmingCharacters(in: .whitespacesAndNewlines)
                return label.isEmpty ? nil : label
            }
        )
    }

    private func inferredRowTitles(
        from labels: [String],
        title: String?,
        primaryValue: String?,
        narrative: String?
    ) -> [String] {
        let excluded = Set([title, primaryValue, narrative].compactMap {
            $0?.trimmingCharacters(in: .whitespacesAndNewlines)
        })

        return deduped(labels).filter { label in
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, excluded.contains(trimmed) == false else { return false }
            guard trimmed.count <= 80 else { return false }
            guard looksLikeValueText(trimmed) == false else { return false }
            return true
        }
    }

    private func looksLikeValueText(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("$") || trimmed.contains("%") { return true }
        if Double(trimmed.replacingOccurrences(of: ",", with: "")) != nil { return true }
        if trimmed.range(of: #"^[A-Z][a-z]{2,8}\s+\d{1,2},?\s+\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        if trimmed.range(of: #"^[A-Z][a-z]{2,8}\s+\d{4}$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private func deduped(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalized.isEmpty == false, seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
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
        var titles: [String] = []
        for index in 0..<8 {
            let button = app.buttons["\(prefix)\(index)"].firstMatch
            guard button.exists else {
                if titles.isEmpty == false { break }
                continue
            }
            titles.append(button.label)
        }
        return titles
    }

    private func waitForTrace(
        prompt: String,
        previousTraceCount: Int,
        timeout: TimeInterval
    ) -> MarinaTraceSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        var latestNewTrace: MarinaTraceSnapshot?
        while Date() < deadline {
            let traces = readTraceLines()
            if traces.count > previousTraceCount {
                let newTraces = traces.dropFirst(previousTraceCount)
                if let matching = newTraces.last(where: {
                    promptMatches(tracePrompt: $0.originalPrompt, submittedPrompt: prompt)
                }) {
                    return matching
                }
                latestNewTrace = newTraces.last ?? latestNewTrace
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        let traceElement = app.staticTexts["marina.trace.latest"].firstMatch
        if traceElement.exists {
            let fallback = MarinaTraceSnapshot(accessibilityValue: traceElement.value as? String ?? "")
            if promptMatches(tracePrompt: fallback.originalPrompt, submittedPrompt: prompt) {
                return fallback
            }
        }
        return latestNewTrace
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
            if let fallback = latestTraceFromAccessibility(), predicate(fallback) {
                return fallback
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        if let fallback = latestTraceFromAccessibility(), predicate(fallback) {
            return fallback
        }
        return latest
    }

    private func latestTraceFromAccessibility() -> MarinaTraceSnapshot? {
        let traceElement = app.staticTexts["marina.trace.latest"].firstMatch
        guard traceElement.exists else { return nil }
        let value = traceElement.value as? String ?? ""
        guard value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }
        return MarinaTraceSnapshot(accessibilityValue: value)
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
        chips: (clarification: [String], recovery: [String], followUp: [String]),
        allowCommandOrUnsupportedTrace: Bool = false
    ) -> MarinaSurfaceResult {
        guard answerAppeared else {
            return MarinaSurfaceResult(passed: false, category: .noVisibleAnswer, reason: "No new answer appeared for prompt.")
        }
        guard answer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return MarinaSurfaceResult(passed: false, category: .noVisibleAnswer, reason: "Latest answer had no readable text.")
        }
        let looksUnsupported = answer.text.localizedCaseInsensitiveContains("different way")
            || answer.text.localizedCaseInsensitiveContains("unsupported")
            || answer.text.localizedCaseInsensitiveContains("read-only")
            || answer.text.localizedCaseInsensitiveContains("can't")
            || answer.text.localizedCaseInsensitiveContains("cannot")
        guard let trace else {
            if allowCommandOrUnsupportedTrace,
               expectation?.outcome == .typedUnsupported,
               looksUnsupported {
                return MarinaSurfaceResult(passed: true, category: .pass, reason: "Typed unsupported response was visible without a prompt-specific Foundation trace.")
            }
            return MarinaSurfaceResult(passed: false, category: .traceUnavailable, reason: "No Marina trace was exported or surfaced.")
        }
        if promptMatches(tracePrompt: trace.originalPrompt, submittedPrompt: prompt) == false {
            if allowCommandOrUnsupportedTrace,
               expectation?.outcome == .typedUnsupported,
               (looksUnsupported || trace.originalPrompt.isEmpty) {
                return MarinaSurfaceResult(passed: true, category: .pass, reason: "Typed unsupported response was visible; latest trace belonged to a non-read or accessibility-only turn.")
            }
            return MarinaSurfaceResult(
                passed: false,
                category: .promptNotSubmitted,
                reason: "Expected trace prompt '\(prompt)', saw '\(trace.originalPrompt)'."
            )
        }
        guard trace.routingMode == "foundationPipeline" else {
            if allowCommandOrUnsupportedTrace,
               expectation?.outcome == .typedUnsupported {
                return MarinaSurfaceResult(passed: true, category: .pass, reason: "Prompt was handled outside the Foundation read route.")
            }
            return MarinaSurfaceResult(passed: false, category: .wrongRuntimeRoute, reason: "Expected foundationPipeline, saw \(trace.routingMode).")
        }
        if trace.selectedRoute != "foundationModels" && trace.selectedRoute != "clarification" {
            return MarinaSurfaceResult(passed: false, category: .nonFoundationRouteInterception, reason: "Prompt did not select the Foundation Models route.")
        }
        if trace.foundationPipelinePath != "foundationModels" {
            return MarinaSurfaceResult(passed: false, category: .nonFoundationRouteInterception, reason: "Trace did not use the Foundation Models pipeline path.")
        }
        if let interpreter = trace.foundationPipelineInterpreterSource,
           interpreter != "foundationModels" {
            return MarinaSurfaceResult(passed: false, category: .nonFoundationRouteInterception, reason: "Trace did not use the Foundation Models interpreter.")
        }
        if answer.text.localizedCaseInsensitiveContains("MarinaResponseRules")
            || answer.text.localizedCaseInsensitiveContains("MarinaResponses")
            || answer.text.localizedCaseInsensitiveContains("bestie") {
            return MarinaSurfaceResult(passed: false, category: .nonFoundationRouteInterception, reason: "Prompt surfaced old canned copy.")
        }
        if trace.turnClassification == "freshQuestion", trace.priorContextIncluded == true {
            return MarinaSurfaceResult(passed: false, category: .stalePriorContext, reason: "Fresh question included prior context.")
        }
        let bridge = trace.foundationPipelineResponseBridgeSummary ?? ""
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
        if expectation?.outcome == .clarification, isUnsupported {
            return MarinaSurfaceResult(
                passed: false,
                category: .ambiguityCollapsedToUnsupported,
                reason: "Expected typed clarification, but candidate resolved/validated as unsupported. candidate=\(trace.foundationPipelineCandidateSummary ?? "nil"); resolver=\(trace.foundationPipelineResolverSummary ?? "nil"); semanticResolver=\(trace.foundationPipelineSemanticResolverSummary ?? "nil"); validator=\(trace.foundationPipelineValidatorSummary ?? "nil")"
            )
        }
        if expectation?.outcome == .clarification, isClarification == false {
            return MarinaSurfaceResult(
                passed: false,
                category: .ambiguityCollapsedToSingleType,
                reason: "Expected typed clarification, but the prompt resolved to a handled response. responseType=\(trace.responseType ?? "nil"); candidate=\(trace.foundationPipelineCandidateSummary ?? "nil"); resolver=\(trace.foundationPipelineResolverSummary ?? "nil"); semanticResolver=\(trace.foundationPipelineSemanticResolverSummary ?? "nil"); executor=\(trace.foundationPipelineExecutorSummary ?? "nil")"
            )
        }
        if expectation?.outcome == .clarification, chips.clarification.isEmpty {
            return MarinaSurfaceResult(passed: false, category: .missingClarificationChips, reason: "Expected actionable clarification chips.")
        }
        if let expectedShape = expectation?.requestShape {
            let candidate = trace.foundationPipelineCandidateSummary ?? ""
            if candidate.localizedCaseInsensitiveContains("requestShape=\(expectedShape.rawValue)") == false {
                return MarinaSurfaceResult(
                    passed: false,
                    category: .requestShapeMismatch,
                    reason: "Expected requestShape=\(expectedShape.rawValue), saw \(candidate.isEmpty ? "nil" : candidate)."
                )
            }
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

    private func promptMatches(tracePrompt: String, submittedPrompt: String) -> Bool {
        let trace = tracePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let submitted = submittedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trace.isEmpty == false, submitted.isEmpty == false else {
            return trace == submitted
        }
        return trace.localizedCaseInsensitiveCompare(submitted) == .orderedSame
            || trace.localizedCaseInsensitiveContains(submitted)
    }

    private func diagnostics(from trace: MarinaTraceSnapshot?) -> MarinaSurfaceDiagnostics? {
        guard let trace else { return nil }
        return MarinaSurfaceDiagnostics(
            candidateSummary: trace.foundationPipelineCandidateSummary,
            resolverSummary: trace.foundationPipelineResolverSummary,
            semanticResolverSummary: trace.foundationPipelineSemanticResolverSummary,
            validatorSummary: trace.foundationPipelineValidatorSummary,
            unsupportedReason: unsupportedReason(from: trace)
        )
    }

    private func unsupportedReason(from trace: MarinaTraceSnapshot) -> String? {
        [
            trace.foundationPipelineValidatorSummary,
            trace.foundationPipelineSemanticValidationSummary,
            trace.foundationPipelineResponseBridgeSummary,
            trace.selectedRouteReason
        ]
        .compactMap { $0 }
        .first { $0.localizedCaseInsensitiveContains("unsupported") }
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

struct MarinaPromptExpectation {
    let model: String
    let outcome: Outcome
    let requestShape: RequestShape?
    let responseShape: ResponseShape?
    let requiredVisibleText: [String]
    let forbiddenVisibleText: [String]

    init(
        model: String,
        outcome: Outcome,
        requestShape: RequestShape? = nil,
        responseShape: ResponseShape?,
        requiredVisibleText: [String] = [],
        forbiddenVisibleText: [String] = []
    ) {
        self.model = model
        self.outcome = outcome
        self.requestShape = requestShape
        self.responseShape = responseShape
        self.requiredVisibleText = requiredVisibleText
        self.forbiddenVisibleText = forbiddenVisibleText
    }

    enum Outcome: String {
        case handled
        case clarification
        case typedUnsupported
    }

    enum RequestShape: String {
        case objectInventoryList
        case ledgerRowList
        case objectDetails
        case relationshipList
        case aggregateMetric
    }

    enum ResponseShape: String {
        case summaryCard
        case relationshipList
        case membershipStatus
        case rankedList
        case scalarCurrency
        case groupedBreakdown
        case comparison
        case clarification
        case unsupported
    }
}
