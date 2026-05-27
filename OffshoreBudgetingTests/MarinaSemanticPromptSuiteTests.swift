import Foundation
import SwiftData
import Testing
@testable import Offshore

@Suite(.serialized)
@MainActor
struct MarinaSemanticPromptSuiteTests {
    private struct PromptCase {
        let prompt: String
        let entity: MarinaSemanticEntity
        let operation: MarinaSemanticOperation
        let measure: MarinaSemanticMeasure?
        let shape: MarinaSemanticAnswerShape
        let source: MarinaSemanticSource = .ruleBased
        let confidence: MarinaSemanticConfidence = .high
    }

    private struct AnswerCase {
        let prompt: String
        let kind: HomeAnswerKind
    }

    private struct Fixture {
        let context: ModelContext
        let workspace: Workspace
        let currentRange: HomeQueryDateRange
        let now: Date
    }

    @Test func promptSuite_parsesIntoUniversalSemanticRequests() throws {
        let interpreter = MarinaRuleBasedInterpreter()
        let planner = MarinaQueryPlanner()
        let cases: [PromptCase] = [
            .init(prompt: "What workspace am I in?", entity: .workspace, operation: .list, measure: .name, shape: .metric),
            .init(prompt: "What is the name of this workspace?", entity: .workspace, operation: .list, measure: .name, shape: .metric),
            .init(prompt: "What is this workspace's color?", entity: .workspace, operation: .list, measure: .color, shape: .metric),
            .init(prompt: "What is my top category this month?", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What preset is due next?", entity: .preset, operation: .next, measure: .plannedAmount, shape: .metric),
            .init(prompt: "What presets have an actual amount greater than 0 this month?", entity: .preset, operation: .list, measure: .actualAmount, shape: .list),
            .init(prompt: "Which category has the most presets assigned to it?", entity: .preset, operation: .group, measure: .plannedAmount, shape: .list),
            .init(prompt: "How many cards do I have?", entity: .card, operation: .count, measure: nil, shape: .metric),
            .init(prompt: "What is my Apple Card spend this month?", entity: .card, operation: .sum, measure: .budgetImpact, shape: .metric),
            .init(prompt: "Compare Apple Card spend to Chase spend", entity: .card, operation: .compare, measure: .budgetImpact, shape: .comparison),
            .init(prompt: "What is my Target spend this month?", entity: .variableExpense, operation: .sum, measure: .budgetImpact, shape: .metric),
            .init(prompt: "When did I last go shopping at Target?", entity: .variableExpense, operation: .last, measure: .budgetImpact, shape: .metric),
            .init(prompt: "List my most recent 5 expenses on Apple Card", entity: .variableExpense, operation: .list, measure: .budgetImpact, shape: .list),
            .init(prompt: "What is Alejandro's balance for the current period?", entity: .reconciliationAccount, operation: .sum, measure: .reconciliationBalance, shape: .metric),
            .init(prompt: "How much did Alejandro spend on Groceries for the current period?", entity: .reconciliationAccount, operation: .sum, measure: .reconciliationBalance, shape: .metric),
            .init(prompt: "What is my current Savings Account balance?", entity: .savingsAccount, operation: .sum, measure: .savingsTotal, shape: .metric),
            .init(prompt: "What is my projected savings for the current period?", entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, shape: .metric),
            .init(prompt: "What is my actual income for this month?", entity: .income, operation: .sum, measure: .incomeAmount, shape: .metric),
            .init(prompt: "Compare my actual income this month to last month. Am I up or down?", entity: .income, operation: .compare, measure: .incomeAmount, shape: .comparison),
            .init(prompt: "What is my Actual Income to Planned Income percentage?", entity: .income, operation: .share, measure: .incomeAmount, shape: .metric),
            .init(prompt: "How is my budget for this period?", entity: .budget, operation: .forecast, measure: .budgetImpact, shape: .metric),
            .init(prompt: "Compare this budget period to last period.", entity: .budget, operation: .compare, measure: .budgetImpact, shape: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", entity: .budget, operation: .whatIf, measure: .remainingRoom, shape: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", entity: .budget, operation: .whatIf, measure: .savingsTotal, shape: .comparison)
        ]

        for testCase in cases {
            let interpreted = interpreter.interpretWithConfidence(testCase.prompt)
            let request = interpreted.request
            let plan = planner.plan(
                request: request,
                ambientDateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
                defaultBudgetingPeriod: .monthly,
                now: date(2026, 4, 20)
            )
            #expect(interpreted.source == testCase.source, "Source mismatch for \(testCase.prompt)")
            #expect(interpreted.confidence == testCase.confidence, "Confidence mismatch for \(testCase.prompt)")
            #expect(request.entity == testCase.entity, "Entity mismatch for \(testCase.prompt)")
            #expect(request.operation == testCase.operation, "Operation mismatch for \(testCase.prompt)")
            #expect(request.measure == testCase.measure, "Measure mismatch for \(testCase.prompt)")
            #expect(request.expectedAnswerShape == testCase.shape, "Shape mismatch for \(testCase.prompt)")
            #expect(plan.entity == testCase.entity, "Plan entity mismatch for \(testCase.prompt)")
            #expect(plan.operation == testCase.operation, "Plan operation mismatch for \(testCase.prompt)")
        }
    }

    @Test func promptSuite_executesEveryInAppQuestionPhrase() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let cases: [AnswerCase] = [
            .init(prompt: "What workspace am I in?", kind: .metric),
            .init(prompt: "What is the name of this workspace?", kind: .metric),
            .init(prompt: "What is this workspace's color?", kind: .metric),
            .init(prompt: "What is my top category this month?", kind: .list),
            .init(prompt: "What preset is due next?", kind: .metric),
            .init(prompt: "What presets have an actual amount greater than 0 this month?", kind: .list),
            .init(prompt: "Which category has the most presets assigned to it?", kind: .list),
            .init(prompt: "How many cards do I have?", kind: .metric),
            .init(prompt: "What is my Apple Card spend this month?", kind: .metric),
            .init(prompt: "Compare Apple Card spend to Chase spend", kind: .comparison),
            .init(prompt: "What is my Target spend this month?", kind: .metric),
            .init(prompt: "When did I last go shopping at Target?", kind: .metric),
            .init(prompt: "List my most recent 5 expenses on Apple Card", kind: .list),
            .init(prompt: "What is Alejandro's balance for the current period?", kind: .metric),
            .init(prompt: "How much did Alejandro spend on Groceries for the current period?", kind: .metric),
            .init(prompt: "What is my current Savings Account balance?", kind: .metric),
            .init(prompt: "What is my projected savings for the current period?", kind: .metric),
            .init(prompt: "What is my actual income for this month?", kind: .metric),
            .init(prompt: "Compare my actual income this month to last month. Am I up or down?", kind: .comparison),
            .init(prompt: "What is my Actual Income to Planned Income percentage?", kind: .metric),
            .init(prompt: "How is my budget for this period?", kind: .list),
            .init(prompt: "Compare this budget period to last period.", kind: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", kind: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", kind: .comparison)
        ]

        for testCase in cases {
            let answer = await answer(testCase.prompt, using: brain, fixture: fixture)
            #expect(answer.kind == testCase.kind, "Answer kind mismatch for \(testCase.prompt): \(answer.title)")
            #expect(answer.title.isEmpty == false, "Missing title for \(testCase.prompt)")
        }
    }

    @Test func promptSuite_plansAndExecutesRepresentativeAnswers() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let cardCount = await answer("How many cards do I have?", using: brain, fixture: fixture)
        #expect(cardCount.kind == .metric)
        #expect(cardCount.primaryValue == "2")

        let appleSpend = await answer("What is my Apple Card spend this month?", using: brain, fixture: fixture)
        #expect(appleSpend.kind == .metric)
        #expect((appleSpend.primaryValue ?? "").contains("1,330") || (appleSpend.primaryValue ?? "").contains("1330"))

        let targetLast = await answer("When did I last go shopping at Target?", using: brain, fixture: fixture)
        #expect(targetLast.kind == .metric)
        #expect(targetLast.rows.contains(where: { $0.title.contains("Target") }))

        let reconciliation = await answer("What is Alejandro's balance for the current period?", using: brain, fixture: fixture)
        #expect(reconciliation.kind == .metric)
        #expect((reconciliation.primaryValue ?? "").contains("40"))

        let monthlyReconciliation = await answer("What is Alejandro's balance for the current month?", using: brain, fixture: fixture)
        #expect(monthlyReconciliation.kind == .metric)
        #expect((monthlyReconciliation.primaryValue ?? "").contains("40"))

        let allTimeReconciliation = await answer("What is Alejandro's balance?", using: brain, fixture: fixture)
        #expect(allTimeReconciliation.kind == .metric)
        #expect((allTimeReconciliation.primaryValue ?? "").contains("50"))

        let reconciliationSpend = await answer("How much did Alejandro spend on Groceries for the current period?", using: brain, fixture: fixture)
        #expect(reconciliationSpend.kind == .metric)
        #expect((reconciliationSpend.primaryValue ?? "").contains("40"))

        let presetCategory = await answer("What presets are tied to Groceries?", using: brain, fixture: fixture)
        #expect(presetCategory.kind == .list)
        #expect(presetCategory.rows.contains(where: { $0.title == "Grocery Envelope" }))

        let savingsMonth = await answer("What is my Savings Account balance this month?", using: brain, fixture: fixture)
        #expect(savingsMonth.kind == .metric)
        #expect(savingsMonth.title.contains("Savings Account"))

        let incomeShare = await answer("What is my Actual Income to Planned Income percentage?", using: brain, fixture: fixture)
        #expect(incomeShare.kind == .metric)
        #expect((incomeShare.primaryValue ?? "").contains("93"))

        let whatIf = await answer("If I spend $50 at Target, what happens to my safe spend?", using: brain, fixture: fixture)
        #expect(whatIf.kind == .comparison)
        #expect(whatIf.rows.contains(where: { $0.title == "Virtual spend" }))
    }

    @Test func promptSuite_negativeCasesStaySafe() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let interpreter = MarinaRuleBasedInterpreter()

        let ambiguous = interpreter.interpret("How much did I spend on Apple?")
        #expect(ambiguous.entity == .variableExpense)
        #expect(ambiguous.targetName == "Apple")

        let readOnly = await answer("Delete my Apple Card expense", using: brain, fixture: fixture)
        #expect(readOnly.kind == .message)
        #expect(readOnly.subtitle?.contains("read-only") == true)

        let unknown = await answer("What did I spend on Food?", using: brain, fixture: fixture)
        #expect(unknown.kind == .message)
        #expect(unknown.subtitle?.contains("could not find") == true)
    }

    @Test func clarification_appleMerchantOrCardStoresExecutableChoices() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)
        #expect(clarification.kind == .message)
        #expect(clarification.title == "Can you clarify?")

        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected clarification choices attachment.")
            return
        }

        #expect(choices.choices.map(\.title).contains("Apple Text"))
        #expect(choices.choices.map(\.title).contains("Apple Card"))

        let merchantChoice = try #require(choices.choice(matching: "merchant"))
        let merchantAnswer = await answer(merchantChoice.request, prompt: "merchant", using: brain, fixture: fixture)
        #expect(merchantAnswer.kind == .message)
        #expect(merchantAnswer.title == "No Results Found")
        #expect(merchantAnswer.subtitle?.contains("Apple") == true)
        let includesAppleSearchRow = merchantAnswer.rows.contains { row in
            row.title == "Search" && row.value == "Apple"
        }
        #expect(includesAppleSearchRow)
        guard case .clarificationChoices(let followUpChoices)? = merchantAnswer.attachment else {
            Issue.record("Expected no-results follow-up choice.")
            return
        }
        #expect(followUpChoices.choice(matching: "card")?.title == "Apple Card")

        let cardChoice = try #require(choices.choice(matching: "Apple Card"))
        let cardAnswer = await answer(cardChoice.request, prompt: "Apple Card", using: brain, fixture: fixture)
        #expect(cardAnswer.kind == .metric)
        #expect(cardAnswer.title == "Apple Card Spend")
    }

    @Test func resolver_groceryAmbiguityCreatesExecutableCategoryAndTextChoices() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("How much did I spend on Grocery?", using: brain, fixture: fixture)
        #expect(clarification.kind == .message)
        #expect(clarification.title == "Can you clarify?")

        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery clarification choices.")
            return
        }

        #expect(choices.choices.map(\.title).contains("Groceries Category"))
        #expect(choices.choices.map(\.title).contains("Grocery Text"))

        let categoryChoice = try #require(choices.choice(matching: "category"))
        let categoryAnswer = await answer(categoryChoice.request, prompt: "category", using: brain, fixture: fixture)
        #expect(categoryAnswer.kind == .metric)
        #expect(categoryAnswer.title == "Groceries Spend")
        #expect((categoryAnswer.primaryValue ?? "").contains("190"))

        let textChoice = try #require(choices.choice(matching: "text"))
        let textAnswer = await answer(textChoice.request, prompt: "text", using: brain, fixture: fixture)
        #expect(textAnswer.kind == .metric)
        #expect(textAnswer.title == "Grocery Spend")
        #expect((textAnswer.primaryValue ?? "").contains("190"))
    }

    @Test func resolver_showGroceryExpensesCanResolveCategoryOrExpenseTextLists() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("Show Grocery expenses", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery list clarification choices.")
            return
        }

        let categoryAnswer = await answer(try #require(choices.choice(matching: "category")).request, prompt: "category", using: brain, fixture: fixture)
        #expect(categoryAnswer.kind == .list)
        #expect(categoryAnswer.rows.contains(where: { $0.title == "Target groceries" }))
        #expect(categoryAnswer.rows.contains(where: { $0.title == "Grocery Envelope" }))

        let textAnswer = await answer(try #require(choices.choice(matching: "description")).request, prompt: "description", using: brain, fixture: fixture)
        #expect(textAnswer.kind == .list)
        #expect(textAnswer.rows.contains(where: { $0.title == "Target groceries" }))
        #expect(textAnswer.rows.contains(where: { $0.title == "Grocery Envelope" }))
    }

    @Test func capabilityMatrix_declaresEveryEntityAndRejectsInvalidShapes() throws {
        let registry = MarinaQueryCapabilityRegistry()

        for entity in MarinaSemanticEntity.allCases {
            #expect(registry.supportedOperations(for: entity).isEmpty == false, "Missing capabilities for \(entity.rawValue)")
        }

        #expect(registry.supports(entity: .budget, operation: .whatIf))
        #expect(registry.supports(entity: .income, operation: .share))
        #expect(registry.supports(entity: .preset, operation: .next))
        #expect(registry.supports(entity: .workspace, operation: .whatIf) == false)
    }

    @Test func clarification_merchantWithoutPendingContextDoesNotBecomeWorkspace() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let answer = await answer("merchant", using: brain, fixture: fixture)

        #expect(answer.title != "Current Workspace")
        #expect(answer.kind == .message)
    }

    @Test func merchantNoResultsAndMerchantMatchesUseDistinctCards() async throws {
        let noAppleFixture = try makeFixture(includeAppleMerchantExpense: false)
        let appleFixture = try makeFixture(includeAppleMerchantExpense: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            dateRangeToken: .currentPeriod,
            textQuery: "Apple",
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )

        let noResults = await answer(request, prompt: "merchant", using: brain, fixture: noAppleFixture)
        #expect(noResults.kind == .message)
        #expect(noResults.title == "No Results Found")
        #expect(noResults.primaryValue == nil)

        let metric = await answer(request, prompt: "merchant", using: brain, fixture: appleFixture)
        #expect(metric.kind == .metric)
        #expect(metric.title == "Apple Spend")
        #expect((metric.primaryValue ?? "").contains("300"))
    }

    @Test func clarificationChoices_persistResolvedStateAndCanBeCleared() throws {
        let suiteName = "MarinaSemanticPromptSuiteTests.clarificationChoices"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = MarinaConversationStore(userDefaults: defaults, storageKeyPrefix: "tests.marina.answers")
        let workspaceID = UUID()
        var choices = MarinaClarificationChoices(
            question: "Did you mean Apple as a merchant, or Apple Card?",
            choices: [
                MarinaClarificationChoice(
                    title: "Merchant",
                    aliases: ["merchant", "store", "vendor"],
                    request: MarinaSemanticRequest(
                        entity: .variableExpense,
                        operation: .sum,
                        measure: .budgetImpact,
                        dimensions: [.merchantText],
                        textQuery: "Apple",
                        expenseScope: .variable,
                        expectedAnswerShape: .metric
                    )
                )
            ]
        )

        let unresolved = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Can you clarify?",
            attachment: .clarificationChoices(choices)
        )
        store.saveAnswers([unresolved], workspaceID: workspaceID)

        let loaded = try #require(store.loadAnswers(workspaceID: workspaceID).first)
        guard case .clarificationChoices(let loadedChoices)? = loaded.attachment else {
            Issue.record("Expected persisted clarification choices.")
            return
        }
        #expect(loadedChoices.isResolved == false)
        #expect(loadedChoices.choice(matching: "vendor")?.title == "Merchant")

        choices.resolvedChoiceID = choices.choices[0].id
        let resolved = HomeAnswer(
            id: unresolved.id,
            queryID: unresolved.queryID,
            kind: unresolved.kind,
            title: unresolved.title,
            attachment: .clarificationChoices(choices),
            generatedAt: unresolved.generatedAt
        )
        store.saveAnswers([resolved], workspaceID: workspaceID)
        let reloaded = try #require(store.loadAnswers(workspaceID: workspaceID).first)
        guard case .clarificationChoices(let resolvedChoices)? = reloaded.attachment else {
            Issue.record("Expected persisted resolved clarification choices.")
            return
        }
        #expect(resolvedChoices.isResolved)

        store.saveAnswers([], workspaceID: workspaceID)
        #expect(store.loadAnswers(workspaceID: workspaceID).isEmpty)
    }

    @Test func hybrid_highConfidencePromptDoesNotCallModelInterpreter() async throws {
        let fixture = try makeFixture()
        let model = RecordingInterpreter(
            result: MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(entity: .income, operation: .sum, measure: .incomeAmount, expectedAnswerShape: .metric),
                confidence: .medium,
                source: .foundationModel
            )
        )
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: model)
        let context = brainContext(fixture)

        let interpreted = try await hybrid.interpretedSemanticRequest(for: "How many cards do I have?", context: context)

        #expect(interpreted.source == .ruleBased)
        #expect(interpreted.request.entity == .card)
        #expect(model.callCount == 0)
    }

    @Test func hybrid_lowConfidencePromptCallsModelInterpreter() async throws {
        let fixture = try makeFixture()
        let model = RecordingInterpreter(
            result: MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(entity: .income, operation: .sum, measure: .incomeAmount, expectedAnswerShape: .metric),
                confidence: .medium,
                source: .foundationModel
            )
        )
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: model)
        let context = brainContext(fixture)

        let interpreted = try await hybrid.interpretedSemanticRequest(for: "Did my paycheck vibe improve?", context: context)

        #expect(interpreted.source == .foundationModel)
        #expect(interpreted.request.entity == .income)
        #expect(model.callCount == 1)
    }

    @Test func validator_repairsFoundationModelMerchantSpendAndRejectsUnknownCategory() throws {
        let fixture = try makeFixture()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context)
        let validator = MarinaSemanticRequestValidator()
        let merchantAsCard = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .currentPeriod,
                targetName: "Target",
                expectedAnswerShape: .metric
            ),
            confidence: .medium,
            source: .foundationModel
        )

        let repaired = validator.validate(interpreted: merchantAsCard, snapshot: snapshot)
        #expect(repaired.source == .repairedFoundationModel)
        #expect(repaired.request.entity == .variableExpense)
        #expect(repaired.request.textQuery == "Target")

        let unknownCategory = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Food",
                expectedAnswerShape: .metric
            ),
            confidence: .high,
            source: .ruleBased
        )
        let rejected = validator.validate(interpreted: unknownCategory, snapshot: snapshot)
        #expect(rejected.request.expectedAnswerShape == .unsupported)
        #expect(rejected.request.unsupportedReason == .unresolvedEntity)
    }

    @Test func hybrid_modelUnavailableFallsBackCleanlyAndModelErrorsAreFriendly() async throws {
        let fixture = try makeFixture()
        let context = brainContext(fixture)
        let hybrid = MarinaHybridInterpreter(modelBackedInterpreter: nil)

        let unavailable = try await hybrid.interpretedSemanticRequest(for: "Is my paycheck vibe improving?", context: context)
        #expect(unavailable.source == .unavailableFallback)
        #expect(unavailable.request.unsupportedReason == .unavailableModel)

        let executor = MarinaQueryExecutor()
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .modelGuardrail
            ),
            dateRange: nil,
            comparisonDateRange: nil,
            now: fixture.now
        )
        let answer = executor.execute(plan: plan, snapshot: try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context))
        #expect(answer.kind == .message)
        #expect(answer.subtitle?.contains("declined") == true)
    }

    private func answer(_ prompt: String, using brain: MarinaBrain, fixture: Fixture) async -> HomeAnswer {
        await brain.answer(
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
    }

    private func answer(
        _ request: MarinaSemanticRequest,
        prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture
    ) async -> HomeAnswer {
        await brain.answer(
            resolvedRequest: request,
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
    }

    private func brainContext(_ fixture: Fixture) -> MarinaBrainContext {
        MarinaBrainContext(
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )
    }

    private final class RecordingInterpreter: MarinaModelInterpreting {
        private let result: MarinaInterpretedSemanticRequest
        private(set) var callCount = 0

        init(result: MarinaInterpretedSemanticRequest) {
            self.result = result
        }

        func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
            callCount += 1
            return result
        }
    }

    private func makeFixture(includeAppleMerchantExpense: Bool = true) throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#14B8A6")

        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chase = Card(name: "Chase", workspace: workspace)
        let otherAppleCard = Card(name: "Apple Card", workspace: otherWorkspace)

        let groceries = Category(name: "Groceries", hexColor: "#16A34A", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let bills = Category(name: "Bills", hexColor: "#2563EB", workspace: workspace)

        let currentBudget = Budget(
            name: "April 2026",
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30),
            workspace: workspace
        )
        let previousBudget = Budget(
            name: "March 2026",
            startDate: date(2026, 3, 1),
            endDate: date(2026, 3, 31),
            workspace: workspace
        )

        let rentPreset = Preset(
            title: "Rent",
            plannedAmount: 1_200,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: bills
        )
        let phonePreset = Preset(
            title: "Phone",
            plannedAmount: 90,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: bills
        )
        let groceryPreset = Preset(
            title: "Grocery Envelope",
            plannedAmount: 200,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: chase,
            defaultCategory: groceries
        )

        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            actualAmount: 1_200,
            expenseDate: date(2026, 4, 3),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourcePresetID: rentPreset.id,
            sourceBudgetID: currentBudget.id
        )
        let phone = PlannedExpense(
            title: "Phone",
            plannedAmount: 90,
            expenseDate: date(2026, 4, 25),
            workspace: workspace,
            card: appleCard,
            category: bills,
            sourcePresetID: phonePreset.id,
            sourceBudgetID: currentBudget.id
        )
        let groceriesPlan = PlannedExpense(
            title: "Grocery Envelope",
            plannedAmount: 200,
            actualAmount: 150,
            expenseDate: date(2026, 4, 8),
            workspace: workspace,
            card: chase,
            category: groceries,
            sourcePresetID: groceryPreset.id,
            sourceBudgetID: currentBudget.id
        )

        let targetApril = VariableExpense(
            descriptionText: "Target groceries",
            amount: 80,
            transactionDate: date(2026, 4, 10),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )
        let starbucks = VariableExpense(
            descriptionText: "Starbucks",
            amount: 25,
            transactionDate: date(2026, 4, 11),
            workspace: workspace,
            card: chase,
            category: dining
        )
        let appleStore = includeAppleMerchantExpense
            ? VariableExpense(
                descriptionText: "Apple Store",
                amount: 300,
                transactionDate: date(2026, 4, 13),
                workspace: workspace,
                card: chase,
                category: bills
            )
            : nil
        let targetMarch = VariableExpense(
            descriptionText: "Target groceries",
            amount: 45,
            transactionDate: date(2026, 3, 12),
            workspace: workspace,
            card: appleCard,
            category: groceries
        )

        let actualPaycheck = Income(source: "Paycheck", amount: 3_000, date: date(2026, 4, 1), isPlanned: false, workspace: workspace)
        let plannedPaycheck = Income(source: "Paycheck", amount: 3_200, date: date(2026, 4, 1), isPlanned: true, workspace: workspace)
        let previousPaycheck = Income(source: "Paycheck", amount: 2_800, date: date(2026, 3, 1), isPlanned: false, workspace: workspace)

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
        let savingsAdjustment = SavingsLedgerEntry(
            date: date(2026, 4, 15),
            amount: 100,
            note: "Manual savings",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savings
        )

        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let targetAllocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: targetApril
        )
        let previousAllocation = ExpenseAllocation(
            allocatedAmount: 20,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: targetMarch
        )
        let settlement = AllocationSettlement(
            date: date(2026, 4, 20),
            note: "Alejandro paid back",
            amount: -10,
            workspace: workspace,
            account: alejandro
        )
        targetApril.allocation = targetAllocation
        targetMarch.allocation = previousAllocation
        alejandro.expenseAllocations = [targetAllocation, previousAllocation]
        alejandro.settlements = [settlement]

        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(appleCard)
        context.insert(chase)
        context.insert(otherAppleCard)
        context.insert(groceries)
        context.insert(dining)
        context.insert(bills)
        context.insert(currentBudget)
        context.insert(previousBudget)
        context.insert(rentPreset)
        context.insert(phonePreset)
        context.insert(groceryPreset)
        context.insert(rent)
        context.insert(phone)
        context.insert(groceriesPlan)
        context.insert(targetApril)
        context.insert(starbucks)
        if let appleStore {
            context.insert(appleStore)
        }
        context.insert(targetMarch)
        context.insert(actualPaycheck)
        context.insert(plannedPaycheck)
        context.insert(previousPaycheck)
        context.insert(savings)
        context.insert(savingsAdjustment)
        context.insert(alejandro)
        context.insert(targetAllocation)
        context.insert(previousAllocation)
        context.insert(settlement)
        try context.save()

        return Fixture(
            context: context,
            workspace: workspace,
            currentRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            now: date(2026, 4, 20)
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            IncomeSeries.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
