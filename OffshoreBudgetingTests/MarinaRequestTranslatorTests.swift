import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaRequestTranslatorTests {
    @Test func eachCapabilityBuildsOnlyItsApplicableComparisonAndDefinitionFields() throws {
        for capability in MarinaCapability.allCases {
            for references in [[], ["r1", "r2"]] {
                let schema = try MarinaRequestTranslator.patchSchema(capability: capability,
                    entityReferences: references, allowedBases: ["newQuestion", "active", "pending", "t1"])
                let root = try object(schema)
                let properties = try #require(root["properties"] as? [String: Any])
                #expect((root["required"] as? [String] ?? []).isEmpty)
                #expect((properties["comparisonDates"] != nil) == capability.isComparison)
                #expect((properties["comparisonTargets"] != nil) == capability.isComparison)
                #expect((properties["grouping"] != nil) == capability.requiresGroupingSelection)
                #expect((properties["availabilityFilter"] != nil) == (capability == .categoryAvailability))
                #expect(properties["operation"] == nil && properties["capability"] == nil && properties["base"] == nil)
                if [.cardSummary, .upcomingPresets, .nextPlannedExpense].contains(capability) {
                    #expect(properties["scope"] == nil && properties["measure"] == nil && properties["includeFuture"] == nil)
                }
            }
        }
    }

    @Test func targetSchemasAllowMultipleSelectionsOnlyForCategories() throws {
        let capabilities: [(MarinaCapability, Set<String>)] = [
            (.spendingComparison, ["card", "categories", "budget", "preset", "merchant", "periodBudget"]),
            (.incomeComparison, ["card", "budget", "incomeSource", "periodBudget"]),
            (.cardSummary, ["card", "budget", "periodBudget"]),
            (.categoryAvailability, ["budget", "categories", "periodBudget"]),
            (.accountBalances, ["account"])
        ]
        for (capability, expectedFields) in capabilities {
            let root = try object(MarinaRequestTranslator.patchSchema(capability: capability,
                entityReferences: ["r1", "r2"], allowedBases: ["active"]))
            let properties = try #require(root["properties"] as? [String: Any])
            for name in capability.isComparison ? ["targets", "comparisonTargets"] : ["targets"] {
                let array = try #require(properties[name] as? [String: Any])
                #expect(array["minItems"] as? Int == 0)
                let items = try #require(array["items"] as? [String: Any])
                var actualFields = Set<String>()
                for variant in try schemaLeaves(items, root: root) {
                    let variantProperties = try #require(variant["properties"] as? [String: Any])
                    let field = try #require(variantProperties["field"] as? [String: Any])
                    let fields = try schemaLeaves(field, root: root).flatMap { try #require($0["enum"] as? [String]) }
                    #expect(!fields.isEmpty)
                    for field in fields { #expect(actualFields.insert(field).inserted) }
                    let change = try #require(variantProperties["change"] as? [String: Any])
                    let changes = try schemaLeaves(change, root: root)
                    #expect(changes.contains { ($0["enum"] as? [String]) == ["keep"] })
                    #expect(changes.contains { ($0["properties"] as? [String: Any])?["clear"] != nil })
                    let sets = changes.compactMap { ($0["properties"] as? [String: Any])?["set"] as? [String: Any] }
                    #expect(sets.count == 1)
                    let values = try #require(sets.first)
                    #expect(values["minItems"] as? Int == 1)
                    for field in fields { #expect(values["maxItems"] as? Int == (field == "categories" ? 8 : 1)) }
                    let target = try #require(values["items"] as? [String: Any])
                    let targetProperties = try schemaLeaves(target, root: root).map { try #require($0["properties"] as? [String: Any]) }
                    #expect(targetProperties.contains { $0["name"] != nil })
                    let reference = try #require(targetProperties.compactMap { $0["reference"] as? [String: Any] }.first)
                    let references = try schemaLeaves(reference, root: root).flatMap { try #require($0["enum"] as? [String]) }
                    #expect(Set(references) == ["r1", "r2"])
                }
                #expect(actualFields == (name == "comparisonTargets" ? expectedFields.subtracting(["periodBudget"]) : expectedFields))
                #expect(array["maxItems"] as? Int == actualFields.count)
            }
        }
    }

    @Test func targetDecodingRejectsDuplicateSingleTargetsButPreservesCombinedCategories() throws {
        func decode(_ field: String, count: Int, capability: MarinaCapability, name: String = "targets") throws -> MarinaTurnPatch {
            let targets = (0..<count).map { ["reference": field == "categories" ? "r\($0 + 1)" : "r1"] }
            let body: [String: Any] = [name: [["field": field, "change": ["set": targets, "source": ["quote": "selected"]]]]]
            let data = try JSONSerialization.data(withJSONObject: body)
            let choice = MarinaRequestTranslator.Choice(goals: [capability.rawValue], base: "active", source: "selected")
            return try MarinaRequestTranslator.decodePatch(GeneratedContent(json: String(decoding: data, as: UTF8.self)),
                choice: choice, capability: capability, entityReferences: (1...9).map { "r\($0)" }, allowedBases: ["active"])
        }
        for (capability, fields) in [
            (MarinaCapability.expenses, ["card", "budget", "preset", "merchant", "periodBudget"]),
            (.income, ["incomeSource"]), (.accountBalances, ["account"])
        ] {
            for field in fields {
                #expect(throws: (any Error).self) { try decode(field, count: 2, capability: capability) }
                #expect(try decode(field, count: 1, capability: capability).targets.count == 1)
            }
        }
        for name in ["targets", "comparisonTargets"] {
            #expect(throws: (any Error).self) { try decode("card", count: 2, capability: .spendingComparison, name: name) }
            for count in [1, 8] {
                let patch = try decode("categories", count: count, capability: .spendingComparison, name: name)
                let changes = name == "targets" ? patch.targets : patch.comparisonTargets
                #expect(changes.first?.change == .set((1...count).map { .reference("r\($0)") }, .userText("selected")))
            }
            for count in [0, 9] {
                #expect(throws: (any Error).self) { try decode("categories", count: count, capability: .spendingComparison, name: name) }
            }
        }
    }

    @Test func selectionConstrainsGoalsAndOfferedBasesAndRejectsInvalidProvenance() throws {
        let schema = try MarinaRequestTranslator.selectionSchema(allowedBases: ["newQuestion", "t7"])
        let root = try object(schema)
        let properties = try #require(root["properties"] as? [String: Any])
        #expect(properties["requestedAnswer"] != nil && properties["source"] == nil)
        #expect(properties["goal"] != nil && properties["goals"] == nil && properties["hasAdditionalGoals"] != nil)
        #expect(properties["changedFields"] == nil)
        #expect(!schema.debugDescription.contains("\"rankedSpending\""))
        for leaf in ["categoryRanking", "cardRanking", "merchantRanking"] { #expect(schema.debugDescription.contains(leaf)) }
        let prompt = "Compare the category leaders."
        let good = try GeneratedContent(json: #"{"requestedAnswer":"Compare the category leaders for two periods.","goal":"leaderComparison","hasAdditionalGoals":false,"base":"t7"}"#)
        let decoded = try MarinaRequestTranslator.decodeChoice(good, prompt: prompt, allowedBases: ["newQuestion", "t7"])
        #expect(decoded.base == "t7")
        #expect(decoded.source == prompt)
        #expect(decoded.requestedAnswer == "Compare the category leaders for two periods.")
        for json in [
            #"{"goals":["leaderComparison"],"base":"t8","source":"Compare"}"#,
            #"{"goals":["leaderComparison"],"base":"t7","source":"Invented request"}"#,
            #"{"goals":["unknown"],"base":"t7","source":"Compare"}"#,
            #"{"goals":["income","income"],"base":"t7","source":"Compare"}"#,
            #"{"goals":[],"base":"t7","source":"Compare"}"#
        ] {
            #expect(throws: (any Error).self) {
                try MarinaRequestTranslator.decodeChoice(GeneratedContent(json: json), prompt: prompt, allowedBases: ["newQuestion", "t7"])
            }
        }
    }

    @Test func requestedAnswerIsNotTheCapabilitySourceAndLegacySourcesRemainChecked() throws {
        let prompt = "And the lowest?"
        let content = try GeneratedContent(json: #"{"requestedAnswer":"Find the smallest expense in the current card report.","goal":"smallestExpense","hasAdditionalGoals":false,"base":"active"}"#)
        let choice = try MarinaRequestTranslator.decodeChoice(content, prompt: prompt, allowedBases: ["active"])
        let patch = try MarinaRequestTranslator.decodePatch(GeneratedContent(json: "{}"), choice: choice,
            capability: .smallestExpense, entityReferences: [], allowedBases: ["active"])
        #expect(patch.capability == .set(.smallestExpense, .userText(prompt)))
        #expect(choice.source != choice.requestedAnswer)
        let legacyWithoutSource = try GeneratedContent(json: #"{"goals":["smallestExpense"],"base":"active"}"#)
        #expect(try MarinaRequestTranslator.decodeChoice(legacyWithoutSource, prompt: prompt, allowedBases: ["active"]).source == prompt)
        let legacyWithBadSource = try GeneratedContent(json: #"{"goals":["smallestExpense"],"base":"active","source":"Old message"}"#)
        #expect(throws: (any Error).self) {
            try MarinaRequestTranslator.decodeChoice(legacyWithBadSource, prompt: prompt, allowedBases: ["active"])
        }
    }

    @Test func offeredReferenceValuesStillRequireCurrentUserQuotesAsSources() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["expenses"], base: "active", source: "Use that card")
        let schema = try MarinaRequestTranslator.patchSchema(capability: .expenses, entityReferences: ["r1"],
            allowedBases: ["active"], changedFields: ["targets"])
        #expect(!schema.debugDescription.contains("ContextSource") && !schema.debugDescription.contains("SourceReference"))
        let valid = try GeneratedContent(json: #"{"targets":[{"field":"card","change":{"set":[{"reference":"r1"}],"source":{"quote":"that card"}}}]}"#)
        let patch = try MarinaRequestTranslator.decodePatch(valid, choice: choice, capability: .expenses,
            entityReferences: ["r1"], allowedBases: ["active"])
        #expect(patch.targets.first?.change == .set([.reference("r1")], .userText("that card")))
        for reference in ["r1", "active"] {
            let content = try GeneratedContent(json: "{\"targets\":[{\"field\":\"card\",\"change\":{\"set\":[{\"reference\":\"r1\"}],\"source\":{\"reference\":\"\(reference)\"}}}]}")
            #expect(throws: (any Error).self) {
                try MarinaRequestTranslator.decodePatch(content, choice: choice, capability: .expenses,
                    entityReferences: ["r1"], allowedBases: ["active"])
            }
        }
    }

    @Test func emptyPatchChangesOnlyCapabilityAndKeepsTheValidatedCardAndDates() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["smallestExpense"], base: "active", source: "lowest")
        let patch = try MarinaRequestTranslator.decodePatch(GeneratedContent(json: "{}"), choice: choice,
            capability: .smallestExpense, entityReferences: [], allowedBases: ["newQuestion", "active"])
        var previous = MarinaDataRequest(tool: .expenses)
        previous.operation = .transactions; previous.sort = .largest; previous.limit = 1
        previous.cardID = UUID().uuidString; previous.expenseMeasure = .spending
        previous.startDate = "2026-10-01"; previous.endDate = "2026-10-31"
        let context = MarinaRequestCompiler.Context(workspaceID: UUID(), prompt: "And the lowest?",
            now: Date(timeIntervalSince1970: 1_792_224_000), activeRequest: previous)
        let result = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(result.request.cardID == previous.cardID)
        #expect(result.request.startDate == previous.startDate && result.request.endDate == previous.endDate)
        #expect(result.request.sort == .smallest && result.request.limit == 1 && result.request.positiveOnly == true)
        #expect(result.request.expenseMeasure == .spending)
    }

    @Test func comparisonPatchAddsOnlyTheOtherMonthAndRetainsGrouping() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["leaderComparison"], base: "active", source: "compare")
        let content = try GeneratedContent(json: #"{"comparisonDates":{"set":{"month":6},"source":{"quote":"June"}}}"#)
        let patch = try MarinaRequestTranslator.decodePatch(content, choice: choice, capability: .leaderComparison,
            entityReferences: [], allowedBases: ["active"])
        var previous = MarinaDataRequest(tool: .expenses)
        previous.operation = .ranking; previous.grouping = .category
        previous.startDate = "2026-10-01"; previous.endDate = "2026-10-31"
        let context = MarinaRequestCompiler.Context(workspaceID: UUID(), prompt: "What about June? Can you compare?",
            now: Date(timeIntervalSince1970: 1_792_224_000), activeRequest: previous)
        let result = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(result.request.operation == .comparison && result.request.compareLeaders == true)
        #expect(result.request.grouping == .category)
        #expect(result.request.startDate == "2026-10-01" && result.request.endDate == "2026-10-31")
        #expect(result.request.comparisonStartDate == "2026-06-01" && result.request.comparisonEndDate == "2026-06-30")
    }

    @Test func targetsUseOnlyOfferedReferencesAndClearRemainsDistinctFromKeep() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["expenses"], base: "active", source: "all cards")
        let clear = try GeneratedContent(json: #"{"targets":[{"field":"card","change":{"clear":{"quote":"all cards"}}}]}"#)
        let patch = try MarinaRequestTranslator.decodePatch(clear, choice: choice, capability: .expenses,
            entityReferences: ["r1"], allowedBases: ["active"])
        #expect(patch.targets.first?.change == .clear(.userText("all cards")))
        for json in [
            #"{"targets":[{"field":"card","change":{"set":[{"reference":"r9"}],"source":{"quote":"all cards"}}}]}"#,
            #"{"targets":[{"field":"card","change":{"set":[{"reference":"r1"}],"source":{"reference":"t9"}}}]}"#,
            #"{"comparisonDates":{"set":"previousMonth","source":{"quote":"all cards"}}}"#,
            #"{"dates":{"set":{"start":"2026-06-01"},"source":{"quote":"all cards"}}}"#
        ] {
            #expect(throws: (any Error).self) {
                try MarinaRequestTranslator.decodePatch(GeneratedContent(json: json), choice: choice, capability: .expenses,
                    entityReferences: ["r1"], allowedBases: ["active"])
            }
        }
    }

    @Test func choiceDoesNotAcceptParameterSelectionAndRetainsIndependentGoalFlag() throws {
        let prompt = "Income and expenses."
        let compound = try GeneratedContent(json: #"{"goal":"income","hasAdditionalGoals":true,"base":"newQuestion","source":"Income"}"#)
        let choice = try MarinaRequestTranslator.decodeChoice(compound, prompt: prompt, allowedBases: ["newQuestion"])
        #expect(choice.goal == "income" && choice.goals == ["income"] && choice.hasAdditionalGoals)
        for json in [
            #"{"goal":"categoryRanking","hasAdditionalGoals":false,"base":"newQuestion","changedFields":["grouping"],"source":"expenses"}"#,
            #"{"goal":"income","hasAdditionalGoals":false,"base":"newQuestion","changedFields":["state","state"],"source":"Income"}"#,
            #"{"goal":"greeting","hasAdditionalGoals":false,"base":"newQuestion","changedFields":["dates"],"source":"Income"}"#,
            #"{"goal":"income","hasAdditionalGoals":false,"base":"newQuestion","changedFields":["invented"],"source":"Income"}"#
        ] {
            #expect(throws: (any Error).self) {
                try MarinaRequestTranslator.decodeChoice(GeneratedContent(json: json), prompt: prompt, allowedBases: ["newQuestion"])
            }
        }
    }

    @Test func diagnosticPrunedSchemaDoesNotSelectRuntimePatchFields() throws {
        let schema = try MarinaRequestTranslator.patchSchema(capability: .leaderComparison,
            entityReferences: ["r1"], allowedBases: ["active"], changedFields: ["comparisonDates"])
        let root = try object(schema)
        let properties = try #require(root["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["comparisonDates"])
        #expect(Set(root["required"] as? [String] ?? []) == ["comparisonDates"])
        #expect(!schema.debugDescription.contains("\"keep\""))
        let choice = MarinaRequestTranslator.Choice(goals: ["leaderComparison"], base: "active", source: "compare")
        let extra = try GeneratedContent(json: #"{"comparisonDates":{"set":{"month":6},"source":{"quote":"June"}},"targets":[]}"#)
        let decoded = try MarinaRequestTranslator.decodePatch(extra, choice: choice, capability: .leaderComparison,
            entityReferences: ["r1"], allowedBases: ["active"])
        #expect(decoded.comparisonDates == .set(.month(year: nil, month: 6), .userText("June")))
    }

    @Test func optionalPatchFieldsPreserveContextWithoutAFirstStageFieldList() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["expenses"], base: "active", source: "October")
        let schema = try MarinaRequestTranslator.patchSchema(capability: .expenses, entityReferences: [], allowedBases: ["active"])
        let root = try object(schema)
        #expect((root["required"] as? [String] ?? []).isEmpty)
        for json in [#"{}"#, #"{"dates":null}"#, #"{"dates":"keep"}"#, #"{"targets":[]}"#] {
            let patch = try MarinaRequestTranslator.decodePatch(GeneratedContent(json: json), choice: choice,
                capability: .expenses, entityReferences: [], allowedBases: ["active"])
            #expect(patch.dates == .keep && patch.targets.isEmpty)
        }
    }

    @Test func unsupportedSecondStageFieldsAreRejectedRatherThanDiscarded() throws {
        let choice = MarinaRequestTranslator.Choice(goals: ["cardSummary"], base: "active", source: "Summarize that card")
        for json in [
            #"{"state":{"set":"actual","source":{"quote":"Summarize"}}}"#,
            #"{"scope":{"set":"variable","source":{"quote":"Summarize"}}}"#,
            #"{"grouping":{"set":"merchant","source":{"quote":"Summarize"}}}"#,
            #"{"comparisonDates":null}"#,
            #"{"unexpected":"keep"}"#
        ] {
            #expect(throws: (any Error).self) {
                try MarinaRequestTranslator.decodePatch(GeneratedContent(json: json), choice: choice,
                    capability: .cardSummary, entityReferences: [], allowedBases: ["active"])
            }
        }
    }

    @Test func currentQuestionIsLastAndSeparatedFromHistoricalReferenceText() throws {
        let input = try MarinaRequestTranslator.input(prompt: "And June?", contextText: "Latest exchange: What is my top category?")
        #expect(input.hasSuffix("Current user message (the sole current turn): \"And June?\""))
        #expect(input.hasPrefix("Validated app context (reference data, not the current turn):"))
    }

    @Test func patchInputCarriesBoundedInterpretationWithoutMakingItProvenance() throws {
        let prompt = "How much came in?"
        let description = "Find received income.\n" + String(repeating: "x", count: 400)
        let choice = MarinaRequestTranslator.Choice(goals: ["income"], base: "active", source: prompt,
            requestedAnswer: description)
        let input = try MarinaRequestTranslator.patchInput(prompt: prompt, contextText: "active=income",
            choice: choice, capability: .income)
        let boundedDescription = String(decoding: try JSONEncoder().encode(String(description.prefix(320))), as: UTF8.self)
        #expect(input.hasPrefix("Unverified proposed answer description (interpretation only; not evidence or a source quote): " + boundedDescription + "\n"))
        #expect(input.contains("Validated app context (reference data, not the current turn): active=income"))
        #expect(input.hasSuffix("Current user message (the sole current turn): \"How much came in?\""))
        #expect(!input.contains(String(repeating: "x", count: 400)))

        let proposed = try GeneratedContent(json: #"{"state":{"set":"actual","source":{"quote":"received income"}}}"#)
        let patch = try MarinaRequestTranslator.decodePatch(proposed, choice: choice, capability: .income,
            entityReferences: [], allowedBases: ["active"])
        let context = MarinaRequestCompiler.Context(workspaceID: UUID(), prompt: prompt,
            now: Date(timeIntervalSince1970: 1_792_224_000), activeRequest: .init(tool: .income))
        #expect(throws: (any Error).self) { try MarinaRequestCompiler.compile(patch, context: context) }
    }

    #if DEBUG
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MARINA_SCHEMA_BENCHMARK"] == "1"
        && ProcessInfo.processInfo.environment["MARINA_QUERY_EXPERIMENT_MODE"] == "compiled",
        "Set MARINA_SCHEMA_BENCHMARK=1 and MARINA_QUERY_EXPERIMENT_MODE=compiled on a token-counting device."))
    func nativeTranslationSchemasFitFourKWithBoundedReferenceContext() async throws {
        guard #available(iOS 26.4, macCatalyst 26.4, macOS 26.4, *) else { throw BenchmarkError.unavailable }
        let model = SystemLanguageModel.default
        let bases = ["newQuestion", "active", "pending"] + (1...8).map { "t\($0)" }
        let references = (1...12).map { "r\($0)" }
        let context = "workspace=Personal; active=rankedSpending category October2026; pending=none; "
            + (1...8).map { "t\($0)=cardSummary card=r1 dates=2026-06-01..2026-06-30" }.joined(separator: ";")
        let question = "Compare this period's leading category to June 2026."
        let input = try MarinaRequestTranslator.input(prompt: question, contextText: context)
        let inputTokens = try await model.tokenCount(for: input)
        let choiceSession = LanguageModelSession(instructions: MarinaRequestTranslator.selectionInstructions)
        let choicePrefix = try await model.tokenCount(for: Array(choiceSession.transcript))
        let selection = try MarinaRequestTranslator.selectionSchema(allowedBases: bases)
        let selectionTokens = try await model.tokenCount(for: selection)
        let budget = MarinaContextBudget(capacity: 4096)
        #expect(budget.fits(choicePrefix + inputTokens + selectionTokens + 16))
        #expect(MarinaRequestTranslator.estimatedSchemaTokens(selection) >= selectionTokens)
        print("MarinaTranslationBenchmark stage=choice schema=\(selectionTokens) total=\(choicePrefix + inputTokens + selectionTokens + 16) tools=0")
        let patchSession = LanguageModelSession(instructions: MarinaRequestTranslator.patchInstructions)
        let patchPrefix = try await model.tokenCount(for: Array(patchSession.transcript))
        for capability in MarinaCapability.allCases {
            let full = try MarinaRequestTranslator.patchSchema(capability: capability, entityReferences: references, allowedBases: bases)
            let fullTokens = try await model.tokenCount(for: full)
            let changes = capability.isComparison ? ["comparisonDates"] : capability == .inventory ? ["recordKind"] : ["dates"]
            let schema = try MarinaRequestTranslator.patchSchema(capability: capability, entityReferences: references,
                allowedBases: bases, changedFields: changes)
            let tokens = try await model.tokenCount(for: schema)
            let choice = MarinaRequestTranslator.Choice(goals: [capability.rawValue], base: "active", source: question,
                requestedAnswer: String(repeating: "Requested result. ", count: 20))
            let patchInput = try MarinaRequestTranslator.patchInput(prompt: question, contextText: context,
                choice: choice, capability: capability)
            let patchInputTokens = try await model.tokenCount(for: patchInput)
            let total = patchPrefix + patchInputTokens + fullTokens + 16
            #expect(budget.fits(total), "Capability \(capability.rawValue) must leave the 4K output reserve intact.")
            #expect(tokens < fullTokens)
            #expect(MarinaRequestTranslator.estimatedSchemaTokens(full) >= fullTokens)
            #expect(MarinaRequestTranslator.estimatedSchemaTokens(schema) >= tokens)
            print("MarinaTranslationBenchmark stage=patch capability=\(capability.rawValue) schema=\(fullTokens) pruned_schema=\(tokens) diagnostic_fields=\(changes.joined(separator: ",")) total=\(total) tools=0")
        }
    }
    #endif

    private func object(_ schema: GenerationSchema) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
    }

    /// Foundation Models versions may inline schemas or keep local references.
    private func schemaLeaves(_ object: [String: Any], root: [String: Any], depth: Int = 0) throws -> [[String: Any]] {
        try #require(depth < 20)
        var current = object
        var visited = Set<String>()
        while let reference = current["$ref"] as? String {
            try #require(reference.hasPrefix("#/") && visited.insert(reference).inserted)
            var target: Any = root
            for part in reference.dropFirst(2).split(separator: "/") {
                let key = part.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
                target = try #require((target as? [String: Any])?[key])
            }
            current = try #require(target as? [String: Any])
        }
        if let alternatives = current["anyOf"] as? [[String: Any]] {
            return try alternatives.flatMap { try schemaLeaves($0, root: root, depth: depth + 1) }
        }
        return [current]
    }

    private enum BenchmarkError: Error { case unavailable }
}
#endif
