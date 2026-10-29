import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaQueryOrchestrationTests {
    @Test func queryOutcomeReferencesCannotBeEntityOrEvidenceReferences() {
        for reference in MarinaQueryResultReference.allCases {
            #expect(MarinaQueryOutcome(act: .answer, primary: reference, supporting: []).hasValidReferenceShape)
        }
        for reference in ["r1", "q0f0", "q01", "q-1", "q١", "q", "q8", "q99", "Personal", ""] {
            #expect(MarinaQueryResultReference(rawValue: reference) == nil)
        }
        let repeatedPrimary = MarinaQueryOutcome(act: .answer, primary: .q0, supporting: [.q0])
        #expect(repeatedPrimary.hasValidReferenceShape)
        #expect(repeatedPrimary.normalizedSupporting.isEmpty)
        let repeatedSupport = MarinaQueryOutcome(act: .answer, primary: .q0, supporting: [.q1, .q1])
        #expect(repeatedSupport.normalizedSupporting == ["q1"])
        let potentiallyMissing = MarinaQueryOutcome(act: .answer, primary: .q0, supporting: [.q7, .q0])
        #expect(potentiallyMissing.normalizedSupporting == ["q7"])
        #expect(!MarinaQueryOutcome(act: .answer, primary: .q0, supporting: [.q1, .q2, .q3]).hasValidReferenceShape)
        #expect(MarinaQueryOutcome(act: .greeting, primary: nil, supporting: []).hasValidReferenceShape)
    }

    @Test func queryAndNarrationUseActualArrayBounds() throws {
        let query = try schemaObject(MarinaQueryOutcome.generationSchema)
        #expect(allValues(for: "maxItems", in: query).contains { ($0 as? Int) == 3 })
        #expect(allValues(for: "enum", in: query).compactMap { $0 as? [String] }
            .contains(MarinaQueryResultReference.allCases.map(\.rawValue)))
        let narration = try schemaObject(MarinaNarrationDraft.generationSchema)
        #expect(allValues(for: "maxItems", in: narration).contains { ($0 as? Int) == 6 })
    }

    @Test func unusedConversationReferencesAreIgnoredOnlyWithoutFinancialReadsOrIntent() throws {
        let greeting = try MarinaQueryOutcome(GeneratedContent(json: "{\"act\":\"greeting\",\"results\":[\"q7\"]}"))
        let normalized = try #require(greeting.normalizedConversation(hasToolResults: false, requiresFreshRead: false))
        #expect(normalized.act == .greeting && normalized.results.isEmpty)
        #expect(greeting.normalizedConversation(hasToolResults: true, requiresFreshRead: false) == nil)
        #expect(greeting.normalizedConversation(hasToolResults: false, requiresFreshRead: true) == nil)
        let answer = MarinaQueryOutcome(act: .answer, primary: .q7, supporting: [])
        #expect(answer.normalizedConversation(hasToolResults: false, requiresFreshRead: false) == nil)
        #expect(answer.primary == .q7)
        let excessive = MarinaQueryOutcome(act: .help, primary: .q0, supporting: [.q1, .q2, .q3])
        #expect(excessive.normalizedConversation(hasToolResults: false, requiresFreshRead: false) == nil)
    }

    @Test func financialNarrationCanOnlyGenerateCurrentEvidenceReferencesAndNoQuestion() throws {
        let evidence = [
            MarinaNarrationEvidence(id: "q2f0", subject: "Dining", relation: "totals", value: "$40", scope: "October", isFocus: true),
            MarinaNarrationEvidence(id: "q2f1", subject: "Its share", relation: "is", value: "40%", scope: "October", isFocus: false)
        ]
        let object = try schemaObject(MarinaNarrationSchema.make(act: .answer, evidence: evidence))
        #expect(allValues(for: "maxItems", in: object).contains { ($0 as? Int) == 2 })
        let root = try #require(object as? [String: Any])
        // Older Foundation Models versions retain local references and represent
        // string choices as anyOf singleton enums. Assert the same constraints on
        // the actual fields rather than depending on one serialized JSON layout.
        let reference = try #require(schema(at: ["properties", "claims", "items", "properties", "reference"], in: root))
        #expect(stringChoices(reference, root: root) == ["q2f0", "q2f1"])
        let act = try #require(schema(at: ["properties", "act"], in: root))
        #expect(stringChoices(act, root: root) == ["answer"])
        for field in ["introduction", "question"] {
            let text = try #require(schema(at: ["properties", field], in: root))
            #expect(stringChoices(text, root: root) == [""])
        }
        let stale = MarinaNarrationDraft(act: .answer, introduction: "", claims: [
            .init(reference: "q0f0", wording: "{subject} {relation} {value} for {scope}.")
        ], question: "")
        #expect(MarinaNarrationValidator.render(draft: stale, evidence: evidence, requiresFinancialEvidence: true) == nil)
        let supportFirst = MarinaNarrationDraft(act: .answer, introduction: "", claims: [
            .init(reference: "q2f1", wording: "{subject} {relation} {value} for {scope}."),
            .init(reference: "q2f0", wording: "{subject} {relation} {value}.")
        ], question: "")
        #expect(MarinaNarrationValidator.render(draft: supportFirst, evidence: evidence, requiresFinancialEvidence: true) == nil)
    }

    @Test func conversationSchemaCannotGenerateFinancialClaims() throws {
        let object = try schemaObject(MarinaNarrationSchema.make(act: .greeting, evidence: []))
        #expect(allValues(for: "maxItems", in: object).contains { ($0 as? Int) == 0 })
        #expect(allValues(for: "enum", in: object).compactMap { $0 as? [String] }.contains(["greeting"]))
    }

    @Test func narrationInstructionsOnlyContainTheValidatedActsTask() {
        let answer = MarinaConversationRuntime.narrationInstructions(for: .answer)
        #expect(answer.contains("first focal fact first"))
        #expect(!answer.contains("Introduce yourself"))
        #expect(!answer.contains("Ask whether to focus"))
        let greeting = MarinaConversationRuntime.narrationInstructions(for: .greeting)
        #expect(greeting.contains("Introduce yourself"))
        #expect(!greeting.contains("evidence references"))
        #expect(!greeting.contains("Ask whether to focus"))
        let clarification = MarinaConversationRuntime.narrationInstructions(for: .clarification)
        #expect(clarification.contains("Ask whether to focus"))
        #expect(!clarification.contains("Introduce yourself"))
    }

    @Test func emptyInventoryIsVerifiedZeroEvidenceRatherThanMissingEvidence() throws {
        let request = MarinaDataRequest(tool: .findRecords)
        let result = MarinaDataResult(status: "empty", scope: "Personal", totalCount: 0)
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
        let fact = try #require(facts.first)
        #expect(fact.value == "0")
        #expect(fact.isFocus)
        #expect(facts.count == 1)
    }

    @Test func rejectedSelectionRestoresThePreviouslyAnsweredScopeAndDates() throws {
        let runtime = MarinaConversationRuntime()
        let workspaceID = UUID(), chatID = UUID()
        let original = MarinaDataRequest(operation: .ranking, tool: .expenses,
            startDate: "2026-09-01", endDate: "2026-09-30", cardID: UUID().uuidString, grouping: .category)
        #expect(runtime.recordUIRead(request: original, result: .init(scope: "September"), answerID: UUID(),
            workspaceID: workspaceID, chatID: chatID, restoredMemory: nil))
        let before = try #require(runtime.memory)
        let exploratory = MarinaDataRequest(tool: .expenses,
            startDate: "2026-10-01", endDate: "2026-10-31", cardID: UUID().uuidString)
        #expect(runtime.recordUIRead(request: exploratory, result: .init(scope: "October"), answerID: UUID(),
            workspaceID: workspaceID, chatID: chatID, restoredMemory: nil))
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
        runtime.rejectQuerySelection(restoring: before)
        #expect(runtime.memory == before)
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-09-01")
        #expect(runtime.memory?.latestFinancialQuery?.selection?.cardID == original.cardID)
    }

    @Test func negativeSavingsBalanceStaysSignedInVerifiedNarration() throws {
        let request = MarinaDataRequest(tool: .accounts, scope: .savings)
        let result = MarinaDataResult(scope: "Personal", metrics: [
            .init(label: "Savings current balance", value: -25)
        ])
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
        let fact = try #require(facts.first)
        #expect(fact.value == CurrencyFormatter.string(from: -25))
        let draft = MarinaNarrationDraft(act: .answer, introduction: "", claims: [
            .init(reference: fact.id, wording: "{subject} {relation} {value} for {scope}.")
        ], question: "")
        let rendered = try #require(MarinaNarrationValidator.render(draft: draft, evidence: facts, requiresFinancialEvidence: true))
        #expect(rendered.contains(CurrencyFormatter.string(from: -25)))
    }

    @Test func comparisonRequiresBothSidesAndCalculatedDifferenceButNotSupportingFacts() throws {
        for compareLeaders in [false, true] {
            let request = MarinaDataRequest(metric: .total, compareLeaders: compareLeaders,
                operation: .comparison, tool: .expenses, grouping: compareLeaders ? .category : .none)
            var result = MarinaDataResult(scope: "October", metrics: [
                .init(label: "Total", value: 350), .init(label: "Comparison total", value: 300),
                .init(label: "Difference", value: 50)
            ])
            if compareLeaders {
                result.report = .init(leaders: [
                    .init(scope: "October", title: "Dining", amount: 350),
                    .init(scope: "June", title: "Travel", amount: 300)
                ])
            }
            var evidence = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
            #expect(evidence.count == 3 && evidence.allSatisfy(\.isFocus))
            let required = evidence
            evidence.append(.init(id: "q1f0", subject: "Your income", relation: "totals", value: "$500",
                scope: "October", isFocus: false))
            func draft(_ facts: [MarinaNarrationEvidence]) -> MarinaNarrationDraft {
                .init(act: .answer, introduction: "", claims: facts.map {
                    .init(reference: $0.id, wording: "{subject} {relation} {value} for {scope}.")
                }, question: "")
            }
            #expect(MarinaNarrationValidator.render(draft: draft(required), evidence: evidence, requiresFinancialEvidence: true) != nil)
            for omitted in [1, 2] {
                let partial = required.enumerated().filter { $0.offset != omitted }.map(\.element)
                #expect(MarinaNarrationValidator.render(draft: draft(partial), evidence: evidence, requiresFinancialEvidence: true) == nil)
            }
            let schema = try schemaObject(MarinaNarrationSchema.make(act: .answer, evidence: evidence))
            #expect(allValues(for: "minItems", in: schema).contains { ($0 as? Int) == 3 })
        }
    }

    @Test func composedConnectivesCannotReplaceOrAddFinancialFacts() throws {
        let evidence = [MarinaNarrationEvidence(id: "q0f0", subject: "Dining", relation: "totals",
            value: "$500", scope: "October", isFocus: true)]
        func content(reference: String = "q0f0", extra: [String: Any] = [:]) throws -> GeneratedContent {
            var claim = extra
            claim["reference"] = reference
            let payload: [String: Any] = [
                "act": "answer", "introduction": "", "question": "",
                "claims": [claim]
            ]
            let json = try JSONSerialization.data(withJSONObject: payload)
            return try GeneratedContent(json: String(decoding: json, as: UTF8.self))
        }
        let plain = try MarinaNarrationSchema.draft(from: content())
        #expect(MarinaNarrationValidator.render(draft: plain, evidence: evidence, requiresFinancialEvidence: true) == "Dining totals $500 for October.")
        let connected = try MarinaNarrationSchema.draft(from: content(extra: ["prefix": "Also,"]))
        #expect(MarinaNarrationValidator.render(draft: connected, evidence: evidence, requiresFinancialEvidence: true) == "Also, Dining totals $500 for October.")
        #expect((try? MarinaNarrationSchema.draft(from: content(extra: ["parts": ["amount"]]))) == nil)
        #expect((try? MarinaNarrationSchema.draft(from: content(extra: ["suffix": "at."]))) == nil)
        let stale = try MarinaNarrationSchema.draft(from: content(reference: "q7f0"))
        #expect(MarinaNarrationValidator.render(draft: stale, evidence: evidence, requiresFinancialEvidence: true) == nil)
        for extra in [["prefix": "Dining totals $500."], ["prefix": "and $900"], ["prefix": "You are overspending."]] {
            let unsupported = try MarinaNarrationSchema.draft(from: content(extra: extra))
            #expect(MarinaNarrationValidator.render(draft: unsupported, evidence: evidence, requiresFinancialEvidence: true) == nil)
        }
    }

    @Test func onlyFrameworkDecodingFailuresQualifyForBoundedQueryRepair() {
        let failure = LanguageModelSession.GenerationError.decodingFailure(.init(debugDescription: "Invalid JSON"))
        #expect(MarinaConversationRuntime.isMalformedQueryOutput(failure))
        let unsupported = LanguageModelSession.GenerationError.unsupportedGuide(.init(debugDescription: "Unsupported pattern"))
        #expect(!MarinaConversationRuntime.isMalformedQueryOutput(unsupported))
        let refusal = LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "Guardrail"))
        #expect(!MarinaConversationRuntime.isMalformedQueryOutput(refusal))
        if #available(iOS 27.0, macCatalyst 27.0, *) {
            let parsing = GeneratedContent.ParsingError(rawContent: "{", debugDescription: "Incomplete JSON")
            #expect(MarinaConversationRuntime.isMalformedQueryOutput(parsing))
        }
    }

    #if DEBUG
    @Test func coldQuerySchemaIsIncludedInTheContextBudget() {
        let runtime = MarinaConversationRuntime()
        #expect(runtime.diagnosticAdditionalQueryPromptTokens > 0)
        #expect(runtime.diagnosticAdditionalQueryPromptTokens == runtime.diagnosticEstimatedQuerySchemaTokens)
    }
    #endif

    private func schemaObject(_ schema: GenerationSchema) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8))
    }

    private func resolvedSchema(_ object: [String: Any], root: [String: Any]) -> [String: Any]? {
        var current = object
        var visited = Set<String>()
        while let reference = current["$ref"] as? String {
            guard reference.hasPrefix("#/"), visited.insert(reference).inserted else { return nil }
            var target: Any = root
            for part in reference.dropFirst(2).split(separator: "/") {
                let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                guard let next = (target as? [String: Any])?[key] else { return nil }
                target = next
            }
            guard let resolved = target as? [String: Any] else { return nil }
            current = resolved
        }
        return current
    }

    private func schema(at path: [String], in root: [String: Any]) -> [String: Any]? {
        var current = root
        for key in path {
            guard let resolved = resolvedSchema(current, root: root),
                  let next = resolved[key] as? [String: Any] else { return nil }
            current = next
        }
        return resolvedSchema(current, root: root)
    }

    private func stringChoices(_ object: [String: Any], root: [String: Any], depth: Int = 0) -> Set<String>? {
        guard depth < 20, let resolved = resolvedSchema(object, root: root) else { return nil }
        if let values = resolved["enum"] as? [String] { return Set(values) }
        guard let alternatives = resolved["anyOf"] as? [[String: Any]], !alternatives.isEmpty else { return nil }
        var choices = Set<String>()
        for alternative in alternatives {
            // An unconstrained branch must fail the assertion, never be ignored.
            guard let values = stringChoices(alternative, root: root, depth: depth + 1) else { return nil }
            choices.formUnion(values)
        }
        return choices
    }

    private func allValues(for key: String, in object: Any) -> [Any] {
        if let dictionary = object as? [String: Any] {
            return dictionary.flatMap { entry in
                (entry.key == key ? [entry.value] : []) + allValues(for: key, in: entry.value)
            }
        }
        if let array = object as? [Any] { return array.flatMap { allValues(for: key, in: $0) } }
        return []
    }
}
#endif
