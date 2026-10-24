import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels

@MainActor
struct MarinaToolSchemaTests {
    #if DEBUG
    @Test func preTokenAPIStartupLeavesRoomForAQuestionOnFourKDevices() throws {
        let runtime = MarinaConversationRuntime()
        let instructions = runtime.diagnosticInstructions(workspace: Workspace(name: "Personal", hexColor: "#123456"),
            homeContext: nil, defaultBudgetingPeriod: .monthly, now: Date(timeIntervalSince1970: 1_792_224_000))
        let schemaBytes = try runtime.diagnosticTools().reduce(0) { try $0 + JSONEncoder().encode($1.parameters).count }
        let prefix = MarinaContextBudget.estimatedPrefixTokens(instructions: instructions, schemaBytes: schemaBytes)
        let prompt = MarinaContextBudget.estimatedTokens("How much did I spend using my Apple Card this month?")
        #expect(MarinaContextBudget(capacity: 4096).fits(prefix + prompt + 16))
    }
    #endif

    @Test func registeredToolsHaveDistinctGeneratedSchemaNames() throws {
        let schemas = [MarinaFindRecordsTool.Arguments.generationSchema,
                       MarinaExpensesTool.Arguments.generationSchema,
                       MarinaIncomeTool.Arguments.generationSchema,
                       MarinaBudgetTool.Arguments.generationSchema,
                       MarinaAccountsTool.Arguments.generationSchema]
        let titles = try schemas.map { schema in
            let object = try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
            return try #require(object["title"] as? String)
        }
        #expect(Set(titles).count == schemas.count)
        #expect(!titles.contains("Arguments"))
    }

    @Test func plainEnumsUseCompactStringSchemasAndStillRoundTrip() throws {
        let schemas = [MarinaExpenseScope.generationSchema, MarinaIncomeState.generationSchema,
                       MarinaDataGrouping.generationSchema, MarinaDataSort.generationSchema,
                       MarinaExpenseMeasure.generationSchema, MarinaPeriodUnit.generationSchema,
                       MarinaAccountScope.generationSchema, MarinaDateSelectionKind.generationSchema]
        for schema in schemas {
            let root = try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
            #expect(root["type"] as? String == "string")
            #expect((root["enum"] as? [String])?.isEmpty == false)
            #expect(root["anyOf"] == nil)
        }
        let content = MarinaExpenseMeasure.ledger.generatedContent
        #expect(try MarinaExpenseMeasure(content).rawValue == "ledger")
        #expect(content.jsonString == "\"ledger\"")
    }

    @Test func compactSelectionsRoundTripWithoutDatabaseIdentifiers() throws {
        for selection in [MarinaSelection.workspace, .previous, .references(["r1", "r2"])] {
            #expect(try MarinaSelection(selection.generatedContent).generatedContent == selection.generatedContent)
        }
        let content = MarinaSelection.references(["r1", "r2"]).generatedContent
        #expect(content.jsonString == "\"r1,r2\"")
        #expect(MarinaSelection.references(["r1"]).generatedContent.jsonString == "\"r1\"")
        for malformed in [
            GeneratedContent("unknown"), GeneratedContent(""), GeneratedContent("r0"), GeneratedContent("r01"),
            GeneratedContent("r1,r1"), GeneratedContent("r1,"), GeneratedContent("r1, r2"), GeneratedContent("r1,workspace"),
            GeneratedContent("r١"), GeneratedContent("R1"), GeneratedContent("Apple Card"),
            GeneratedContent(properties: ["refs": ["r1"]]),
            GeneratedContent(properties: ["type": "expenseWorkspace"])
        ] {
            do {
                _ = try MarinaSelection(malformed)
                Issue.record("A selection string must contain distinct positive reference numbers or an explicit selection mode.")
            } catch { }
        }
    }

    @Test func onlyKnownArgumentDecodeErrorsProvideRepairFeedback() throws {
        let tool = MarinaExpensesTool(bridge: MarinaToolBridge())
        for content in [GeneratedContent(""), GeneratedContent("r1, r2"), GeneratedContent("Apple Card"),
                        GeneratedContent(properties: ["refs": ["r1"]])] {
            do {
                _ = try MarinaSelection(content)
                Issue.record("Malformed selection unexpectedly decoded.")
            } catch {
                let feedback = try #require(MarinaToolBridge.argumentErrorFeedback(error))
                #expect(feedback.contains("workspace") && feedback.contains("unnamed or all-records"))
                #expect(feedback.contains("previous") && feedback.contains("relevant follow-up"))
                #expect(feedback.contains("exact references returned by findRecords") && feedback.contains("Never invent references"))
                #expect(!feedback.contains("r1"))
                let wrapped = LanguageModelSession.ToolCallError(tool: tool, underlyingError: error)
                #expect(MarinaToolBridge.argumentErrorFeedback(wrapped) == feedback)
            }
        }
        let unrelated: [any Error] = [CancellationError(), CocoaError(.fileReadNoSuchFile), MarinaClarificationRequired()]
        for error in unrelated {
            #expect(MarinaToolBridge.argumentErrorFeedback(error) == nil)
            let wrapped = LanguageModelSession.ToolCallError(tool: tool, underlyingError: error)
            #expect(MarinaToolBridge.argumentErrorFeedback(wrapped) == nil)
        }
    }

    @Test func incomeAndBudgetOperationsGenerateExclusiveFields() throws {
        #expect(MarinaIncomeOperation.summary.generatedContent.jsonString == "\"summary\"")
        #expect(MarinaIncomeOperation.progress.generatedContent.jsonString == "\"progress\"")
        #expect(MarinaBudgetOperation.overview.generatedContent.jsonString == "\"overview\"")
        #expect(MarinaBudgetOperation.pace.generatedContent.jsonString == "\"pace\"")
        let operations: [(MarinaIncomeOperation, Set<String>)] = [
            (.transactions(order: .newest, offset: 0), ["order", "offset"]),
            (.groups(by: .source, offset: 0), ["by", "offset"]),
            (.periodTotals(unit: .month, offset: 0), ["unit", "offset"]),
            (.compareIncome(selection: .references(["r1", "r2"]), dates: .previousMonth), ["compareIncome"]),
            (.compareIncome(selection: .workspace, dates: .previousQuery), ["compareIncome"])
        ]
        for (operation, expectedKeys) in operations {
            let content = operation.generatedContent
            let object = try #require(JSONSerialization.jsonObject(with: Data(content.jsonString.utf8)) as? [String: Any])
            #expect(Set(object.keys) == expectedKeys)
            if expectedKeys == ["compareIncome"] {
                let payload = try #require(object["compareIncome"] as? [String: Any])
                #expect(Set(payload.keys) == ["selection", "dates"])
            }
            let decoded = try MarinaIncomeOperation(content)
            #expect(decoded.generatedContent == content)
        }
        let budget = MarinaBudgetOperation.savingsTrend(unit: .week, offset: 5)
        let object = try #require(JSONSerialization.jsonObject(with: Data(budget.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(Set(object.keys) == ["unit", "offset"])
        #expect(try MarinaBudgetOperation(budget.generatedContent).generatedContent == budget.generatedContent)
        for malformed in [
            GeneratedContent("unknown"),
            GeneratedContent(properties: ["by": "source"]),
            GeneratedContent(properties: ["unit": "month", "offset": 0, "by": "source"]),
            GeneratedContent(properties: ["dates": "currentMonth", "order": "newest"]),
            GeneratedContent(properties: ["source": "Salary"]),
            GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth"]),
            GeneratedContent(properties: ["compareIncome": GeneratedContent(properties: ["selection": "workspace"])]),
            GeneratedContent(properties: ["compareIncome": GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth", "offset": 0])]),
            GeneratedContent(properties: ["compareIncome": GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth"]), "offset": 0])
        ] {
            do {
                _ = try MarinaIncomeOperation(malformed)
                Issue.record("Income operations must have exactly one complete payload shape.")
            } catch { }
        }
        for malformed in [
            GeneratedContent("unknown"),
            GeneratedContent(properties: ["offset": 0]),
            GeneratedContent(properties: ["unit": "week", "offset": 0, "by": "source"])
        ] {
            do {
                _ = try MarinaBudgetOperation(malformed)
                Issue.record("Budget operations must be a known summary or exclusive trend payload.")
            } catch { }
        }
    }

    @Test func expenseComparisonsRequireTheOtherSelectionAndPeriod() throws {
        let simpleOperations: [(MarinaExpenseOperation, String)] = [
            (.summary, "summary"), (.transactions, "transactions"), (.upcomingPresets, "upcomingPresets"),
            (.largestPurchase, "largestPurchase"), (.categoryTotals, "categoryTotals"), (.cardTotals, "cardTotals"),
            (.merchantTotals, "merchantTotals"), (.categoryShares, "categoryShares"), (.cardShares, "cardShares"),
            (.merchantShares, "merchantShares"), (.periodTotals, "periodTotals")
        ]
        for (operation, value) in simpleOperations {
            #expect(operation.generatedContent == value.generatedContent)
            #expect(try MarinaExpenseOperation(operation.generatedContent).generatedContent == operation.generatedContent)
        }
        for operation in [MarinaExpenseOperation.compare(selection: .references(["r1", "r2"]), dates: .previousMonth),
                          .compare(selection: .workspace, dates: .dates(start: "2026-09-01", end: "2026-09-30")),
                          .compare(selection: .previous, dates: .previousQuery)] {
            let content = operation.generatedContent
            let object = try #require(JSONSerialization.jsonObject(with: Data(content.jsonString.utf8)) as? [String: Any])
            #expect(Set(object.keys) == ["compare"])
            let payload = try #require(object["compare"] as? [String: Any])
            #expect(Set(payload.keys) == ["selection", "dates"])
            #expect(try MarinaExpenseOperation(content).generatedContent == content)
            let arguments = MarinaExpensesTool.Arguments(selection: .workspace, dates: .currentMonth, operation: operation)
            let argumentJSON = try #require(JSONSerialization.jsonObject(with: Data(arguments.generatedContent.jsonString.utf8)) as? [String: Any])
            #expect(argumentJSON["operation"] as? String == "compare")
            let comparison = try #require(argumentJSON["comparison"] as? [String: Any])
            #expect(Set(comparison.keys) == ["selection", "dates"])
            #expect(try MarinaExpensesTool.Arguments(arguments.generatedContent).validatedOperation().generatedContent == content)
        }
        for malformed in [
            GeneratedContent("compare"), GeneratedContent("unknown"),
            GeneratedContent(properties: ["selection": "workspace"]),
            GeneratedContent(properties: ["dates": "previousMonth"]),
            GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth", "offset": 0]),
            GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth"]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["selection": "workspace"])]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["dates": "previousMonth"])]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["selection": "r1,r1", "dates": "previousMonth"])]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["selection": "workspace", "dates": "unknown-period"])]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth", "offset": 0])]),
            GeneratedContent(properties: ["compare": GeneratedContent(properties: ["selection": "workspace", "dates": "previousMonth"]), "offset": 0])
        ] {
            do {
                _ = try MarinaExpenseOperation(malformed)
                Issue.record("An expense comparison must require exactly one valid selection and date choice.")
            } catch { }
        }
    }

    @Test func flatComparisonPayloadsAreRequiredIfAndOnlyIfComparisonIsChosen() throws {
        let incomeOperations: [MarinaIncomeOperation] = [
            .summary, .progress, .transactions(order: .newest, offset: 0), .groups(by: .source, offset: 5),
            .periodTotals(unit: .month, offset: 0), .compareIncome(selection: .workspace, dates: .previousMonth)
        ]
        for operation in incomeOperations {
            let arguments = MarinaIncomeTool.Arguments(selection: .workspace, dates: .currentMonth,
                state: .actual, operation: operation)
            let decoded = try MarinaIncomeTool.Arguments(arguments.generatedContent)
            #expect(try decoded.validatedOperation().generatedContent == operation.generatedContent)
            let object = try #require(JSONSerialization.jsonObject(with: Data(arguments.generatedContent.jsonString.utf8)) as? [String: Any])
            if case .compareIncome = operation {
                #expect(object["operation"] as? String == "compareIncome")
                let comparison = try #require(object["comparison"] as? [String: Any])
                #expect(Set(comparison.keys) == ["selection", "dates"])
            } else { #expect(decoded.comparison == nil) }
        }
        for json in [
            #"{"selection":"workspace","dates":"currentMonth","operation":"compare"}"#,
            #"{"selection":"workspace","dates":"currentMonth","operation":"summary","comparison":{"selection":"workspace","dates":"previousMonth"}}"#
        ] {
            let arguments = try MarinaExpensesTool.Arguments(GeneratedContent(json: json))
            do {
                _ = try arguments.validatedOperation()
                Issue.record("A comparison payload must be present exactly when compare is selected.")
            } catch { #expect(MarinaToolBridge.argumentErrorFeedback(error) != nil) }
        }
        for json in [
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"compareIncome"}"#,
            #"{"selection":"workspace","dates":"currentMonth","state":"actual","operation":"summary","comparison":{"selection":"workspace","dates":"previousMonth"}}"#
        ] {
            let arguments = try MarinaIncomeTool.Arguments(GeneratedContent(json: json))
            do {
                _ = try arguments.validatedOperation()
                Issue.record("A comparison payload must be present exactly when compareIncome is selected.")
            } catch { #expect(MarinaToolBridge.argumentErrorFeedback(error) != nil) }
        }
        for json in [
            #"{"selection":"workspace","dates":"currentMonth","operation":"compare","comparison":{"selection":"workspace"}}"#,
            #"{"selection":"workspace","dates":"currentMonth","operation":"compare","comparison":{"dates":"previousMonth"}}"#,
            #"{"selection":"workspace","dates":"currentMonth","operation":{"compare":{"selection":"workspace","dates":"previousMonth"}}}"#
        ] {
            do {
                _ = try MarinaExpensesTool.Arguments(GeneratedContent(json: json))
                Issue.record("Flat comparisons require a complete typed payload and string operation.")
            } catch { }
        }
    }

    @Test func financialSchemasUseSharedReferencesInsteadOfRawIDs() throws {
        let schemas = [MarinaExpensesTool.Arguments.generationSchema,
                       MarinaIncomeTool.Arguments.generationSchema,
                       MarinaBudgetTool.Arguments.generationSchema,
                       MarinaAccountsTool.Arguments.generationSchema]
        for schema in schemas {
            let text = schema.debugDescription
            #expect(text.contains("selection"))
            #expect(!text.contains("cardID") && !text.contains("accountID") && !text.contains("budgetID"))
            #expect(!text.contains("expenseMatching") && !text.contains("expenseCard"))
        }
        #expect(MarinaSelection.workspace.generatedContent.jsonString == "\"workspace\"")
        #expect(MarinaSelection.previous.generatedContent.jsonString == "\"previous\"")
    }

    @Test func dateSelectionSeparatesCalendarPeriodsFromExplicitRanges() throws {
        #expect(MarinaDateSelection.previousQuery.generatedContent.jsonString == "\"previousQuery\"")
        #expect(try MarinaDateSelection(MarinaDateSelection.previousQuery.generatedContent).generatedContent == MarinaDateSelection.previousQuery.generatedContent)
        let calendar = MarinaDateSelection.currentMonth
        #expect(calendar.generatedContent.jsonString == "\"currentMonth\"")
        let parsedCalendar = try MarinaDateSelection(calendar.generatedContent)
        guard case .calendar(let period) = parsedCalendar else {
            Issue.record("A calendar string must decode to a typed calendar period.")
            return
        }
        #expect(period == .currentMonth)
        let range = MarinaDateSelection.dates(start: "2026-10-01", end: "2026-10-31")
        let rangeJSON = try #require(JSONSerialization.jsonObject(with: Data(range.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(rangeJSON.count == 2)
        #expect(rangeJSON["start"] as? String == "2026-10-01")
        #expect(rangeJSON["end"] as? String == "2026-10-31")
        for malformed in [
            GeneratedContent("unknown-period"),
            GeneratedContent(properties: ["start": "2026-10-01"]),
            GeneratedContent(properties: ["start": "2026-10-01", "end": "2026-10-31", "period": "currentMonth"]),
            GeneratedContent(properties: ["start": "", "end": "2026-10-31"])
        ] {
            do {
                _ = try MarinaDateSelection(malformed)
                Issue.record("A date selection must be a known calendar period or complete, exclusive range.")
            } catch { }
        }
    }

    @Test func recordLookupPreservesExclusiveResolutionAndInventoryShapes() throws {
        let resolution = MarinaRecordLookup.resolveName(name: "Apple Card")
        let resolutionJSON = try #require(JSONSerialization.jsonObject(with: Data(resolution.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(resolutionJSON["type"] as? String == "resolveName")
        #expect(resolutionJSON["name"] as? String == "Apple Card")
        #expect(resolutionJSON["kind"] == nil || resolutionJSON["kind"] is NSNull)
        #expect(resolutionJSON["offset"] == nil)
        let qualified = MarinaRecordLookup.resolveName(name: "Apple", kind: .merchant)
        let qualifiedJSON = try #require(JSONSerialization.jsonObject(with: Data(qualified.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(qualifiedJSON["kind"] as? String == "merchant")
        #expect(try MarinaRecordLookup(qualified.generatedContent).generatedContent == qualified.generatedContent)
        let inventory = MarinaRecordLookup.inventory(kind: .card, offset: 5)
        let inventoryJSON = try #require(JSONSerialization.jsonObject(with: Data(inventory.generatedContent.jsonString.utf8)) as? [String: Any])
        #expect(inventoryJSON["type"] as? String == "inventory")
        #expect(inventoryJSON["kind"] as? String == "card")
        #expect(inventoryJSON["offset"] as? Int == 5)
        #expect(inventoryJSON["name"] == nil)
        do {
            _ = try MarinaRecordLookup(GeneratedContent(properties: ["type": "resolveName"]))
            Issue.record("Name resolution must require a name in its generated shape.")
        } catch { }
    }

    @Test func sharedSchemaDefinitionNamesNeverHaveDifferentShapes() throws {
        let schemas = [MarinaFindRecordsTool.Arguments.generationSchema,
                       MarinaExpensesTool.Arguments.generationSchema,
                       MarinaIncomeTool.Arguments.generationSchema,
                       MarinaBudgetTool.Arguments.generationSchema,
                       MarinaAccountsTool.Arguments.generationSchema]
        var definitions: [String: Data] = [:]
        for schema in schemas {
            let root = try #require(JSONSerialization.jsonObject(with: Data(schema.debugDescription.utf8)) as? [String: Any])
            for (name, definition) in root["$defs"] as? [String: Any] ?? [:] {
                let encoded = try JSONSerialization.data(withJSONObject: definition, options: [.sortedKeys])
                if let existing = definitions[name] {
                    #expect(existing == encoded, "Generated definition \(name) has incompatible shapes across registered tools.")
                } else { definitions[name] = encoded }
            }
        }
    }
}
#endif
