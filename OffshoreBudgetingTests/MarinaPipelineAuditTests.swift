import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaPipelineAuditTests {
    @Test func failingPromptsRecoverThroughAuditedPipelineWithoutDroppingTargets() async throws {
        let fixture = try AuditFixture.make()
        let prompts: [AuditExpectation] = [
            .init(
                prompt: "What is my top category this month?",
                titleContains: "Categor",
                textContains: ["Groceries"],
                amountBasis: .budgetImpact,
                rowObjectTypes: [.category]
            ),
            .init(
                prompt: "What preset is due next?",
                titleContains: "Next Planned Expense",
                textContains: ["Rent", "5/20/26"],
                amountBasis: .plannedEffectiveAmount,
                rowObjectTypes: [.plannedExpense]
            ),
            .init(
                prompt: "Which presets have an actual amount greater than 0 this month?",
                titleContains: "Recorded Preset Actuals",
                textContains: ["Grocery Box", "$75.00"],
                amountBasis: .recordedActualAmount,
                rowObjectTypes: [.plannedExpense]
            ),
            .init(
                prompt: "Which category has the most presets assigned to it?",
                titleContains: "Preset Count by Category",
                textContains: ["Groceries", "2 presets"],
                amountBasis: .count,
                rowObjectTypes: [.category]
            ),
            .init(
                prompt: "How many cards do I have?",
                titleContains: "Cards",
                textContains: ["Apple Card", "Chase", "2"],
                amountBasis: .count,
                rowObjectTypes: [.card]
            ),
            .init(
                prompt: "What is my Apple Card spend this month?",
                titleContains: "Spending",
                textContains: ["Apple Card", "$"],
                amountBasis: .budgetImpact,
                forbiddenText: ["Chase Grocery"]
            ),
            .init(
                prompt: "Compare Apple Card spend to Chase spend",
                titleContains: "Card Spend Comparison",
                textContains: ["Apple Card", "Chase", "Difference"],
                amountBasis: .budgetImpact,
                rowObjectTypes: [.card]
            ),
            .init(
                prompt: "When did I last go shopping at Target?",
                titleContains: "Recent Purchases",
                textContains: ["Target"],
                amountBasis: .budgetImpact,
                rowObjectTypes: [.variableExpense]
            ),
            .init(
                prompt: "List my most recent 5 expenses on Apple Card",
                titleContains: "Recent Purchases",
                textContains: ["Apple Card", "Target"],
                amountBasis: .budgetImpact,
                rowObjectTypes: [.variableExpense]
            ),
            .init(
                prompt: "How much did Alejandro spend on Groceries for the current period?",
                titleContains: "Alejandro Allocated Spend",
                textContains: ["Groceries", "$30.00"],
                amountBasis: .allocated,
                rowObjectTypes: [.variableExpense]
            ),
            .init(
                prompt: "Compare my actual income this month to last month. Am I up or down?",
                titleContains: "Income Comparison",
                textContains: ["Current period", "Previous period", "$3,100.00"],
                amountBasis: .actualIncome
            ),
            .init(
                prompt: "Compare this budget period to last period",
                titleContains: "Budget Period Comparison",
                textContains: ["Current period", "Previous period", "Change"],
                amountBasis: .budgetImpact
            )
        ]

        let coordinator = MarinaTurnCoordinator(
            availability: FakeAuditAvailability(status: .available),
            turnInterpreter: ScriptedAuditTurnInterpreter(
                interpretationsByPrompt: Dictionary(uniqueKeysWithValues: prompts.map {
                    ($0.prompt, malformedTokenizedTurnInterpretation())
                })
            )
        )

        for expectation in prompts {
            let result = await coordinator.run(
                prompt: expectation.prompt,
                context: fixture.turnContext()
            )

            guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
                Issue.record("Expected handled audit result for \(expectation.prompt).")
                continue
            }

            let text = answerText(answer)
            #expect(answer.title.localizedCaseInsensitiveContains(expectation.titleContains))
            for expected in expectation.textContains {
                #expect(text.localizedCaseInsensitiveContains(expected), "Missing '\(expected)' for \(expectation.prompt): \(text)")
            }
            for forbidden in expectation.forbiddenText {
                #expect(text.localizedCaseInsensitiveContains(forbidden) == false, "Dropped/overbroadened target for \(expectation.prompt): \(text)")
            }
            #expect(text.localizedCaseInsensitiveContains("narrower") == false)
            #expect(text.localizedCaseInsensitiveContains("could not read") == false)
            #expect(text.localizedCaseInsensitiveContains("couldn't safely resolve") == false)
            #expect(amountBasis == expectation.amountBasis, "Wrong amount basis for \(expectation.prompt)")
            #expect(route != nil)
            if expectation.rowObjectTypes.isEmpty == false {
                let objectTypes = Set(answer.rows.compactMap(\.objectType))
                #expect(expectation.rowObjectTypes.allSatisfy { objectTypes.contains($0) }, "Wrong row object types for \(expectation.prompt): \(objectTypes)")
            }
        }
    }

    @Test func decodingFailureUsesAuditOnlyWhenItCanPreserveExplicitTargets() async throws {
        let fixture = try AuditFixture.make()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .decodingFailure,
            step: .typedEnvelope,
            debugSummary: "scripted decoding failure"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeAuditAvailability(status: .available),
            interpreter: ThrowingAuditCanonicalInterpreter(
                error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic)
            )
        )

        let result = await coordinator.run(
            prompt: "Compare Apple Card spend to Chase spend",
            context: fixture.turnContext()
        )

        guard case .handled(let answer, _, _, let amountBasis, _) = result else {
            Issue.record("Expected audited decoding-failure recovery for card comparison.")
            return
        }

        #expect(answer.title == "Card Spend Comparison")
        #expect(answerText(answer).contains("Apple Card"))
        #expect(answerText(answer).contains("Chase"))
        #expect(amountBasis == .budgetImpact)
    }

    @Test func promptBackedPresetSuggestionUsesAuditPathWithoutDroppingTargets() async throws {
        let fixture = try AuditFixture.make()
        let presetContext = MarinaPresetPromptContext(
            budgetNames: ["May Budget"],
            cardNames: ["Apple Card", "Chase"],
            categoryNames: ["Groceries", "Utilities"],
            presetTitles: ["Grocery Box", "Market Trip", "Rent"],
            incomeSourceNames: ["Salary"],
            savingsAccountNames: [],
            allocationAccountNames: ["Alejandro"],
            supportsPromptBackedSuggestions: true
        )
        let suggestion = MarinaPresetPromptCatalog.suggestions(
            for: .accounts,
            defaultPeriodUnit: .month,
            context: presetContext
        )
        .first { $0.promptText == "Show expenses on Apple Card." }

        guard let suggestion,
              case .freeformPrompt(let promptText) = suggestion.action else {
            Issue.record("Expected prompt-backed Apple Card suggestion to execute as freeform text.")
            return
        }

        let coordinator = MarinaTurnCoordinator(
            availability: FakeAuditAvailability(status: .available),
            turnInterpreter: ScriptedAuditTurnInterpreter(
                interpretationsByPrompt: [promptText: malformedTokenizedTurnInterpretation()]
            )
        )

        let result = await coordinator.run(
            prompt: suggestion.executionPrompt,
            context: fixture.turnContext()
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected prompt-backed preset suggestion to recover through audited pipeline.")
            return
        }

        let text = answerText(answer)
        #expect(answer.title.localizedCaseInsensitiveContains("Recent Purchases"))
        #expect(text.localizedCaseInsensitiveContains("Apple Card"))
        #expect(text.localizedCaseInsensitiveContains("Target"))
        #expect(text.localizedCaseInsensitiveContains("Chase Grocery") == false)
        #expect(amountBasis == .budgetImpact)
        #expect(route != nil)
    }

    private struct AuditExpectation {
        let prompt: String
        let titleContains: String
        let textContains: [String]
        let amountBasis: MarinaFinancialAmountBasis
        var forbiddenText: [String] = []
        var rowObjectTypes: Set<MarinaLookupObjectType> = []
    }

    private func malformedTokenizedTurnInterpretation() -> MarinaTurnInterpretation {
        MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Apple Intelligence returned model tokens Marina could not safely validate."
                )
            ),
            repairSummary: "tokenizedReadRequest:malformed",
            generatedSchemaName: MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
        )
    }
}

@MainActor
private struct AuditFixture {
    let context: ModelContext
    let workspace: Workspace
    let groceries: Offshore.Category
    let utilities: Offshore.Category
    let appleCard: Card
    let chase: Card
    let provider: MarinaDataProvider

    static func make() throws -> AuditFixture {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            Card.self,
            BudgetCardLink.self,
            Offshore.Category.self,
            Preset.self,
            BudgetPresetLink.self,
            BudgetCategoryLimit.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            IncomeSeries.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            Income.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self
        ])
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)

        let workspace = Workspace(name: "Audit Workspace", hexColor: "#3B82F6")
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let utilities = Offshore.Category(name: "Utilities", hexColor: "#F59E0B", workspace: workspace)
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chase = Card(name: "Chase", workspace: workspace)
        let budget = Budget(
            name: "May Budget",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            workspace: workspace
        )
        let previousBudget = Budget(
            name: "April Budget",
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30),
            workspace: workspace
        )
        let groceryBox = Preset(title: "Grocery Box", plannedAmount: 75, workspace: workspace, defaultCard: appleCard, defaultCategory: groceries)
        let marketTrip = Preset(title: "Market Trip", plannedAmount: 40, workspace: workspace, defaultCard: chase, defaultCategory: groceries)
        let rent = Preset(title: "Rent", plannedAmount: 1_200, workspace: workspace, defaultCard: appleCard, defaultCategory: utilities)
        let alejandro = AllocationAccount(name: "Alejandro", hexColor: "#14B8A6", workspace: workspace)

        context.insert(workspace)
        context.insert(groceries)
        context.insert(utilities)
        context.insert(appleCard)
        context.insert(chase)
        context.insert(budget)
        context.insert(previousBudget)
        context.insert(groceryBox)
        context.insert(marketTrip)
        context.insert(rent)
        context.insert(alejandro)
        context.insert(BudgetCardLink(budget: budget, card: appleCard))
        context.insert(BudgetCardLink(budget: budget, card: chase))
        context.insert(BudgetPresetLink(budget: budget, preset: groceryBox))
        context.insert(BudgetPresetLink(budget: budget, preset: marketTrip))
        context.insert(BudgetPresetLink(budget: budget, preset: rent))

        let rentDue = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 5, 20),
            workspace: workspace,
            card: appleCard,
            category: utilities,
            sourcePresetID: rent.id,
            sourceBudgetID: budget.id
        )
        let groceryActual = PlannedExpense(
            title: "Grocery Box",
            plannedAmount: 75,
            actualAmount: 75,
            expenseDate: date(2026, 5, 5),
            workspace: workspace,
            card: appleCard,
            category: groceries,
            sourcePresetID: groceryBox.id,
            sourceBudgetID: budget.id
        )
        let marketActual = PlannedExpense(
            title: "Market Trip",
            plannedAmount: 40,
            actualAmount: 40,
            expenseDate: date(2026, 5, 8),
            workspace: workspace,
            card: chase,
            category: groceries,
            sourcePresetID: marketTrip.id,
            sourceBudgetID: budget.id
        )
        let target = VariableExpense(
            descriptionText: "Target",
            amount: 45,
            transactionDate: date(2026, 5, 14),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let appleStore = VariableExpense(
            descriptionText: "Apple Store",
            amount: 120,
            transactionDate: date(2026, 5, 10),
            workspace: workspace,
            card: appleCard,
            category: utilities
        )
        let chaseGrocery = VariableExpense(
            descriptionText: "Chase Grocery",
            amount: 80,
            transactionDate: date(2026, 5, 11),
            workspace: workspace,
            card: chase,
            category: groceries
        )
        let sharedGroceries = VariableExpense(
            descriptionText: "Shared Groceries",
            amount: 60,
            transactionDate: date(2026, 5, 12),
            workspace: workspace,
            card: chase,
            category: groceries
        )
        let aprilSpend = VariableExpense(
            descriptionText: "April Spend",
            amount: 50,
            transactionDate: date(2026, 4, 12),
            workspace: workspace,
            card: chase,
            category: utilities
        )

        context.insert(rentDue)
        context.insert(groceryActual)
        context.insert(marketActual)
        context.insert(target)
        context.insert(appleStore)
        context.insert(chaseGrocery)
        context.insert(sharedGroceries)
        context.insert(aprilSpend)
        context.insert(
            ExpenseAllocation(
                allocatedAmount: 30,
                preservesGrossAmount: true,
                workspace: workspace,
                account: alejandro,
                expense: sharedGroceries
            )
        )
        context.insert(Income(source: "Salary", amount: 3_100, date: date(2026, 5, 3), isPlanned: false, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 2_500, date: date(2026, 4, 3), isPlanned: false, workspace: workspace))
        try context.save()

        return AuditFixture(
            context: context,
            workspace: workspace,
            groceries: groceries,
            utilities: utilities,
            appleCard: appleCard,
            chase: chase,
            provider: MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        )
    }

    func turnContext() -> MarinaTurnContext {
        MarinaTurnContext(
            provider: provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: [appleCard.name, chase.name],
                categoryNames: [groceries.name, utilities.name],
                incomeSourceNames: ["Salary"],
                presetTitles: ["Grocery Box", "Market Trip", "Rent"],
                budgetNames: ["May Budget", "April Budget"],
                allocationAccountNames: ["Alejandro"],
                aliasSummaries: [],
                now: Self.date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: Self.date(2026, 5, 15)
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct FakeAuditAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct ScriptedAuditTurnInterpreter: MarinaTurnIntentInterpreting {
    enum Failure: Error {
        case missingPrompt(String)
    }

    let interpretationsByPrompt: [String: MarinaTurnInterpretation]

    func interpretTurnIntent(
        prompt: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaTurnInterpretation {
        guard let interpretation = interpretationsByPrompt[prompt] else {
            throw Failure.missingPrompt(prompt)
        }
        return interpretation
    }
}

private struct ThrowingAuditCanonicalInterpreter: MarinaCanonicalAIInterpreting {
    let error: Error

    func interpretCanonical(
        prompt _: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        throw error
    }
}

private func answerText(_ answer: HomeAnswer) -> String {
    ([answer.title, answer.subtitle, answer.primaryValue].compactMap { $0 } + answer.rows.flatMap { [$0.title, $0.value] })
        .joined(separator: " ")
}
