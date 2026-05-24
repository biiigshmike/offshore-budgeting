//
//  MarinaModelsTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaModelsTests {

    @Test func marinaTurnOutcomeEvaluator_executableQueryOverridesRecovery() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: true,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: true
        )

        #expect(outcome == .answer)
    }

    @Test func marinaTurnOutcomeEvaluator_actionableClarificationWithoutExecutableQuery_isClarification() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: true,
            clarificationIsActionable: true,
            shouldRecover: false
        )

        #expect(outcome == .clarification)
    }

    @Test func marinaTurnOutcomeEvaluator_noExecutableAndNonActionableClarification_isUnresolved() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: false
        )

        #expect(outcome == .unresolved)
    }

    @Test func marinaTurnOutcomeEvaluator_lowConfidencePath_isRecovery() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: true
        )

        #expect(outcome == .recovery)
    }









    @Test func executedQueryAnswerNormalizer_emptySpendQuery_becomesMetricCard() throws {
        let normalizer = MarinaExecutedQueryAnswerNormalizer()
        let query = HomeQuery(
            intent: .spendThisMonth,
            dateRange: weekRange(2026, 4, 6)
        )
        let raw = HomeAnswer(
            queryID: query.id,
            kind: .message,
            title: "Spend This Month",
            subtitle: "No spending in this range yet.",
            primaryValue: nil,
            rows: []
        )

        let normalized = normalizer.normalize(raw, for: query)

        #expect(normalized.kind == .metric)
        #expect(normalized.primaryValue == CurrencyFormatter.string(from: 0))
        #expect(normalized.rows.count == 1)
        #expect(normalized.rows.first?.title == "Total")
        #expect(normalized.rows.first?.value == CurrencyFormatter.string(from: 0))
        #expect(normalized.subtitle?.contains("2026") == true)
    }

    @Test func executedQueryAnswerNormalizer_emptySpendQueryExplicitRange_becomesMetricCard() throws {
        let normalizer = MarinaExecutedQueryAnswerNormalizer()
        let query = HomeQuery(
            intent: .spendThisMonth,
            dateRange: HomeQueryDateRange(
                startDate: date(2026, 4, 1, 0, 0, 0),
                endDate: date(2026, 4, 7, 0, 0, 0)
            )
        )
        let raw = HomeAnswer(
            queryID: query.id,
            kind: .message,
            title: "Spend This Month",
            subtitle: "No spending in this range yet.",
            primaryValue: nil,
            rows: []
        )

        let normalized = normalizer.normalize(raw, for: query)

        #expect(normalized.kind == .metric)
        #expect(normalized.primaryValue == CurrencyFormatter.string(from: 0))
        #expect(normalized.rows.count == 1)
        #expect(normalized.rows.first?.title == "Total")
        #expect(normalized.rows.first?.value == CurrencyFormatter.string(from: 0))
        #expect(normalized.subtitle?.contains("Apr") == true || normalized.subtitle?.contains("2026") == true)
    }

    @Test func cardSummaryPresentationModel_usesHomeCardMetrics() throws {
        let card = Card(
            name: "Apple Card",
            theme: CardThemeOption.ruby.rawValue,
            effect: CardEffectOption.plastic.rawValue
        )
        let planned = PlannedExpense(
            title: "Phone",
            plannedAmount: 579.45,
            expenseDate: date(2026, 5, 5),
            card: card
        )
        let futurePlanned = PlannedExpense(
            title: "Future",
            plannedAmount: 500,
            expenseDate: date(2026, 7, 1),
            card: card
        )
        let variable = VariableExpense(
            descriptionText: "Groceries",
            amount: 909.06,
            transactionDate: date(2026, 5, 10),
            card: card
        )
        let otherPeriodVariable = VariableExpense(
            descriptionText: "April",
            amount: 44,
            transactionDate: date(2026, 4, 30),
            card: card
        )
        card.plannedExpenses = [planned, futurePlanned]
        card.variableExpenses = [variable, otherPeriodVariable]

        let summary = CardSummaryPresentationModel.make(
            for: card,
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false
        )

        #expect(summary.title == "Apple Card")
        #expect(summary.themeRaw == CardThemeOption.ruby.rawValue)
        #expect(summary.effectRaw == CardEffectOption.plastic.rawValue)
        #expect(abs(summary.plannedTotal - 579.45) < 0.001)
        #expect(abs(summary.variableTotal - 909.06) < 0.001)
        #expect(abs(summary.total - 1_488.51) < 0.001)
    }

    @Test func cardSummaryAttachmentBuilder_attachesSummaryForSingleCardLookup() throws {
        let card = Card(
            name: "Apple Card",
            theme: CardThemeOption.ruby.rawValue,
            effect: CardEffectOption.plastic.rawValue
        )
        let planned = PlannedExpense(
            title: "Phone",
            plannedAmount: 579.45,
            expenseDate: date(2026, 5, 5),
            card: card
        )
        let variable = VariableExpense(
            descriptionText: "Groceries",
            amount: 909.06,
            transactionDate: date(2026, 5, 10),
            card: card
        )
        card.plannedExpenses = [planned]
        card.variableExpenses = [variable]

        let lookupAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: "show Apple Card",
            title: "I found Apple Card.",
            subtitle: "Card",
            rows: [
                HomeAnswerRow(title: "Type", value: "Card"),
                HomeAnswerRow(title: "Theme", value: CardThemeOption.ruby.rawValue),
                HomeAnswerRow(title: "Matched", value: "Apple Card")
            ]
        )

        let decorated = MarinaCardSummaryAttachmentBuilder().attachingCardSummaryIfNeeded(
            to: lookupAnswer,
            cards: [card],
            dateRange: HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31)),
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false
        )

        guard case let .cardSummary(summary)? = decorated.attachment else {
            Issue.record("Expected card summary attachment.")
            return
        }

        #expect(summary.title == "Apple Card")
        #expect(abs(summary.total - 1_488.51) < 0.001)
        #expect(decorated.subtitle?.contains("Total spending is currently") == true)
        #expect(decorated.rows.prefix(4).map(\.title) == ["Period", "Total", "Planned", "Variable"])
        #expect(decorated.rows.contains { $0.title == "Type" && $0.value == "Card" })
    }

    @Test func visualAttachmentBuilder_keepsCardSummaryForCardEntityMetadata() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(
            name: "Apple Card",
            theme: CardThemeOption.ruby.rawValue,
            effect: CardEffectOption.plastic.rawValue,
            workspace: workspace
        )
        let variable = VariableExpense(
            descriptionText: "Groceries",
            amount: 50,
            transactionDate: date(2026, 5, 10),
            workspace: workspace,
            card: card
        )
        card.variableExpenses = [variable]

        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Apple Card.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Card", sourceID: card.id, objectType: .card)
            ]
        )

        let decorated = visualAttachmentAnswer(
            answer,
            workspace: workspace,
            cards: [card],
            variableExpenses: [variable]
        )

        guard case let .cardSummary(summary)? = decorated.attachment else {
            Issue.record("Expected card summary attachment.")
            return
        }

        #expect(summary.cardID == card.id)
        #expect(abs(summary.variableTotal - 50) < 0.001)
    }

    @Test func visualAttachmentBuilder_attachesEntitySummariesForSupportedLookups() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let category = Category(name: "Groceries", hexColor: "#10B981", workspace: workspace)
        let card = Card(name: "Debit Card", workspace: workspace)
        let preset = Preset(
            title: "Rent",
            plannedAmount: 1_500,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        let variable = VariableExpense(
            descriptionText: "Market",
            amount: 42,
            transactionDate: date(2026, 5, 2),
            workspace: workspace,
            card: card,
            category: category
        )
        let planned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_500,
            expenseDate: date(2026, 5, 1),
            workspace: workspace,
            card: card,
            category: category
        )

        let categoryAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Groceries.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Category", sourceID: category.id, objectType: .category)
            ]
        )
        let presetAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Rent.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Preset", sourceID: preset.id, objectType: .preset)
            ]
        )
        let workspaceAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Personal.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Workspace", sourceID: workspace.id, objectType: .workspace)
            ]
        )

        let categoryDecorated = visualAttachmentAnswer(
            categoryAnswer,
            workspace: workspace,
            cards: [card],
            categories: [category],
            presets: [preset],
            variableExpenses: [variable],
            plannedExpenses: [planned]
        )
        let presetDecorated = visualAttachmentAnswer(
            presetAnswer,
            workspace: workspace,
            cards: [card],
            categories: [category],
            presets: [preset]
        )
        let workspaceDecorated = visualAttachmentAnswer(
            workspaceAnswer,
            workspace: workspace,
            cards: [card],
            categories: [category],
            presets: [preset]
        )

        guard case let .entitySummary(categorySummary)? = categoryDecorated.attachment,
              case let .entitySummary(presetSummary)? = presetDecorated.attachment,
              case let .entitySummary(workspaceSummary)? = workspaceDecorated.attachment else {
            Issue.record("Expected entity summary attachments.")
            return
        }

        #expect(categorySummary.objectType == .category)
        #expect(categorySummary.title == "Groceries")
        #expect(categorySummary.rows.contains { $0.title == "Variable rows" && $0.value == "1" })
        #expect(presetSummary.objectType == .preset)
        #expect(presetSummary.primaryValue == CurrencyFormatter.string(from: 1_500))
        #expect(workspaceSummary.objectType == .workspace)
        #expect(workspaceSummary.rows.contains { $0.title == "Cards" && $0.value == "1" })
    }

    @Test func visualAttachmentBuilder_attachesAccountAndLedgerSummaries() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let reconciliation = AllocationAccount(
            name: "Roommate",
            hexColor: "#6366F1",
            workspace: workspace
        )
        let settlement = AllocationSettlement(
            date: date(2026, 5, 3),
            note: "Paid back",
            amount: -25,
            workspace: workspace,
            account: reconciliation
        )
        reconciliation.settlements = [settlement]
        let savings = SavingsAccount(
            name: "Emergency Fund",
            total: 1_200,
            workspace: workspace
        )
        let entry = SavingsLedgerEntry(
            date: date(2026, 5, 4),
            amount: 25,
            note: "Manual save",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savings
        )
        savings.entries = [entry]

        let reconciliationAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Roommate.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Reconciliation account", sourceID: reconciliation.id, objectType: .reconciliationAccount)
            ]
        )
        let savingsAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Emergency Fund.",
            rows: [
                HomeAnswerRow(title: "Type", value: "Savings account", sourceID: savings.id, objectType: .savingsAccount)
            ]
        )
        let reconciliationRowsAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Roommate reconciliation rows",
            rows: [
                HomeAnswerRow(title: "Paid back", value: "-$25.00", sourceID: settlement.id, objectType: .reconciliationItem, amount: -25, date: settlement.date)
            ]
        )
        let savingsRowsAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Savings activity",
            rows: [
                HomeAnswerRow(title: "Manual save", value: "$25.00", sourceID: entry.id, objectType: .savingsLedgerEntry, amount: 25, date: entry.date)
            ]
        )

        let reconciliationDecorated = visualAttachmentAnswer(
            reconciliationAnswer,
            workspace: workspace,
            allocationAccounts: [reconciliation]
        )
        let savingsDecorated = visualAttachmentAnswer(
            savingsAnswer,
            workspace: workspace,
            savingsAccounts: [savings],
            savingsEntries: [entry]
        )
        let reconciliationRowsDecorated = visualAttachmentAnswer(
            reconciliationRowsAnswer,
            workspace: workspace,
            allocationAccounts: [reconciliation]
        )
        let savingsRowsDecorated = visualAttachmentAnswer(
            savingsRowsAnswer,
            workspace: workspace,
            savingsAccounts: [savings],
            savingsEntries: [entry]
        )

        guard case let .entitySummary(reconciliationSummary)? = reconciliationDecorated.attachment,
              case let .entitySummary(savingsSummary)? = savingsDecorated.attachment,
              case let .rowList(reconciliationRows)? = reconciliationRowsDecorated.attachment,
              case let .rowList(savingsRows)? = savingsRowsDecorated.attachment else {
            Issue.record("Expected account summaries and ledger row lists.")
            return
        }

        #expect(reconciliationSummary.primaryValue == CurrencyFormatter.string(from: -25))
        #expect(savingsSummary.primaryValue == CurrencyFormatter.string(from: 1_200))
        #expect(reconciliationRows.family == .reconciliation)
        #expect(savingsRows.family == .savings)
    }

    @Test func visualAttachmentBuilder_attachesExpenseRowListAndLeavesMixedRowsUntouched() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)
        let category = Category(name: "Groceries", hexColor: "#10B981", workspace: workspace)
        let variable = VariableExpense(
            descriptionText: "Market",
            amount: 42,
            transactionDate: date(2026, 5, 2),
            workspace: workspace,
            card: card,
            category: category
        )
        let planned = PlannedExpense(
            title: "Internet",
            plannedAmount: 80,
            expenseDate: date(2026, 5, 19),
            workspace: workspace,
            card: card,
            category: category
        )
        let expenseRows = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Apple Card expenses",
            rows: [
                HomeAnswerRow(title: "Market", value: "$42.00", sourceID: variable.id, objectType: .variableExpense, amount: 42, date: variable.transactionDate),
                HomeAnswerRow(title: "Internet", value: "$80.00", sourceID: planned.id, objectType: .plannedExpense, amount: 80, date: planned.expenseDate)
            ]
        )
        let mixedRows = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Mixed results",
            rows: [
                HomeAnswerRow(title: "Market", value: "$42.00", sourceID: variable.id, objectType: .variableExpense, amount: 42, date: variable.transactionDate),
                HomeAnswerRow(title: "Groceries", value: "Category", sourceID: category.id, objectType: .category)
            ]
        )

        let decorated = visualAttachmentAnswer(
            expenseRows,
            workspace: workspace,
            variableExpenses: [variable],
            plannedExpenses: [planned]
        )
        let mixedDecorated = visualAttachmentAnswer(
            mixedRows,
            workspace: workspace,
            categories: [category],
            variableExpenses: [variable]
        )

        guard case let .rowList(rowList)? = decorated.attachment else {
            Issue.record("Expected expense row list attachment.")
            return
        }

        #expect(rowList.family == .expenses)
        #expect(rowList.rows.map(\.objectType) == [.variableExpense, .plannedExpense])
        #expect(rowList.hidesSourceRows)
        guard case let .breakdownList(mixedBreakdown)? = mixedDecorated.attachment else {
            Issue.record("Expected mixed rows to get polished breakdown fallback.")
            return
        }
        #expect(mixedBreakdown.rows.map(\.title) == ["Market", "Groceries"])
    }

    @Test func visualAttachmentBuilder_polishesRecentPurchasesFromHomeQueryRows() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)
        let category = Category(name: "Groceries", hexColor: "#10B981", workspace: workspace)
        let variable = VariableExpense(
            descriptionText: "Market",
            amount: 42,
            transactionDate: date(2026, 5, 2),
            workspace: workspace,
            card: card,
            category: category
        )
        let planned = PlannedExpense(
            title: "Internet",
            plannedAmount: 80,
            expenseDate: date(2026, 5, 19),
            workspace: workspace,
            card: card,
            category: category
        )

        let answer = HomeQueryEngine(calendar: calendar).execute(
            query: HomeQuery(intent: .largestRecentTransactions, dateRange: monthRange(2026, 5)),
            categories: [category],
            plannedExpenses: [planned],
            variableExpenses: [variable],
            now: date(2026, 5, 20)
        )

        let decorated = visualAttachmentAnswer(
            answer,
            workspace: workspace,
            variableExpenses: [variable],
            plannedExpenses: [planned]
        )

        guard case let .rowList(rowList)? = decorated.attachment else {
            Issue.record("Expected HomeQuery recent purchase rows to render native expense rows.")
            return
        }

        #expect(rowList.family == .expenses)
        #expect(rowList.rows.map(\.objectType) == [.plannedExpense, .variableExpense])
        #expect(rowList.hidesSourceRows)
    }

    @Test func visualAttachmentBuilder_polishesMetricComparisonContractAndGenericRows() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let metric = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .metric,
                title: "Safe Spend Today",
                primaryValue: "$45.00",
                rows: [
                    HomeAnswerRow(title: "Period remaining room", value: "$450.00", amount: 450)
                ]
            ),
            workspace: workspace
        )
        let comparison = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .comparison,
                title: "Spending Comparison",
                rows: [
                    HomeAnswerRow(title: "Current period", value: "$80.00", amount: 80),
                    HomeAnswerRow(title: "Previous period", value: "$120.00", amount: 120),
                    HomeAnswerRow(title: "Change", value: "-$40.00", amount: -40)
                ]
            ),
            workspace: workspace
        )
        let contract = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Known Formula",
                rows: [
                    HomeAnswerRow(title: "Metric contract", value: "forecastSavings", role: .contract),
                    HomeAnswerRow(title: "Required support", value: "Executor wiring is planned.", role: .contract)
                ]
            ),
            workspace: workspace
        )
        let trend = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .list,
                title: "Spend trend",
                rows: [
                    HomeAnswerRow(title: "May 1", value: "1x | $40.00"),
                    HomeAnswerRow(title: "May 2", value: "2x | $65.00")
                ]
            ),
            workspace: workspace
        )
        let generic = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "I found details",
                rows: [
                    HomeAnswerRow(title: "Status", value: "Ready")
                ]
            ),
            workspace: workspace
        )

        guard case let .metricSummary(metricSummary)? = metric.attachment,
              case let .comparisonSummary(comparisonSummary)? = comparison.attachment,
              case let .formulaContract(contractSummary)? = contract.attachment,
              case let .trendChart(trendSummary)? = trend.attachment,
              case let .genericSummary(genericSummary)? = generic.attachment else {
            Issue.record("Expected polished attachment fallbacks.")
            return
        }

        #expect(metricSummary.primaryValue == "$45.00")
        #expect(comparisonSummary.deltaValue == "-$40.00")
        #expect(contractSummary.rows.map(\.role).allSatisfy { $0 == .contract })
        #expect(trendSummary.points.first?.value == 40)
        #expect(genericSummary.rows.first?.title == "Status")
    }

    @Test func visualAttachmentBuilder_polishesClarificationAndDeadEndCardsBeforeGenericFallback() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let clarification = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Which Apple do you mean?",
                subtitle: "I found more than one kind of Offshore data with that name. Pick the object type and I can show the details.",
                rows: [
                    HomeAnswerRow(title: "Apple Card", value: "Card", sourceID: appleCard.id, objectType: .card),
                    HomeAnswerRow(title: "Apple Store", value: "$42.00 on Apple Card", objectType: .variableExpense)
                ]
            ),
            workspace: workspace,
            cards: [appleCard]
        )
        let unsupported = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "I can answer this a different way",
                subtitle: "No deterministic Marina executor supports this plan shape.",
                rows: [
                    HomeAnswerRow(title: "Reason", value: "unsupportedCombination")
                ]
            ),
            workspace: workspace
        )
        let contractOnly = visualAttachmentAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Marina knows this metric, but cannot run it yet",
                primaryValue: "contractOnly",
                rows: [
                    HomeAnswerRow(title: "Metric contract", value: "forecastSavings", role: .contract),
                    HomeAnswerRow(title: "Required setup", value: "Executor wiring is planned.", role: .contract)
                ]
            ),
            workspace: workspace
        )

        guard case let .clarification(clarificationCard)? = clarification.attachment else {
            Issue.record("Expected clarification card, saw \(String(describing: clarification.attachment)).")
            return
        }
        guard case let .deadEnd(unsupportedCard)? = unsupported.attachment else {
            Issue.record("Expected unsupported dead-end card, saw \(String(describing: unsupported.attachment)).")
            return
        }
        guard case let .deadEnd(contractCard)? = contractOnly.attachment else {
            Issue.record("Expected contract-only dead-end card, saw \(String(describing: contractOnly.attachment)).")
            return
        }

        #expect(clarificationCard.rows.contains { $0.title == "Next step" && $0.value.contains("Choose") })
        #expect(clarificationCard.hidesSourceRows)
        #expect(unsupported.title == "I need a narrower query")
        #expect(unsupportedCard.rows.contains { $0.value.contains("unsupportedCombination") } == false)
        #expect(contractCard.rows.contains { $0.value.contains("contractOnly") || $0.value.contains("forecastSavings") } == false)
        #expect(contractOnly.title == "Marina needs one setup step")
    }

    @Test func suggestionSectionBuilder_prioritizesClarificationRecoveryThenFollowUps() throws {
        let clarification = [
            MarinaSuggestion(title: "Clarify", query: HomeQuery(intent: .spendThisMonth))
        ]
        let recovery = [
            MarinaRecoverySuggestion(
                suggestion: MarinaSuggestion(title: "Recover", query: HomeQuery(intent: .topCategoriesThisMonth)),
                confidenceScore: 0.4,
                reasoning: "Fallback"
            )
        ]
        let followUps = [
            MarinaSuggestion(title: "Follow up", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
        ]

        let sections = MarinaSuggestionSectionBuilder.build(
            clarificationSuggestions: clarification,
            clarificationReasonCount: 1,
            recoverySuggestions: recovery,
            followUpSuggestions: followUps
        )

        #expect(sections.map(\.title) == ["Clarification (1)", "Recovery", "Follow-Up Suggestions"])
        #expect(sections[0].suggestions.first?.title == "Clarify")
    }

    @Test func suggestionModel_supportsQueryAndPromptBackedActions() throws {
        let querySuggestion = MarinaSuggestion(
            title: "Spend this month",
            query: HomeQuery(intent: .spendThisMonth)
        )
        let promptSuggestion = MarinaSuggestion(
            title: "Show active budget",
            promptText: "What is my active budget?"
        )

        #expect(querySuggestion.isPromptBacked == false)
        #expect(querySuggestion.executionPrompt == "Spend this month")
        #expect(querySuggestion.action == .homeQuery(HomeQuery(intent: .spendThisMonth)))
        #expect(promptSuggestion.isPromptBacked)
        #expect(promptSuggestion.executionPrompt == "What is my active budget?")
        #expect(promptSuggestion.action == .freeformPrompt("What is my active budget?"))
        #expect(promptSuggestion.query.intent == .periodOverview)
    }

    // MARK: - HomeQueryDateRange

    @Test func queryDateRange_reordersWhenInputIsDescending() throws {
        let later = Date(timeIntervalSince1970: 2_000)
        let earlier = Date(timeIntervalSince1970: 1_000)

        let range = HomeQueryDateRange(startDate: later, endDate: earlier)

        #expect(range.startDate == earlier)
        #expect(range.endDate == later)
    }

    @Test func queryDateRange_keepsOrderWhenInputIsAscending() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        let range = HomeQueryDateRange(startDate: start, endDate: end)

        #expect(range.startDate == start)
        #expect(range.endDate == end)
    }

    // MARK: - HomeQuery limits

    @Test func query_defaultLimit_matchesIntentDefaults() throws {
        let overview = HomeQuery(intent: .periodOverview)
        let topCategories = HomeQuery(intent: .topCategoriesThisMonth)
        let recentTransactions = HomeQuery(intent: .largestRecentTransactions)
        let cardSpend = HomeQuery(intent: .cardSpendTotal)
        let cardHabits = HomeQuery(intent: .cardVariableSpendingHabits)
        let incomeAverage = HomeQuery(intent: .incomeAverageActual)
        let savingsStatus = HomeQuery(intent: .savingsStatus)
        let savingsAverage = HomeQuery(intent: .savingsAverageRecentPeriods)
        let incomeShare = HomeQuery(intent: .incomeSourceShare)
        let categoryShare = HomeQuery(intent: .categorySpendShare)
        let incomeShareTrend = HomeQuery(intent: .incomeSourceShareTrend)
        let categoryShareTrend = HomeQuery(intent: .categorySpendShareTrend)
        let presetDueSoon = HomeQuery(intent: .presetDueSoon)
        let presetHighestCost = HomeQuery(intent: .presetHighestCost)
        let presetTopCategory = HomeQuery(intent: .presetTopCategory)
        let presetCategorySpend = HomeQuery(intent: .presetCategorySpend)
        let categoryPotentialSavings = HomeQuery(intent: .categoryPotentialSavings)
        let categoryReallocationGuidance = HomeQuery(intent: .categoryReallocationGuidance)
        let spend = HomeQuery(intent: .spendThisMonth)
        let comparison = HomeQuery(intent: .compareThisMonthToPreviousMonth)

        #expect(overview.resultLimit == 1)
        #expect(topCategories.resultLimit == HomeQuery.defaultTopCategoryLimit)
        #expect(recentTransactions.resultLimit == HomeQuery.defaultRecentTransactionsLimit)
        #expect(cardSpend.resultLimit == 1)
        #expect(cardHabits.resultLimit == 3)
        #expect(incomeAverage.resultLimit == 1)
        #expect(savingsStatus.resultLimit == 1)
        #expect(savingsAverage.resultLimit == 3)
        #expect(incomeShare.resultLimit == 1)
        #expect(categoryShare.resultLimit == 1)
        #expect(incomeShareTrend.resultLimit == 3)
        #expect(categoryShareTrend.resultLimit == 3)
        #expect(presetDueSoon.resultLimit == 3)
        #expect(presetHighestCost.resultLimit == 3)
        #expect(presetTopCategory.resultLimit == 3)
        #expect(presetCategorySpend.resultLimit == 1)
        #expect(categoryPotentialSavings.resultLimit == 3)
        #expect(categoryReallocationGuidance.resultLimit == 3)
        #expect(spend.resultLimit == 1)
        #expect(comparison.resultLimit == 1)
    }

    @Test func query_limit_clampsToAllowedBounds() throws {
        let low = HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 0)
        let high = HomeQuery(intent: .largestRecentTransactions, resultLimit: 500)
        let valid = HomeQuery(intent: .largestRecentTransactions, resultLimit: 12)

        #expect(low.resultLimit == 1)
        #expect(high.resultLimit == HomeQuery.maxResultLimit)
        #expect(valid.resultLimit == 12)
    }

    // MARK: - HomeQueryPlan

    @Test func queryPlan_mapsMetricToIntentAndLimit() throws {
        let range = HomeQueryDateRange(
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_000)
        )

        let topCategoriesPlan = HomeQueryPlan(
            metric: .topCategories,
            dateRange: range,
            resultLimit: 4,
            confidenceBand: .high
        )

        let overviewPlan = HomeQueryPlan(
            metric: .overview,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        #expect(topCategoriesPlan.query.intent == .topCategoriesThisMonth)
        #expect(topCategoriesPlan.query.resultLimit == 4)
        #expect(topCategoriesPlan.query.dateRange == range)

        #expect(overviewPlan.query.intent == .periodOverview)
        #expect(overviewPlan.query.resultLimit == 1)
        #expect(overviewPlan.query.dateRange == nil)
    }

    // MARK: - Codable

    @Test func query_codableRoundTrip_preservesPayload() throws {
        let range = HomeQueryDateRange(
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 5_000)
        )
        let original = HomeQuery(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            intent: .largestRecentTransactions,
            dateRange: range,
            resultLimit: 9
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeQuery.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_codableRoundTrip_preservesRowsAndMetadata() throws {
        let queryID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let generatedAt = Date(timeIntervalSince1970: 12_345)

        let original = HomeAnswer(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            queryID: queryID,
            kind: .list,
            title: "Top Categories",
            subtitle: "This Month",
            primaryValue: "$1,250.00",
            rows: [
                HomeAnswerRow(
                    id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
                    title: "Food",
                    value: "$500.00",
                    sourceID: UUID(uuidString: "AAAAAAAA-1234-1234-1234-123456789012")!,
                    objectType: .category,
                    amount: 500,
                    date: Date(timeIntervalSince1970: 6_000),
                    role: .result
                ),
                HomeAnswerRow(
                    id: UUID(uuidString: "87654321-4321-4321-4321-210987654321")!,
                    title: "Travel",
                    value: "$300.00",
                    sourceID: UUID(uuidString: "BBBBBBBB-4321-4321-4321-210987654321")!,
                    objectType: .variableExpense,
                    amount: 300,
                    date: Date(timeIntervalSince1970: 7_000),
                    role: .evidence
                )
            ],
            generatedAt: generatedAt
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_decodesOldRowsWithoutSourceMetadata() throws {
        let json = """
        {
          "id": "99999999-8888-7777-6666-555555555555",
          "queryID": "11111111-2222-3333-4444-555555555555",
          "kind": "message",
          "title": "Old answer",
          "rows": [
            {
              "id": "12345678-1234-1234-1234-123456789012",
              "title": "Total",
              "value": "$42.00"
            }
          ],
          "generatedAt": 12345
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: json)

        #expect(decoded.rows.first?.sourceID == nil)
        #expect(decoded.rows.first?.objectType == nil)
        #expect(decoded.rows.first?.amount == nil)
        #expect(decoded.rows.first?.date == nil)
        #expect(decoded.rows.first?.role == .result)
    }

    @Test func answer_codableRoundTrip_preservesEntitySummaryAttachment() throws {
        let summary = MarinaEntitySummaryPresentationModel(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            sourceID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            objectType: .savingsAccount,
            title: "Emergency Fund",
            subtitle: "Savings account",
            primaryValue: "$1,200.00",
            systemImage: "banknote.fill",
            tintHex: "#22C55E",
            rows: [
                .init(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, title: "Ledger entries", value: "3")
            ]
        )
        let original = HomeAnswer(
            queryID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            kind: .message,
            title: "I found Emergency Fund.",
            rows: [],
            attachment: .entitySummary(summary),
            generatedAt: Date(timeIntervalSince1970: 12_347)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_codableRoundTrip_preservesRowListAttachment() throws {
        let rowList = MarinaRowListPresentationModel(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Savings activity",
            subtitle: "2 rows",
            family: .savings,
            rows: [
                .init(
                    id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
                    sourceID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                    objectType: .savingsLedgerEntry,
                    title: "Manual Adjustment",
                    subtitle: "May 1, 2026",
                    value: "$25.00",
                    amount: 25,
                    date: Date(timeIntervalSince1970: 12_000),
                    systemImage: "banknote.fill",
                    tintHex: "#22C55E"
                )
            ]
        )
        let original = HomeAnswer(
            queryID: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            kind: .list,
            title: "Savings activity",
            rows: [],
            attachment: .rowList(rowList),
            generatedAt: Date(timeIntervalSince1970: 12_348)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_codableRoundTrip_preservesPolishedAttachments() throws {
        let row = MarinaDisplayRow(
            id: UUID(uuidString: "11111111-AAAA-BBBB-CCCC-111111111111")!,
            title: "Current period",
            value: "$80.00",
            amount: 80,
            role: .result
        )
        let attachments: [MarinaAttachment] = [
            .metricSummary(
                MarinaMetricSummaryPresentationModel(
                    id: UUID(uuidString: "22222222-AAAA-BBBB-CCCC-222222222222")!,
                    title: "Safe Spend",
                    primaryValue: "$45.00",
                    rows: [row]
                )
            ),
            .comparisonSummary(
                MarinaComparisonSummaryPresentationModel(
                    id: UUID(uuidString: "33333333-AAAA-BBBB-CCCC-333333333333")!,
                    title: "Comparison",
                    primaryLabel: "Current",
                    primaryValue: "$80.00",
                    comparisonLabel: "Previous",
                    comparisonValue: "$120.00",
                    deltaLabel: "Change",
                    deltaValue: "-$40.00",
                    rows: [row]
                )
            ),
            .breakdownList(
                MarinaBreakdownListPresentationModel(
                    id: UUID(uuidString: "44444444-AAAA-BBBB-CCCC-444444444444")!,
                    title: "Breakdown",
                    rows: [row]
                )
            ),
            .trendChart(
                MarinaTrendChartPresentationModel(
                    id: UUID(uuidString: "55555555-AAAA-BBBB-CCCC-555555555555")!,
                    title: "Trend",
                    points: [
                        .init(id: UUID(uuidString: "66666666-AAAA-BBBB-CCCC-666666666666")!, label: "May", value: 80, renderedValue: "$80.00")
                    ]
                )
            ),
            .formulaContract(
                MarinaFormulaContractPresentationModel(
                    id: UUID(uuidString: "77777777-AAAA-BBBB-CCCC-777777777777")!,
                    title: "Known Formula",
                    status: "contractOnly",
                    rows: [row]
                )
            ),
            .clarification(
                MarinaClarificationPresentationModel(
                    id: UUID(uuidString: "99999999-AAAA-BBBB-CCCC-999999999999")!,
                    title: "Which one?",
                    rows: [row]
                )
            ),
            .deadEnd(
                MarinaDeadEndPresentationModel(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-BBBB-CCCC-AAAAAAAAAAAA")!,
                    title: "I need a narrower query",
                    rows: [row]
                )
            ),
            .genericSummary(
                MarinaGenericSummaryPresentationModel(
                    id: UUID(uuidString: "88888888-AAAA-BBBB-CCCC-888888888888")!,
                    title: "Details",
                    rows: [row]
                )
            )
        ]

        for attachment in attachments {
            let original = HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Polished",
                attachment: attachment
            )

            let encoded = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

            #expect(decoded == original)
        }
    }

    @Test func answer_codableRoundTrip_preservesInlineCreateFormAttachment() throws {
        let original = HomeAnswer(
            id: UUID(uuidString: "AAAAAAAA-8888-7777-6666-555555555555")!,
            queryID: UUID(uuidString: "BBBBBBBB-2222-3333-4444-555555555555")!,
            kind: .message,
            title: "Create Expense",
            subtitle: nil,
            rows: [],
            attachment: .inlineCreateForm(
                MarinaInlineCreateForm(
                    entity: .expense,
                    summary: nil,
                    amountText: "18.50",
                    date: Date(timeIntervalSince1970: 5_000),
                    notesText: "Coffee",
                    selectedCardID: UUID(uuidString: "CCCCCCCC-1111-2222-3333-444444444444")!
                )
            ),
            generatedAt: Date(timeIntervalSince1970: 12_346)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    // MARK: - Command Plan Updates

    @Test func commandPlanUpdating_cardName_preservesParsedAttributes() throws {
        let original = MarinaCommandPlan(
            intent: .addPreset,
            confidenceBand: .high,
            rawPrompt: "create preset rent 1500 every 2 weeks on Apple Card",
            amount: 1500,
            notes: "rent",
            cardName: "Old Card",
            categoryName: "Housing",
            entityName: "rent",
            cardThemeRaw: "sunset",
            cardEffectRaw: "glass",
            recurrenceFrequencyRaw: RecurrenceFrequency.weekly.rawValue,
            recurrenceInterval: 2,
            weeklyWeekday: 6
        )

        let updated = original.updating(cardName: "Apple Card")

        #expect(updated.cardName == "Apple Card")
        #expect(updated.entityName == "rent")
        #expect(updated.cardThemeRaw == "sunset")
        #expect(updated.cardEffectRaw == "glass")
        #expect(updated.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(updated.recurrenceInterval == 2)
        #expect(updated.weeklyWeekday == 6)
    }

    @Test func commandPlanUpdating_incomeKindAndRecurrence_preservesOtherFields() throws {
        let original = MarinaCommandPlan(
            intent: .addIncome,
            confidenceBand: .high,
            rawPrompt: "log income from side gig 1200",
            amount: 1200,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: "Side Gig",
            isPlannedIncome: nil,
            recurrenceFrequencyRaw: nil,
            recurrenceInterval: nil
        )

        let updated = original.updating(
            isPlannedIncome: false,
            recurrenceFrequencyRaw: RecurrenceFrequency.monthly.rawValue,
            recurrenceInterval: 1
        )

        #expect(updated.amount == 1200)
        #expect(updated.source == "Side Gig")
        #expect(updated.date == original.date)
        #expect(updated.isPlannedIncome == false)
        #expect(updated.recurrenceFrequencyRaw == RecurrenceFrequency.monthly.rawValue)
        #expect(updated.recurrenceInterval == 1)
    }

    // MARK: - Follow-up Anchoring

    @Test func clarificationChoiceResolver_resolvesExactChipTitle() throws {
        let card = MarinaClarificationChoice(
            title: "Apple Card",
            entityTypeHint: .card,
            patchSlot: .target,
            rawValue: "Apple Card",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple?",
            choices: [card]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "Apple Card (card)",
            clarification: clarification
        )
        let cleanTitleResult = MarinaClarificationChoiceResolver().resolve(
            reply: "Apple Card",
            clarification: clarification
        )

        #expect(result == .resolved(card))
        #expect(cleanTitleResult == .resolved(card))
    }

    @Test func clarificationChoiceResolver_returnsAmbiguousForDuplicateCleanDisplayTitle() throws {
        let category = MarinaClarificationChoice(
            title: "Apple",
            entityTypeHint: .category,
            patchSlot: .target,
            rawValue: "Apple",
            sourceID: UUID()
        )
        let merchant = MarinaClarificationChoice(
            title: "Apple",
            entityTypeHint: .merchant,
            patchSlot: .target,
            rawValue: "Apple",
            sourceID: UUID()
        )
        let card = MarinaClarificationChoice(
            title: "Apple Card",
            entityTypeHint: .card,
            patchSlot: .target,
            rawValue: "Apple Card",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple?",
            choices: [category, merchant, card]
        )

        let duplicateTitleResult = MarinaClarificationChoiceResolver().resolve(
            reply: "Apple",
            clarification: clarification
        )
        let uniqueTitleResult = MarinaClarificationChoiceResolver().resolve(
            reply: "Apple Card",
            clarification: clarification
        )

        #expect(duplicateTitleResult == .ambiguous([category, merchant]))
        #expect(uniqueTitleResult == .resolved(card))
    }

    @Test func clarificationChoiceResolver_resolvesUniqueTypeAlias() throws {
        let category = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .category,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let expense = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Groceries?",
            choices: [category, expense]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "category",
            clarification: clarification
        )

        #expect(result == .resolved(category))
    }

    @Test func clarificationChoiceResolver_returnsAmbiguousForRepeatedTypeAlias() throws {
        let first = MarinaClarificationChoice(
            title: "Apple Watch",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Apple Watch",
            sourceID: UUID()
        )
        let second = MarinaClarificationChoice(
            title: "Apple Store",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Apple Store",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple?",
            choices: [first, second]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "expense",
            clarification: clarification
        )

        #expect(result == .ambiguous([first, second]))
    }

    @Test func clarificationChoiceResolver_doesNotFabricateUnmatchedTargetChoice() throws {
        let choice = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .category,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Groceries?",
            choices: [choice]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "category(category) category",
            clarification: clarification
        )

        #expect(result == .unresolved)
    }

    @Test func promptTurnClassifier_compareToLastMonthIsFollowUp() throws {
        let classifier = MarinaPromptTurnClassifier()

        #expect(classifier.classify("Compare to last month", defaultPeriodUnit: .month) == .followUp)
        #expect(classifier.classify("Compare this to last month", defaultPeriodUnit: .month) == .followUp)
    }

    @Test func promptTurnClassifier_whatIfIsFreshFoundationPrompt() throws {
        let classifier = MarinaPromptTurnClassifier()

        #expect(classifier.classify("What if I saved 200 more this month?", defaultPeriodUnit: .month) == .freshQuestion)
    }

    @Test func followUpAnchorResolver_matchesLatestRelevantAnswer() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let context = MarinaAnswerContext(
            query: HomeQuery(
                intent: .categoryReallocationGuidance,
                dateRange: HomeQueryDateRange(
                    startDate: Date(timeIntervalSince1970: 1_000),
                    endDate: Date(timeIntervalSince1970: 2_000)
                ),
                targetName: "Bills & Utilities"
            ),
            answerTitle: "Reallocation Guidance (Bills & Utilities)",
            answerKind: .list,
            userPrompt: "Category reallocation guidance",
            targetName: "Bills & Utilities",
            targetType: .category,
            rowTitles: ["Current Bills & Utilities", "Reduce other categories by", "Shopping"],
            rowValues: ["$2,399.94", "$239.99", "$106.30 (from $261.50)"],
            scenarioPercent: 10
        )

        let decision = resolver.resolve(
            prompt: "Reduce bills by 10% will save me 239.99?",
            recentContexts: [context]
        )

        #expect(decision == .matched(context))
    }

    @Test func followUpAnchorResolver_usesRecentFallbackWhenLatestIsWeakMatch() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let older = MarinaAnswerContext(
            query: HomeQuery(intent: .merchantSpendTotal, targetName: "Starbucks"),
            answerTitle: "Merchant Spend (Starbucks)",
            answerKind: .message,
            userPrompt: "What did I spend at Starbucks this year?",
            targetName: "Starbucks",
            targetType: .merchant,
            rowTitles: ["Transactions", "Latest activity", "Total"],
            rowValues: ["17", "Mar 27, 2026", "$425.00"],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let latest = MarinaAnswerContext(
            query: HomeQuery(intent: .periodOverview),
            answerTitle: "Budget Overview",
            answerKind: .message,
            userPrompt: "How am I doing this month?",
            rowTitles: ["Total spend"],
            rowValues: ["$1,234.00"],
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let decision = resolver.resolve(
            prompt: "What about Starbucks instead?",
            recentContexts: [older, latest]
        )

        #expect(decision == .matched(older))
    }

    @Test func followUpAnchorResolver_returnsAmbiguousWhenTwoRecentAnswersFit() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let first = MarinaAnswerContext(
            query: HomeQuery(intent: .categoryPotentialSavings, targetName: "Groceries"),
            answerTitle: "Potential Savings (Groceries)",
            answerKind: .list,
            userPrompt: "If I cut groceries, what could I save?",
            targetName: "Groceries",
            targetType: .category,
            rowTitles: ["Current spend"],
            rowValues: ["$500.00"],
            scenarioPercent: 10,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = MarinaAnswerContext(
            query: HomeQuery(intent: .categoryPotentialSavings, targetName: "Dining"),
            answerTitle: "Potential Savings (Dining)",
            answerKind: .list,
            userPrompt: "If I cut dining, what could I save?",
            targetName: "Dining",
            targetType: .category,
            rowTitles: ["Current spend"],
            rowValues: ["$420.00"],
            scenarioPercent: 10,
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let decision = resolver.resolve(
            prompt: "Will that save me 10%?",
            recentContexts: [first, second]
        )

        if case let .ambiguous(contexts) = decision {
            #expect(contexts.count == 2)
        } else {
            Issue.record("Expected ambiguous follow-up anchor decision")
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: comps) ?? .distantPast
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        date(year, month, day, 0, 0, 0)
    }

    private func dayRange(_ year: Int, _ month: Int, _ day: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, day, 0, 0, 0),
            endDate: date(year, month, day, 23, 59, 59)
        )
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let start = date(year, month, 1, 0, 0, 0)
        let endDay = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
        return HomeQueryDateRange(
            startDate: start,
            endDate: date(year, month, endDay, 23, 59, 59)
        )
    }

    private func weekRange(_ year: Int, _ month: Int, _ day: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, day, 0, 0, 0),
            endDate: date(year, month, day + 6, 23, 59, 59)
        )
    }

    private func visualAttachmentAnswer(
        _ answer: HomeAnswer,
        workspace: Workspace,
        cards: [Card] = [],
        allocationAccounts: [AllocationAccount] = [],
        savingsAccounts: [SavingsAccount] = [],
        categories: [Offshore.Category] = [],
        presets: [Preset] = [],
        variableExpenses: [VariableExpense] = [],
        plannedExpenses: [PlannedExpense] = [],
        savingsEntries: [SavingsLedgerEntry] = []
    ) -> HomeAnswer {
        MarinaVisualAttachmentBuilder().attachingVisualAttachmentIfNeeded(
            to: answer,
            workspace: workspace,
            cards: cards,
            allocationAccounts: allocationAccounts,
            savingsAccounts: savingsAccounts,
            categories: categories,
            presets: presets,
            variableExpenses: variableExpenses,
            plannedExpenses: plannedExpenses,
            savingsEntries: savingsEntries,
            dateRange: monthRange(2026, 5),
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false
        )
    }

    private func makePriorQueryContext(
        metric: HomeQueryMetric,
        targetName: String?,
        targetType: MarinaAnswerTargetType?,
        dateRange: HomeQueryDateRange,
        resultLimit: Int? = nil,
        periodUnit: HomeQueryPeriodUnit = .month,
        lastQueryPlan: HomeQueryPlan? = nil
    ) -> MarinaPriorQueryContext {
        let plan = lastQueryPlan ?? HomeQueryPlan(
            metric: metric,
            dateRange: dateRange,
            resultLimit: resultLimit,
            confidenceBand: .high,
            targetName: targetName,
            periodUnit: periodUnit
        )

        return MarinaPriorQueryContext(
            lastQueryPlan: plan,
            lastMetric: metric,
            lastTargetName: targetName,
            lastTargetType: targetType,
            lastDateRange: dateRange,
            lastResultLimit: resultLimit,
            lastPeriodUnit: periodUnit
        )
    }

    private func makeRouterContext(
        priorQueryContext: MarinaPriorQueryContext
    ) -> MarinaInterpretationContext {
        MarinaInterpretationContext(
            workspaceName: "Test Workspace",
            defaultPeriodUnit: .month,
            sessionContext: MarinaSessionContext(),
            priorQueryContext: priorQueryContext,
            cardNames: [],
            categoryNames: ["Groceries"],
            incomeSourceNames: [],
            presetTitles: [],
            budgetNames: [],
            aliasSummaries: [],
            now: date(2026, 4, 15, 12, 0, 0)
        )
    }

    private func emptyPriorQueryContext() -> MarinaPriorQueryContext {
        MarinaPriorQueryContext(
            lastQueryPlan: nil,
            lastMetric: nil,
            lastTargetName: nil,
            lastTargetType: nil,
            lastDateRange: nil,
            lastResultLimit: nil,
            lastPeriodUnit: nil
        )
    }

}

private struct StubAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct StubStructuredInterpreter: MarinaStructuredIntentInterpreting {
    let result: Result<MarinaStructuredIntent, Error>

    func interpret(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaStructuredIntent {
        try result.get()
    }
}
