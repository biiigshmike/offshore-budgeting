import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaFoundationSemanticRealAppTests {
    @Test func semanticRealApp_foundationTypedSpendExecutesWithEvidence() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "How much did I spend on groceries this month?"
        let candidate = spendCandidate(
            prompt: prompt,
            mentions: [mention("Groceries", .category)],
            timeScopes: [monthScope()]
        )
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(candidate)
        ])

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected handled Foundation semantic answer.")
            return
        }

        #expect(answer.kind == .metric)
        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Groceries") })
        #expect(amountBasis == .budgetImpact)
        #expect(route?.traceName == "aggregate")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_freeTextMerchantExpensePhrasesShareCanonicalRows() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "DoorDash - Mr. Pickle", amount: 45.69, transactionDate: date(2026, 5, 10), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "DoorDash - Mr. Pickle", amount: 50.74, transactionDate: date(2026, 5, 14), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Starbucks", amount: 25, transactionDate: date(2026, 5, 13), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompts = [
            "Show me all of my Mr. Pickle expenses, please",
            "List Mr. Pickle Expenses",
            "Show Mr. Pickle"
        ]
        let coordinator = coordinator(for: Dictionary(uniqueKeysWithValues: prompts.map { prompt in
            (prompt, freeTextRowsInterpretation(prompt: prompt, target: "Mr. Pickle"))
        }))

        var canonicalResultTitles: [[String]] = []
        for prompt in prompts {
            let (result, trace) = await tracedTurn(prompt: prompt) {
                await coordinator.run(prompt: prompt, context: turnContext(fixture))
            }

            guard case .handled(let answer, _, _, _, let route) = result else {
                Issue.record("Expected free-text merchant row lookup to handle '\(prompt)'.")
                continue
            }
            let pickleTitles = answer.rows.map(\.title).filter {
                $0.localizedCaseInsensitiveContains("Mr. Pickle")
            }
            #expect(pickleTitles.count == 2)
            #expect(answer.rows.contains { $0.title.localizedCaseInsensitiveContains("Starbucks") } == false)
            #expect(route?.traceName == "list")
            canonicalResultTitles.append(pickleTitles)
            assertFoundationOnly(trace)
        }

        #expect(Set(canonicalResultTitles).count == 1)
    }

    @Test func semanticRealApp_allocatedCategoryContractUsesAllocatedShareInsteadOfGrossSpend() async throws {
        let fixture = try makeFixture()
        let cannabis = Offshore.Category(name: "Cannabis", hexColor: "#225522", workspace: fixture.workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let sharedCannabis = VariableExpense(
            descriptionText: "Cannabis shared purchase",
            amount: 100,
            transactionDate: date(2026, 5, 9),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: cannabis
        )
        let grossOnlyCannabis = VariableExpense(
            descriptionText: "Cannabis personal purchase",
            amount: 70,
            transactionDate: date(2026, 5, 10),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: cannabis
        )
        fixture.context.insert(cannabis)
        fixture.context.insert(alejandro)
        fixture.context.insert(sharedCannabis)
        fixture.context.insert(grossOnlyCannabis)
        fixture.context.insert(ExpenseAllocation(
            allocatedAmount: 30,
            workspace: fixture.workspace,
            account: alejandro,
            expense: sharedCannabis
        ))
        try fixture.context.save()

        let prompt = "What had Alejandro spent on Cannabis?"
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Alejandro",
                    typeHint: .allocationAccount,
                    allowedTypeHints: [.allocationAccount]
                ),
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Cannabis",
                    typeHint: .category,
                    allowedTypeHints: [.category]
                )
            ],
            timeScopes: [monthScope()],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(candidate)
        ])

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(
                    fixture,
                    categoryNames: ["Groceries", "Travel", "Cannabis"],
                    allocationAccountNames: ["Alejandro"]
                )
            )
        }

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected allocated category spend to execute.")
            return
        }

        #expect(answer.primaryValue == "$30.00")
        #expect(answer.primaryValue != "$170.00")
        #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == "allocatedCategorySpend" })
        #expect(answer.rows.contains { $0.title == "Amount basis" && $0.value == "allocated" })
        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.contains("Alejandro") && $0.value.contains("Cannabis") })
        #expect(amountBasis == .allocated)
        #expect(route?.traceName == "aggregate")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_missingSeedReturnsContractAwareResponseInsteadOfFallback() async throws {
        let fixture = try makeFixture()
        let prompt = "What upcoming expenses will hit before my next income?"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .blocked(let answer, let outcome) = result else {
            Issue.record("Expected missing contract seed to block with contract-aware answer.")
            return
        }

        #expect(answer.title == "Marina needs one setup step")
        #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == "upcomingExpensesBeforeNextIncome" })
        #expect(answer.rows.contains { $0.title == "Amount basis" && $0.value == "budget impact" })
        #expect(answer.rows.contains { $0.title == "Source rows" && $0.value.contains("PlannedExpense") && $0.value.contains("Income") })
        guard case .unsupported(let unsupported) = outcome else {
            Issue.record("Expected unsupported contract outcome.")
            return
        }
        #expect(unsupported.message.contains("upcoming planned or actual income"))
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_allApprovedMetricSeedsSurfaceContractEvidence() async throws {
        let fixture = try makeFixture()
        let seedIDs: [MarinaMetricContractID] = [
            .safeSpendRemaining,
            .spendingIncreaseDrivers,
            .categoryOverPace,
            .upcomingExpensesBeforeNextIncome,
            .plannedVsActualSpend,
            .unrecordedPlannedExpenses,
            .unusualMerchantSpend,
            .subscriptionSpend,
            .reconciliationOwedThisMonth,
            .trueOwnedSpend,
            .cardOverspendingDriver,
            .categoryCutImpact,
            .skipCategoryScenario,
            .savingsTrackVsLastMonth,
            .budgetSharedLinks,
            .categorizationReview,
            .sinceLastCheckIn
        ]
        let contracts = try seedIDs.map { try #require(MarinaMetricContractRegistry.current.contract(for: $0)) }
        let coordinator = coordinator(for: Dictionary(uniqueKeysWithValues: contracts.map { contract in
            (contract.seedPrompt, canonicalInterpretation(unsupportedCandidate(prompt: contract.seedPrompt)))
        }))

        for contract in contracts {
            let (result, _) = await tracedTurn(prompt: contract.seedPrompt) {
                await coordinator.run(prompt: contract.seedPrompt, context: turnContext(fixture))
            }

            switch result {
            case .handled(let answer, _, _, _, _), .blocked(let answer, _):
                #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == contract.id.rawValue })
            case .clarification, .unavailable:
                Issue.record("Expected \(contract.id.rawValue) to handle or return a setup-aware block.")
            }
        }
    }

    @Test func semanticRealApp_formulaNamePhraseRoutesToContractExecutor() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Paycheck", amount: 1_200, date: date(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Side Work", amount: 300, date: date(2026, 5, 9), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Expected Bonus", amount: 900, date: date(2026, 5, 20), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let prompt = "income by source"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected formula-name phrase to execute through the metric contract.")
            return
        }

        #expect(answer.title == "Income by Source")
        #expect(answer.primaryValue == "$1,500.00")
        #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == "incomeBySource" })
        #expect(answer.rows.contains { $0.title == "Amount basis" && $0.value == "actual income" })
        #expect(answer.rows.contains { $0.title == "Paycheck" && $0.value == "$1,200.00" })
        #expect(answer.rows.contains { $0.title == "Expected Bonus" } == false)
        #expect(amountBasis == .actualIncome)
        #expect(route?.traceName == "groupedRanked")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_allFormulaNamePhrasesSurfaceContractEvidence() async throws {
        let fixture = try makeFixture()
        var interpretations: [String: MarinaCanonicalReadInterpretation] = [:]
        let prompts = MarinaMetricContractRegistry.current.contracts.map { contract in
            let prompt = spaced(contract.formulaName)
            interpretations[prompt] = canonicalInterpretation(unsupportedCandidate(prompt: prompt))
            return (prompt: prompt, contract: contract)
        }
        let coordinator = coordinator(for: interpretations)

        for item in prompts {
            let (result, trace) = await tracedTurn(prompt: item.prompt) {
                await coordinator.run(prompt: item.prompt, context: turnContext(fixture))
            }

            switch result {
            case .handled(let answer, _, _, _, _), .blocked(let answer, _):
                #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == item.contract.id.rawValue }, "Prompt '\(item.prompt)' should surface \(item.contract.id.rawValue).")
            case .clarification, .unavailable:
                Issue.record("Expected formula prompt '\(item.prompt)' to surface \(item.contract.id.rawValue).")
            }
            assertFoundationOnly(trace)
        }
    }

    @Test func semanticRealApp_typedRelationshipPromptUsesDeterministicExecutor() async throws {
        let fixture = try makeFixture()
        let budget = Budget(
            name: "May Budget",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            workspace: fixture.workspace
        )
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.appleCard))
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.backupCard))
        try fixture.context.save()
        let prompt = "Which cards are linked to May Budget?"
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaTypedFixtureInterpreter()
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(
                    fixture,
                    cardNames: ["Apple Card", "Backup Card"],
                    budgetNames: ["May Budget"]
                )
            )
        }

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected linked-card relationship prompt to execute through Foundation.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Backup Card" })
        #expect(route?.traceName == "groupedRanked")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_clarificationResumeStaysFoundationOnly() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 40,
                transactionDate: date(2026, 5, 9),
                workspace: fixture.workspace,
                card: fixture.appleCard,
                category: nil
            )
        )
        try fixture.context.save()

        let prompt = "What did I spend at Apple?"
        let mentionID = UUID()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    id: mentionID,
                    role: .filter,
                    rawText: "Apple",
                    typeHint: nil,
                    allowedTypeHints: [.card, .merchant],
                    confidence: .medium
                )
            ],
            responseShapeHint: .clarification,
            confidence: .medium
        )
        let cardChoice = MarinaClarificationChoice(
            title: "Apple Card",
            entityRole: .filter,
            entityTypeHint: .card,
            patchSlot: .target,
            rawValue: "Apple Card",
            sourceID: fixture.appleCard.id,
            mentionID: mentionID
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple target did you mean?",
            candidate: candidate,
            patchSlot: .target,
            choices: [
                cardChoice,
                MarinaClarificationChoice(
                    title: "Apple Store",
                    entityRole: .filter,
                    entityTypeHint: .merchant,
                    patchSlot: .target,
                    rawValue: "Apple Store",
                    mentionID: mentionID
                )
            ]
        )
        let coordinator = coordinator(for: [
            prompt: MarinaCanonicalReadInterpretation(
                result: .clarification(clarification),
                compatibilityCandidate: candidate
            )
        ])

        let (initial, initialTrace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }
        guard case .clarification = initial else {
            Issue.record("Expected typed clarification before executing.")
            return
        }
        assertFoundationOnly(initialTrace, allowsClarificationRoute: true)

        let (resumed, resumedTrace) = await tracedTurn(prompt: "Apple Card") {
            await coordinator.resume(
                clarification: clarification,
                choice: cardChoice,
                context: turnContext(fixture, turnClassification: .clarificationAnswer)
            )
        }
        guard case .handled(let answer, _, _, _, let route) = resumed else {
            Issue.record("Expected clarified card choice to execute.")
            return
        }

        #expect(answer.kind == .metric)
        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Apple Card") })
        #expect(route?.traceName == "aggregate")
        assertFoundationOnly(resumedTrace)
    }

    @Test func semanticRealApp_bareShowCategoryClarifiesWithRunnableChoices() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let prompt = "Show Groceries"
        let candidate = unsupportedCandidate(prompt: prompt)
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(candidate)
        ])

        let (initial, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .clarification(_, let clarification) = initial else {
            Issue.record("Expected bare category prompt to ask a clarification.")
            return
        }

        #expect(clarification.choices.contains { $0.title == "Groceries spending" && $0.resumeIntent != nil })
        #expect(clarification.choices.contains { $0.title == "Groceries expenses" && $0.resumeIntent != nil })

        let choice = try #require(clarification.choices.first { $0.title == "Groceries spending" })
        let (resumed, _) = await tracedTurn(prompt: choice.title) {
            await coordinator.resume(
                clarification: clarification,
                choice: choice,
                context: turnContext(fixture, turnClassification: .clarificationAnswer)
            )
        }

        guard case .handled(let answer, _, _, _, _) = resumed else {
            Issue.record("Expected clarification choice to execute.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Groceries") })
    }

    @Test func semanticRealApp_upcomingBudgetsRecoverFromUnsupported() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Budget(name: "April Budget", startDate: date(2026, 4, 1), endDate: date(2026, 4, 30), workspace: fixture.workspace))
        fixture.context.insert(Budget(name: "May Budget", startDate: date(2026, 5, 1), endDate: date(2026, 5, 31), workspace: fixture.workspace))
        fixture.context.insert(Budget(name: "June Budget", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: fixture.workspace))
        try fixture.context.save()

        let prompt = "What are my upcoming budgets?"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(fixture, budgetNames: ["April Budget", "May Budget", "June Budget"])
            )
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected upcoming budgets to execute.")
            return
        }

        #expect(answer.title == "Upcoming Budgets")
        #expect(answer.rows.contains { $0.title == "May Budget" })
        #expect(answer.rows.contains { $0.title == "June Budget" })
        #expect(answer.rows.contains { $0.title == "April Budget" } == false)
    }

    @Test func semanticRealApp_plannedExpensesNextMonthRecoverFromUnsupported() async throws {
        let fixture = try makeFixture()
        let rent = Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: fixture.groceries)
        fixture.context.insert(rent)
        fixture.context.insert(PlannedExpense(title: "Rent Bill", plannedAmount: 1_500, expenseDate: date(2026, 6, 3), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries, sourcePresetID: rent.id))
        fixture.context.insert(PlannedExpense(title: "May Only", plannedAmount: 80, expenseDate: date(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "What are my planned expenses for next month?"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture, presetTitles: ["Rent"]))
        }

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected planned expenses next month to execute.")
            return
        }

        #expect(answer.title == "Planned Expenses Due")
        #expect(answer.rows.contains { $0.title == "Rent Bill" && $0.value.contains("preset Rent") })
        #expect(answer.rows.contains { $0.title == "May Only" } == false)
        #expect(route?.traceName == "aggregate")
    }

    @Test func semanticRealApp_savingsActivityUsesLedgerRows() async throws {
        let fixture = try makeFixture()
        let account = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        fixture.context.insert(account)
        fixture.context.insert(SavingsLedgerEntry(date: date(2026, 5, 10), amount: 125, note: "Manual deposit", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: account))
        try fixture.context.save()

        let prompt = "Show savings activity"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected savings activity to execute.")
            return
        }

        #expect(answer.title == "Savings Activity")
        #expect(answer.rows.contains { $0.title == "Manual deposit" })
    }

    @Test func semanticRealApp_formulaIR_sumsCategorySpend() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let prompt = "Sum Groceries spend this month."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected Formula IR sum to execute.")
            return
        }

        assertFormulaFamilyRows(answer, family: .sum, measure: .variableBudgetImpact)
        #expect(answer.title == "Groceries Total Spending")
        #expect(answer.primaryValue?.contains("50") == true)
    }

    @Test func semanticRealApp_formulaIR_averagesWeeklyCategorySpend() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "Feb Groceries", amount: 70, transactionDate: date(2026, 2, 10), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Mar Groceries", amount: 80, transactionDate: date(2026, 3, 10), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Apr Groceries", amount: 90, transactionDate: date(2026, 4, 10), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "Average weekly Groceries spend over the last 3 months."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected Formula IR average to execute.")
            return
        }

        assertFormulaFamilyRows(answer, family: .average, measure: .variableBudgetImpact)
        #expect(answer.title == "Groceries Average Weekly Spending")
        #expect(answer.rows.contains { $0.title == "Average basis" && $0.value.contains("weeks") })
    }

    @Test func semanticRealApp_formulaIR_ranksCardsBySpend() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "Apple Spend", amount: 40, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Backup Spend", amount: 95, transactionDate: date(2026, 5, 6), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        try fixture.context.save()

        let prompt = "Rank cards by spending this month."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected Formula IR rank to execute.")
            return
        }

        assertFormulaFamilyRows(answer, family: .rank, measure: .variableBudgetImpact)
        #expect(answer.rows.contains { $0.title == "Backup Card" && $0.value.contains("95") })
    }

    @Test func semanticRealApp_formulaIR_comparesCategorySpend() async throws {
        let fixture = try makeFixture()
        let utilities = Offshore.Category(name: "Utilities", hexColor: "#888888", workspace: fixture.workspace)
        fixture.context.insert(utilities)
        fixture.context.insert(VariableExpense(descriptionText: "April Power", amount: 50, transactionDate: date(2026, 4, 8), workspace: fixture.workspace, card: fixture.appleCard, category: utilities))
        fixture.context.insert(VariableExpense(descriptionText: "May Power", amount: 80, transactionDate: date(2026, 5, 8), workspace: fixture.workspace, card: fixture.appleCard, category: utilities))
        try fixture.context.save()

        let prompt = "Compare Utilities this month to last month."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture, categoryNames: ["Groceries", "Travel", "Utilities"]))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected Formula IR compare to execute.")
            return
        }

        assertFormulaFamilyRows(answer, family: .compare, measure: .variableBudgetImpact)
        #expect(answer.title == "Utilities Comparison Spending")
        #expect(answer.rows.contains { $0.title == "Change" && $0.value.contains("30") })
    }

    @Test func semanticRealApp_formulaIR_countsUncategorizedTransactions() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "Unknown One", amount: 10, transactionDate: date(2026, 5, 4), workspace: fixture.workspace, card: fixture.appleCard, category: nil))
        fixture.context.insert(VariableExpense(descriptionText: "Unknown Two", amount: 20, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.backupCard, category: nil))
        fixture.context.insert(VariableExpense(descriptionText: "Known", amount: 30, transactionDate: date(2026, 5, 6), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "Count uncategorized transactions."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected Formula IR count to execute.")
            return
        }

        assertFormulaFamilyRows(answer, family: .count, measure: .count)
        #expect(answer.primaryValue == "2")
    }

    @Test func semanticRealApp_groceryPaceUsesCategoryLimitBurnRateFormula() async throws {
        let fixture = try makeFixture()
        let budget = Budget(name: "May Budget", startDate: date(2026, 5, 1), endDate: date(2026, 5, 31), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCategoryLimit(minAmount: nil, maxAmount: 300, budget: budget, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Week 1", amount: 120, transactionDate: date(2026, 5, 4), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries Week 2", amount: 120, transactionDate: date(2026, 5, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "If I keep spending on groceries at this pace, when do I blow past my grocery limit?"
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture, budgetNames: ["May Budget"]))
        }

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected category limit burn-rate formula to execute.")
            return
        }

        #expect(answer.title == "Groceries Limit Burn Rate")
        assertFormulaRows(answer, formula: .categoryLimitBurnRate)
        #expect(answer.rows.contains { $0.title == "Expected limit date" })
        #expect(answer.rows.contains { $0.title == "Budget max" && $0.value.contains("300") })
        #expect(route?.traceName == "scenario")
    }

    @Test func semanticRealApp_savingsDragUsesLargestCardFormula() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "Apple Small", amount: 50, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Backup Large", amount: 425, transactionDate: date(2026, 5, 7), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        fixture.context.insert(PlannedExpense(title: "Backup Plan", plannedAmount: 100, expenseDate: date(2026, 5, 20), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        try fixture.context.save()

        let prompt = "Which card is quietly ruining my savings this month?"
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected card savings drag formula to execute.")
            return
        }

        #expect(answer.title == "Card Savings Drag")
        assertFormulaRows(answer, formula: .cardSavingsDrag)
        #expect(answer.primaryValue?.contains("Backup Card") == true)
        #expect(answer.rows.contains { $0.title == "Backup Card" && $0.value.contains("actual") && $0.value.contains("planned") })
    }

    @Test func semanticRealApp_postedEarlyPlannedExpenseUsesStressFormula() async throws {
        let fixture = try makeFixture()
        let rent = Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: fixture.groceries)
        fixture.context.insert(rent)
        fixture.context.insert(SavingsAccount(name: "True Savings", total: 250, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Paycheck", amount: 600, date: date(2026, 6, 1), isPlanned: true, workspace: fixture.workspace))
        fixture.context.insert(PlannedExpense(title: "Rent Bill", plannedAmount: 1_500, expenseDate: date(2026, 6, 3), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries, sourcePresetID: rent.id))
        fixture.context.insert(PlannedExpense(title: "Internet", plannedAmount: 120, expenseDate: date(2026, 6, 10), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        try fixture.context.save()

        let prompt = "What planned expense next month would hurt the most if it posted early?"
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture, presetTitles: ["Rent"]))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected early planned expense stress formula to execute.")
            return
        }

        #expect(answer.title == "Early Planned Expense Stress")
        assertFormulaRows(answer, formula: .earlyPlannedExpenseStress)
        #expect(answer.rows.contains { $0.title == "Rent Bill" && $0.value.contains("preset Rent") && $0.value.contains("stress") })
    }

    @Test func semanticRealApp_recurringSubscriptionsDoNotBecomeGenericComparison() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(descriptionText: "StreamBox", amount: 10, transactionDate: date(2026, 3, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "StreamBox", amount: 10, transactionDate: date(2026, 4, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "StreamBox", amount: 25, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(VariableExpense(descriptionText: "StreamBox", amount: 25, transactionDate: date(2026, 5, 14), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.travel))
        fixture.context.insert(PlannedExpense(title: "Music Plan", plannedAmount: 10, actualAmount: 15, expenseDate: date(2026, 5, 8), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "Show me subscriptions or recurring-ish charges that look suspiciously higher than usual."
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected recurring charge anomaly formula to execute.")
            return
        }

        #expect(answer.title == "Recurring Charge Anomalies")
        #expect(answer.title != "Spending Comparison This Month")
        assertFormulaRows(answer, formula: .recurringChargeAnomaly)
        #expect(answer.rows.contains { $0.title == "Streambox" || $0.title == "Music Plan" })
    }

    @Test func semanticRealApp_unsafeExpenseOnlyPromptUsesSavingsRunwayFormula() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(SavingsAccount(name: "True Savings", total: 300, workspace: fixture.workspace))
        fixture.context.insert(VariableExpense(descriptionText: "Groceries", amount: 90, transactionDate: date(2026, 5, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(VariableExpense(descriptionText: "Travel", amount: 60, transactionDate: date(2026, 5, 10), workspace: fixture.workspace, card: fixture.backupCard, category: fixture.travel))
        fixture.context.insert(Income(source: "Ignored Income", amount: 10_000, date: date(2026, 5, 12), isPlanned: false, workspace: fixture.workspace))
        try fixture.context.save()

        let prompt = "If I ignore income and only look at actual card activity, how many days until this budget feels unsafe?"
        let coordinator = coordinator(for: [prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected expense-only savings runway formula to execute.")
            return
        }

        #expect(answer.title == "Expense-Only Savings Runway")
        assertFormulaRows(answer, formula: .expenseOnlySavingsRunway)
        #expect(answer.rows.contains { $0.title == "Actual card activity" })
        #expect(answer.rows.contains { $0.title == "Ignored Income" } == false)
    }

    private func coordinator(for interpretations: [String: MarinaCanonicalReadInterpretation]) -> MarinaTurnCoordinator {
        MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: interpretations)
        )
    }

    private func tracedTurn(
        prompt: String,
        turn: () async -> MarinaTurnResult
    ) async -> (MarinaTurnResult, MarinaExecutionTrace?) {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: prompt,
            routingMode: .foundationPipeline,
            runtimeSettingsSummary: "foundationSemanticRealApp=true"
        )
        let result = await turn()
        switch result {
        case .clarification:
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "foundation_semantic_real_app")
        case .handled, .blocked, .unavailable:
            MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "foundation_semantic_real_app")
        }
        return (result, MarinaTraceRecorder.shared.finish())
    }

    private func assertFoundationOnly(
        _ trace: MarinaExecutionTrace?,
        allowsClarificationRoute: Bool = false
    ) {
        guard let trace else {
            Issue.record("Expected a Marina execution trace.")
            return
        }
        let allowedRoutes: [MarinaExecutionSelectedRoute] = allowsClarificationRoute
            ? [.foundationModels, .clarification]
            : [.foundationModels]
        #expect(allowedRoutes.contains(trace.selectedRoute))
        #expect(trace.foundationPipelinePath == .foundationModels)
        #expect(trace.foundationPipelineInterpreterSource == .foundationModels)
    }

    private func assertFormulaRows(
        _ answer: HomeAnswer,
        formula: MarinaCompositeFormulaKind
    ) {
        #expect(answer.rows.contains { $0.title == "Formula" && $0.value == formula.rawValue })
        #expect(answer.rows.contains { $0.title == "Assumptions" && $0.value.isEmpty == false })
        #expect(answer.rows.contains { $0.title == "Date range" && $0.value.isEmpty == false })
    }

    private func assertFormulaFamilyRows(
        _ answer: HomeAnswer,
        family: MarinaFormulaFamily,
        measure: MarinaFormulaMeasure
    ) {
        #expect(answer.rows.contains { $0.title == "Formula family" && $0.value == family.rawValue })
        #expect(answer.rows.contains { $0.title == "Measure" && $0.value == measure.rawValue })
        #expect(answer.rows.contains { $0.title == "Assumptions" && $0.value.isEmpty == false })
        #expect(answer.rows.contains { $0.title == "Date range" && $0.value.isEmpty == false })
    }

    private func canonicalInterpretation(
        _ candidate: MarinaQueryPlanCandidate
    ) -> MarinaCanonicalReadInterpretation {
        MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func freeTextRowsInterpretation(
        prompt: String,
        target: String
    ) -> MarinaCanonicalReadInterpretation {
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [
                MarinaFilter(
                    role: .filter,
                    relationship: .merchant,
                    value: target,
                    matchMode: .freeText,
                    entityTypeHint: .merchant,
                    allowedEntityTypeHints: [.merchant, .expense, .transaction],
                    sourceID: nil
                )
            ],
            amountField: .amount,
            grouping: MarinaGrouping(dimension: .transaction, rawText: "transaction"),
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "newest"),
            limit: 10,
            responseShape: .rankedList,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: [.merchant, .expense, .transaction],
                requestedDetail: nil,
                responseShape: .rankedList,
                preferredExecutorRoute: .list
            )
        )
        return MarinaCanonicalReadInterpretation(
            result: .query(query),
            compatibilityCandidate: MarinaSemanticQueryAdapter().compatibilityCandidate(from: query, prompt: prompt)
        )
    }

    private func spendCandidate(
        prompt: String,
        mentions: [MarinaUnresolvedEntityMention],
        timeScopes: [MarinaUnresolvedTimeScope]
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: mentions,
            timeScopes: timeScopes,
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )
    }

    private func unsupportedCandidate(prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            responseShapeHint: .unsupported,
            confidence: .medium,
            unsupportedHint: .unsupportedOperation
        )
    }

    private func mention(
        _ rawText: String,
        _ type: MarinaCandidateEntityTypeHint
    ) -> MarinaUnresolvedEntityMention {
        MarinaUnresolvedEntityMention(
            role: .primaryTarget,
            rawText: rawText,
            typeHint: type,
            allowedTypeHints: [type],
            confidence: .high
        )
    }

    private func monthScope() -> MarinaUnresolvedTimeScope {
        MarinaUnresolvedTimeScope(
            role: .primary,
            rawText: "this month",
            resolvedRangeHint: monthRange(),
            periodUnitHint: .month
        )
    }

    private func turnContext(
        _ fixture: MarinaPhase5Fixture,
        cardNames: [String] = ["Apple Card", "Backup Card"],
        categoryNames: [String] = ["Groceries", "Travel"],
        presetTitles: [String] = [],
        budgetNames: [String] = [],
        allocationAccountNames: [String] = [],
        turnClassification: MarinaPromptTurnClassification = .freshQuestion
    ) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: fixture.provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: cardNames,
                categoryNames: categoryNames,
                incomeSourceNames: [],
                presetTitles: presetTitles,
                budgetNames: budgetNames,
                allocationAccountNames: allocationAccountNames,
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: date(2026, 5, 15),
            turnClassification: turnClassification
        )
    }

    private func monthRange() -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31)
        )
    }

    private func spaced(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
            .lowercased()
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct AvailableMarinaModel: MarinaModelAvailabilityProviding {
        func currentStatus() -> MarinaModelAvailability.Status { .available }
    }
}
