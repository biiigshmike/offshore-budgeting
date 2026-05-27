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
            .init(prompt: "How is my income progress?", entity: .income, operation: .share, measure: .incomeAmount, shape: .metric),
            .init(prompt: "How is my budget for this period?", entity: .budget, operation: .forecast, measure: .budgetImpact, shape: .metric),
            .init(prompt: "What is my safe spend today?", entity: .budget, operation: .forecast, measure: .remainingRoom, shape: .metric),
            .init(prompt: "Compare this budget period to last period.", entity: .budget, operation: .compare, measure: .budgetImpact, shape: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", entity: .budget, operation: .whatIf, measure: .remainingRoom, shape: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", entity: .budget, operation: .whatIf, measure: .savingsTotal, shape: .comparison),
            .init(prompt: "Show my savings outlook.", entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, shape: .metric),
            .init(prompt: "Show category availability.", entity: .category, operation: .forecast, measure: .categoryAvailability, shape: .metric),
            .init(prompt: "Show category spotlight.", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What are my spend trends?", entity: .category, operation: .group, measure: .budgetImpact, shape: .list),
            .init(prompt: "What is my next planned expense?", entity: .plannedExpense, operation: .next, measure: .effectiveAmount, shape: .metric),
            .init(prompt: "Summarize my Apple Card.", entity: .card, operation: .sum, measure: .budgetImpact, shape: .metric)
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
            .init(prompt: "How is my income progress?", kind: .metric),
            .init(prompt: "How is my budget for this period?", kind: .list),
            .init(prompt: "What is my safe spend today?", kind: .metric),
            .init(prompt: "Compare this budget period to last period.", kind: .comparison),
            .init(prompt: "If I spend $50 at Target, what happens to my safe spend?", kind: .comparison),
            .init(prompt: "If I spend $200 on Groceries, what happens to projected savings?", kind: .comparison),
            .init(prompt: "Show my savings outlook.", kind: .metric),
            .init(prompt: "Show category availability.", kind: .metric),
            .init(prompt: "Show category spotlight.", kind: .list),
            .init(prompt: "What are my spend trends?", kind: .list),
            .init(prompt: "What is my next planned expense?", kind: .metric),
            .init(prompt: "Summarize my Apple Card.", kind: .metric)
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
        #expect((appleSpend.primaryValue ?? "").contains("1,370") || (appleSpend.primaryValue ?? "").contains("1370"))
        #expect(appleSpend.rows.contains(where: { $0.title == "Planned" }))
        #expect(appleSpend.rows.contains(where: { $0.title == "Variable" }))

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
        #expect(savingsMonth.title == "Savings Status")

        let incomeShare = await answer("What is my Actual Income to Planned Income percentage?", using: brain, fixture: fixture)
        #expect(incomeShare.kind == .metric)
        #expect((incomeShare.primaryValue ?? "").contains("93"))

        let whatIf = await answer("If I spend $50 at Target, what happens to my safe spend?", using: brain, fixture: fixture)
        #expect(whatIf.kind == .comparison)
        #expect((whatIf.primaryValue ?? "").contains("113.18"))
        #expect(whatIf.rows.contains(where: { $0.title == "Current safe spend today" }))
        #expect(whatIf.rows.contains(where: { $0.title == "Virtual spend" }))
        let safeSpendAfter = whatIf.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        let periodRoomAfter = whatIf.rows.first(where: { $0.title == "Period room after" })?.amount
        #expect(abs(safeSpendAfter - 113.18181818181819) < 0.0001)
        #expect(periodRoomAfter == 1_245)

        let categoryAvailability = await answer("Show category availability.", using: brain, fixture: fixture)
        #expect(categoryAvailability.kind == .metric)
        #expect(categoryAvailability.title == "Category Availability")
        let categoryAvailabilityHasOverRow = categoryAvailability.rows.contains { row in
            row.title == "Over" && row.value == "0"
        }
        #expect(categoryAvailabilityHasOverRow)

        let nextPlanned = await answer("What is my next planned expense?", using: brain, fixture: fixture)
        #expect(nextPlanned.kind == .metric)
        let nextPlannedHasExpenseRow = nextPlanned.rows.contains { row in
            row.title == "Expense" && row.value == "Phone"
        }
        #expect(nextPlannedHasExpenseRow)
    }

    @Test func resolver_cardSummaryPhrasesResolveSameWorkspaceCardTarget() async throws {
        let fixture = try makeFixture(includeDebitCard: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let prompts = [
            "Summarize my Debit Card.",
            "Debit Card spend",
            "What is my Debit Card spend this period?"
        ]

        for prompt in prompts {
            let cardAnswer = await answer(prompt, using: brain, fixture: fixture)
            #expect(cardAnswer.kind == .metric, "Expected metric for \(prompt), got \(cardAnswer.kind)")
            #expect(cardAnswer.title == "Debit Card Spend", "Wrong title for \(prompt): \(cardAnswer.title)")
            #expect(cardAnswer.primaryValue == CurrencyFormatter.string(from: 100), "Wrong value for \(prompt): \(cardAnswer.primaryValue ?? "nil")")
            let hasPlannedRow = cardAnswer.rows.contains { row in
                row.title == "Planned" && row.amount == 70
            }
            let hasVariableRow = cardAnswer.rows.contains { row in
                row.title == "Variable" && row.amount == 30
            }
            #expect(hasPlannedRow)
            #expect(hasVariableRow)
        }
    }

    @Test func resolver_phraseInvarianceWorksAcrossNonHardcodedEntityTypes() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let transportation = await answer("Summarize my Transportation.", using: brain, fixture: fixture)
        #expect(transportation.kind == .metric)
        #expect(transportation.title == "Transportation Spend")
        #expect((transportation.primaryValue ?? "").contains("60"))

        let paycheck = await answer("Paycheck income", using: brain, fixture: fixture)
        #expect(paycheck.kind == .metric)
        #expect(paycheck.title == "Paycheck Income")
        #expect((paycheck.primaryValue ?? "").contains("6,200") || (paycheck.primaryValue ?? "").contains("6200"))

        let savings = await answer("Summarize my Savings Account.", using: brain, fixture: fixture)
        #expect(savings.kind == .metric)
        #expect(savings.title == "Savings Account Balance")

        let balance = await answer("Alejandro balance", using: brain, fixture: fixture)
        #expect(balance.kind == .metric)
        #expect(balance.title == "Alejandro Balance")

        let merchant = await answer("Target spend", using: brain, fixture: fixture)
        #expect(merchant.kind == .metric)
        #expect(merchant.title == "Target groceries Spend")
        #expect((merchant.primaryValue ?? "").contains("40"))

        let preset = await answer("Summarize my Phone preset.", using: brain, fixture: fixture)
        #expect(preset.kind == .metric)
        #expect(preset.title == "Phone Preset")
        #expect(preset.primaryValue == CurrencyFormatter.string(from: 90))

        let budget = await answer("Summarize my April 2026 budget.", using: brain, fixture: fixture)
        #expect(budget.kind == .list)
        #expect(budget.title == "Budget Overview")
        #expect(budget.subtitle?.isEmpty == false)
    }

    @Test func resolver_unknownNamedTargetNeverFallsBackToAggregate() async throws {
        let fixture = try makeFixture(includeDebitCard: false)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let answer = await answer("Summarize my Debit Card.", using: brain, fixture: fixture)

        #expect(answer.kind == .message)
        #expect(answer.title == "I can't answer that yet")
        #expect(answer.subtitle?.contains("could not find") == true)
        #expect(answer.title != "Card Spend")
    }

    @Test func resolver_incomeComparisonDoesNotInventSourceFromComparisonWords() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let interpreter = MarinaRuleBasedInterpreter()
        let prompt = "Compare my actual income this month to last month. Am I up or down?"

        let interpreted = interpreter.interpret(prompt)
        #expect(interpreted.entity == .income)
        #expect(interpreted.operation == .compare)
        #expect(interpreted.targetName == nil)
        #expect(interpreted.dimensions.contains(.incomeSource) == false)

        let answer = await answer(prompt, using: brain, fixture: fixture)
        #expect(answer.kind == .comparison)
        #expect(answer.title == "Income Comparison")
    }

    @Test func starterPromptFactoryUsesWorkspaceCardsWithoutHardcodedAppleCard() throws {
        let noCardPrompts = MarinaStarterPromptFactory.promptPool(cardNames: [])
        #expect(noCardPrompts.contains("Summarize my Apple Card.") == false)

        let debitPrompts = MarinaStarterPromptFactory.promptPool(cardNames: ["Debit Card"])
        #expect(debitPrompts.contains("Summarize my Debit Card."))
        #expect(debitPrompts.contains("Summarize my Apple Card.") == false)
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
        #expect(readOnly.title == "I can't answer that yet")
        #expect(readOnly.subtitle?.contains("read-only") == true)
        #expect(readOnly.subtitle?.contains("I'm") == true)
        #expect(readOnly.subtitle?.contains("Marina") == false)

        let unknown = await answer("What did I spend on Food?", using: brain, fixture: fixture)
        #expect(unknown.kind == .message)
        #expect(unknown.subtitle?.contains("could not find") == true)
    }

    @Test func clarification_appleMerchantOrCardStoresExecutableChoices() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)
        #expect(clarification.kind == .message)
        #expect(clarification.title == "Can you clarify?")

        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected clarification choices attachment.")
            return
        }

        #expect(choices.choices.map(\.title).contains("Apple Store"))
        #expect(choices.choices.map(\.title).contains("Apple Card"))
        #expect(choices.choice(matching: "Apple Store")?.kindLabel == "Expense match")
        #expect(choices.choice(matching: "Apple Card")?.kindLabel == "Card")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let merchantChoice = try #require(choices.choice(matching: "merchant"))
        let merchantAnswer = await answer(merchantChoice.request, prompt: "merchant", using: brain, fixture: fixture)
        #expect(merchantAnswer.kind == .metric)
        #expect(merchantAnswer.title == "Apple Store Spend")
        #expect((merchantAnswer.primaryValue ?? "").contains("300"))

        let cardChoice = try #require(choices.choice(matching: "Apple Card"))
        let cardAnswer = await answer(cardChoice.request, prompt: "Apple Card", using: brain, fixture: fixture)
        #expect(cardAnswer.kind == .metric)
        #expect(cardAnswer.title == "Apple Card Spend")
    }

    @Test func resolver_appleCardOnlyDoesNotOfferSyntheticTextChoice() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let answer = await answer("How much did I spend on Apple?", using: brain, fixture: fixture)

        #expect(answer.kind == .metric)
        #expect(answer.title == "Apple Card Spend")
        #expect(answer.attachment == nil)
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

        #expect(choices.choices.map(\.title).contains("Groceries"))
        #expect(choices.choices.map(\.title).contains("Grocery Envelope"))
        #expect(choices.choices.map(\.title).contains("Target groceries"))
        #expect(choices.choices.map(\.title).contains("All expense matches for \"Grocery\""))
        #expect(choices.choice(matching: "category")?.kindLabel == "Category")
        #expect(choices.choice(matching: "Grocery Envelope")?.kindLabel == "Planned expense match")
        #expect(choices.choice(matching: "Target groceries")?.kindLabel == "Expense match")
        #expect(choices.choice(matching: "description")?.kindLabel == "Expense search")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let categoryChoice = try #require(choices.choice(matching: "category"))
        let categoryAnswer = await answer(categoryChoice.request, prompt: "category", using: brain, fixture: fixture)
        #expect(categoryAnswer.kind == .metric)
        #expect(categoryAnswer.title == "Groceries Spend")
        #expect((categoryAnswer.primaryValue ?? "").contains("190"))

        let textChoice = try #require(choices.choice(matching: "description"))
        let textAnswer = await answer(textChoice.request, prompt: "description", using: brain, fixture: fixture)
        #expect(textAnswer.kind == .metric)
        #expect(textAnswer.title == "All expense matches for \"Grocery\" Spend")
        #expect((textAnswer.primaryValue ?? "").contains("190"))
    }

    @Test func resolver_expenseMatchChoiceUsesStoredTitleInButtonAndAnswer() async throws {
        let fixture = try makeFixture(includeGroceryOutletExpense: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("How much did I spend on Grocery?", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery clarification choices.")
            return
        }

        let groceryOutletChoice = try #require(choices.choice(matching: "Grocery Outlet of Midt"))
        #expect(groceryOutletChoice.title == "Grocery Outlet of Midt")
        #expect(groceryOutletChoice.kindLabel == "Expense match")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)

        let answer = await answer(groceryOutletChoice.request, prompt: "Grocery Outlet of Midt", using: brain, fixture: fixture)
        #expect(answer.kind == .metric)
        #expect(answer.title == "Grocery Outlet of Midt Spend")
        #expect((answer.primaryValue ?? "").contains("42"))
    }

    @Test func resolver_multipleExpenseTextMatchesUsesExplicitAggregateChoice() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let clarification = await answer("Show Grocery expenses", using: brain, fixture: fixture)
        guard case .clarificationChoices(let choices)? = clarification.attachment else {
            Issue.record("Expected Grocery list clarification choices.")
            return
        }

        let aggregate = try #require(choices.choice(matching: "description"))
        #expect(aggregate.title == "All expense matches for \"Grocery\"")
        #expect(aggregate.kindLabel == "Expense search")
        #expect(choices.choices.contains { $0.title.contains("Text") } == false)
    }

    @Test func resolver_categoryOnlySpendTargetAutoResolvesWithoutTextChoice() async throws {
        let fixture = try makeFixture(includeTransportationCategory: true)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let answer = await answer("What did I spend on Transportation?", using: brain, fixture: fixture)

        #expect(answer.kind == .metric)
        #expect(answer.title == "Transportation Spend")
        #expect(answer.attachment == nil)
        #expect((answer.primaryValue ?? "").contains("60"))
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
        let unavailablePlan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unavailableModel
            ),
            dateRange: nil,
            comparisonDateRange: nil,
            now: fixture.now
        )
        let unavailableAnswer = executor.execute(plan: unavailablePlan, snapshot: try MarinaWorkspaceSnapshotProvider().snapshot(for: fixture.workspace, modelContext: fixture.context))
        #expect(unavailableAnswer.title == "I can't answer that yet")
        #expect(unavailableAnswer.subtitle?.contains("My on-device language model") == true)
        #expect(unavailableAnswer.subtitle?.contains("Marina") == false)

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
        #expect(answer.title == "I can't answer that yet")
        #expect(answer.subtitle?.contains("I can still answer") == true)
    }

    @Test func insightContext_buildsCompactFactsForSupportedAnswerShapes() throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )

        let metric = MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Spend Today",
                subtitle: "Apr 1, 2026 - Apr 30, 2026",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Period room", value: "$420.00", amount: 420)]
            ),
            plan: plan
        )
        #expect(metric.isNarratable)
        #expect(metric.answerKind == .metric)
        #expect(metric.entity == .budget)
        #expect(metric.operation == .forecast)
        #expect(metric.measure == .remainingRoom)
        #expect(metric.rows.count == 1)

        let list = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(
                kind: .list,
                title: "Top Categories",
                rows: [HomeAnswerRow(title: "Groceries", value: "$120.00")]
            ),
            plan: plan
        )
        #expect(list.isNarratable)
        #expect(list.answerKind == .list)

        let comparison = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(
                kind: .comparison,
                title: "Budget Comparison",
                primaryValue: "Down $18.00",
                rows: [
                    HomeAnswerRow(title: "Current period", value: "$200.00"),
                    HomeAnswerRow(title: "Previous period", value: "$218.00")
                ]
            ),
            plan: plan
        )
        #expect(comparison.isNarratable)
        #expect(comparison.rows.count == 2)

        let emptyMessage = MarinaInsightContext(
            prompt: nil,
            result: MarinaExecutionResult(kind: .message, title: "No Expenses Found"),
            plan: plan
        )
        #expect(emptyMessage.isNarratable == false)
    }

    @Test func insightFactsDigest_capsRowsAndUsesOnlySuppliedFacts() throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                expectedAnswerShape: .list
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let rows = (1...10).map { index in
            HomeAnswerRow(title: "Row \(index)", value: "$\(index)")
        }
        let context = MarinaInsightContext(
            prompt: "Show category spotlight.",
            result: MarinaExecutionResult(kind: .list, title: "Category Spotlight", rows: rows),
            plan: plan
        )
        let digest = MarinaAnswerFactsDigest(context: context).text()

        #expect(context.rows.count == MarinaInsightContext.maxRows)
        #expect(digest.contains("Row 1"))
        #expect(digest.contains("Row 6"))
        #expect(digest.contains("Row 7") == false)
        #expect(digest.contains("Personal") == false)
    }

    #if canImport(FoundationModels)
    @Test func readAnswerFactsTool_returnsOnlySuppliedFacts() async throws {
        guard #available(iOS 26.0, *) else { return }

        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .card,
                operation: .sum,
                measure: .budgetImpact,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let context = MarinaInsightContext(
            prompt: "Summarize my Apple Card.",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Apple Card Spend",
                primaryValue: "$1,370.00",
                rows: [HomeAnswerRow(title: "Variable", value: "$80.00")]
            ),
            plan: plan
        )
        let tool = MarinaReadAnswerFactsTool(context: context)
        let output = try await tool.call(arguments: MarinaReadAnswerFactsTool.Arguments(focus: nil))

        #expect(output.contains("Apple Card Spend"))
        #expect(output.contains("$1,370.00"))
        #expect(output.contains("Variable"))
        #expect(output.contains("SwiftData") == false)
    }
    #endif

    @Test func deterministicInsightNarrator_producesWarmFallback() async throws {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: .metric
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        let context = MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: .metric,
                title: "Safe Spend Today",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
            ),
            plan: plan
        )

        let narration = try await MarinaDeterministicInsightNarrator().narration(for: context)
        #expect(narration?.contains("Safe Spend Today") == true)
        #expect(narration?.contains("$42.00") == true)
        #expect(narration?.contains("Period room") == true)
        #expect(narration?.hasPrefix("Marina:") == false)
    }

    @Test func deterministicInsightNarrator_streamYieldsOneInstantFallback() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )

        let values = try await collect(MarinaDeterministicInsightNarrator().narrationStream(for: context))

        #expect(values.count == 1)
        #expect(values.first?.contains("Safe Spend Today") == true)
    }

    @Test func insightNarrator_streamSkipsNonNarratableContext() async throws {
        let context = insightContext(
            kind: .message,
            title: "Can you clarify?",
            primaryValue: nil,
            rows: []
        )

        let values = try await collect(MarinaInsightNarrator().narrationStream(for: context))

        #expect(values.isEmpty)
    }

    @Test func insightNarrator_modelStreamFailureFallsBackInstantly() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish(throwing: TestNarrationError.failed)
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values.count == 1)
        #expect(values.first?.contains("Safe Spend Today") == true)
    }

    @Test func voiceSanitizer_removesLeadingNameLabelsAndPreservesLaterMentions() throws {
        #expect(MarinaVoiceSanitizer.sanitizedFinal("Marina: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("Marina says: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("This is how Marina sees the answer.") == "This is how Marina sees the answer.")
    }

    @Test func voiceSanitizer_suppressesPartialStreamingNameLabels() throws {
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("M") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Ma") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Marina") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("Marina: I see your safe spend.") == "I see your safe spend.")
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("I see your safe spend.") == "I see your safe spend.")
    }

    @Test func voiceSanitizer_rewritesAssistantOwnedFinancialOpenings() throws {
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My income status is on track.") == "Your income status is on track.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My budget has room left.") == "Your budget has room left.")
        #expect(MarinaVoiceSanitizer.sanitizedFinal("My read is that your income is on track.") == "My read is that your income is on track.")
    }

    @Test func voiceSanitizer_suppressesPartialAssistantOwnedFinancialOpenings() throws {
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My income") == nil)
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My income status is on track.") == "Your income status is on track.")
        #expect(MarinaVoiceSanitizer.sanitizedStreaming("My read is that your income is on track.") == "My read is that your income is on track.")
    }

    @Test func insightNarrator_modelStreamStripsLeadingNameLabel() async throws {
        let context = insightContext(
            kind: .metric,
            title: "Safe Spend Today",
            primaryValue: "$42.00",
            rows: [HomeAnswerRow(title: "Period room", value: "$420.00")]
        )
        let narrator = MarinaInsightNarrator(modelStreamProvider: { _ in
            AsyncThrowingStream { continuation in
                continuation.yield("Marina:")
                continuation.yield("Marina: I see your safe spend.")
                continuation.finish()
            }
        })

        let values = try await collect(narrator.narrationStream(for: context))

        #expect(values == ["I see your safe spend."])
    }

    @Test func brain_addsInsightToSuccessfulAnswersAndSkipsTerminalAnswers() async throws {
        let fixture = try makeFixture()
        let narrator = RecordingInsightNarrator(response: "Stub insight.")
        let brain = MarinaBrain(
            interpreter: MarinaRuleBasedInterpreter(),
            insightNarrator: narrator
        )

        let successful = await answer("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(successful.kind == .metric)
        #expect(successful.explanation == "Stub insight.")
        #expect(narrator.contexts.count == 1)
        #expect(narrator.contexts.first?.title == "Safe Spend Today")

        let unsupported = await answer("delete my Apple Card", using: brain, fixture: fixture)
        #expect(unsupported.kind == .message)
        #expect(unsupported.explanation == nil)
        #expect(narrator.contexts.count == 1)

        let clarification = await answer(
            MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .clarification,
                clarificationQuestion: "Which matching record should Marina use?",
                unsupportedReason: .ambiguousEntity
            ),
            prompt: "Clarify this.",
            using: brain,
            fixture: fixture
        )
        #expect(clarification.kind == .message)
        #expect(clarification.explanation == nil)
        #expect(narrator.contexts.count == 1)
    }

    @Test func brain_keepsOriginalAnswerWhenInsightNarratorFails() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(
            interpreter: MarinaRuleBasedInterpreter(),
            insightNarrator: ThrowingInsightNarrator()
        )

        let answer = await answer("What is my safe spend today?", using: brain, fixture: fixture)
        #expect(answer.kind == .metric)
        #expect(answer.primaryValue != nil)
        #expect(answer.explanation == nil)
    }

    @Test func brain_answerSeedReturnsCardBeforeNarrationAndIncludesContextOnlyForNarratableAnswers() async throws {
        let fixture = try makeFixture()
        let narrator = RecordingInsightNarrator(response: "Stub insight.")
        let brain = MarinaBrain(
            interpreter: MarinaRuleBasedInterpreter(),
            insightNarrator: narrator
        )

        let successful = await brain.answerSeed(
            prompt: "What is my safe spend today?",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        #expect(successful.answer.kind == .metric)
        #expect(successful.answer.explanation == nil)
        #expect(successful.insightContext?.title == "Safe Spend Today")
        #expect(narrator.contexts.isEmpty)

        let terminal = await brain.answerSeed(
            prompt: "delete my Apple Card",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        #expect(terminal.answer.kind == .message)
        #expect(terminal.insightContext == nil)
        #expect(narrator.contexts.isEmpty)
    }

    @Test func brain_completedAnswerCombinesStreamedNarrationWithSeed() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let seed = await brain.answerSeed(
            prompt: "What is my safe spend today?",
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            now: fixture.now
        )

        let completed = brain.completedAnswer(from: seed, streamingNarration: "Streamed insight.")

        #expect(completed.id == seed.answer.id)
        #expect(completed.rows == seed.answer.rows)
        #expect(completed.explanation == "Streamed insight.")
    }

    @Test func homeMetricParity_matchesCardCategoryAvailabilityIncomeAndNextPlannedCalculators() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let homeContext = MarinaPanelHomeContext(dateRange: fixture.currentRange)
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: homeContext,
            now: fixture.now
        )

        let appleCard = try #require(snapshot.cards.first(where: { $0.name == "Apple Card" }))
        let cardMetrics = HomeCardMetricsCalculator.metrics(
            for: appleCard,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            start: fixture.currentRange.startDate,
            end: fixture.currentRange.endDate,
            excludeFuturePlannedExpenses: false,
            excludeFutureVariableExpenses: false,
            now: fixture.now
        )
        let cardAnswer = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(cardAnswer.primaryValue == CurrencyFormatter.string(from: cardMetrics.total))
        #expect(cardAnswer.rows.contains(where: { $0.title == "Planned" && $0.amount == cardMetrics.plannedTotal }))
        #expect(cardAnswer.rows.contains(where: { $0.title == "Variable" && $0.amount == cardMetrics.variableTotal }))

        let availability = HomeCategoryLimitsAggregator.build(
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            rangeStart: fixture.currentRange.startDate,
            rangeEnd: fixture.currentRange.endDate
        )
        let availabilityAnswer = await answer("Show category availability.", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(availabilityAnswer.rows.first(where: { $0.title == "Over" })?.value == AppNumberFormat.integer(availability.overCount))
        #expect(availabilityAnswer.rows.first(where: { $0.title == "Near" })?.value == AppNumberFormat.integer(availability.nearCount))

        let incomeProgress = HomeQueryEngine().execute(
            query: HomeQuery(intent: .incomeProgressSummary, dateRange: fixture.currentRange),
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            incomes: snapshot.incomes,
            now: fixture.now
        )
        let incomeAnswer = await answer("How is my income progress?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(incomeAnswer.primaryValue == incomeProgress.primaryValue)

        let safeSpend = HomeQueryEngine().execute(
            query: HomeQuery(intent: .safeSpendToday, dateRange: fixture.currentRange),
            budgets: snapshot.budgets,
            categories: snapshot.categories,
            plannedExpenses: snapshot.homeCalculationPlannedExpenses,
            variableExpenses: snapshot.homeCalculationVariableExpenses,
            incomes: snapshot.incomes,
            savingsEntries: snapshot.savingsEntries,
            now: fixture.now
        )
        let safeSpendAnswer = await answer("What is my safe spend today?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(safeSpendAnswer.primaryValue == safeSpend.primaryValue)

        let next = try #require(
            HomeNextPlannedExpenseFinder.nextExpense(
                from: snapshot.homePlannedExpenses,
                in: fixture.currentRange.startDate,
                to: fixture.currentRange.endDate,
                now: fixture.now
            )
        )
        let nextAnswer = await answer("What is my next planned expense?", using: brain, fixture: fixture, homeContext: homeContext)
        #expect(nextAnswer.rows.first(where: { $0.title == "Expense" })?.value == next.title)
    }

    @Test func homeMetricParity_honorsFutureExclusionButKeepsNextPlannedUnfiltered() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let includeFutureContext = MarinaPanelHomeContext(dateRange: fixture.currentRange)
        let excludeFutureContext = MarinaPanelHomeContext(
            dateRange: fixture.currentRange,
            excludeFuturePlannedExpensesFromCalculations: true,
            excludeFutureVariableExpensesFromCalculations: true
        )

        let included = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: includeFutureContext)
        let excluded = await answer("Summarize my Apple Card.", using: brain, fixture: fixture, homeContext: excludeFutureContext)
        #expect(included.primaryValue == CurrencyFormatter.string(from: 1_370))
        #expect(excluded.primaryValue == CurrencyFormatter.string(from: 1_280))

        let next = await answer("What is my next planned expense?", using: brain, fixture: fixture, homeContext: excludeFutureContext)
        #expect(next.primaryValue == CurrencyFormatter.string(from: 90))
        let nextHasExpenseRow = next.rows.contains { row in
            row.title == "Expense" && row.value == "Phone"
        }
        #expect(nextHasExpenseRow)
    }

    @Test func homeMetricParity_ignoresOrphanBudgetGeneratedPlannedExpenses() async throws {
        let fixture = try makeFixture()
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let appleCard = try #require(snapshot.cards.first(where: { $0.name == "Apple Card" }))
        let bills = try #require(snapshot.categories.first(where: { $0.name == "Bills" }))
        let orphan = PlannedExpense(
            title: "Orphan Generated Row",
            plannedAmount: 500,
            expenseDate: date(2026, 4, 9),
            workspace: fixture.workspace,
            card: appleCard,
            category: bills,
            sourceBudgetID: UUID()
        )
        fixture.context.insert(orphan)
        try fixture.context.save()

        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let answer = await answer("Summarize my Apple Card.", using: brain, fixture: fixture)
        #expect(answer.primaryValue == CurrencyFormatter.string(from: 1_370))
    }

    @Test func safeSpendWhatIf_uncappedCategoriesUseBaseRoom() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())

        let answer = await answer("If I spend $5 on Groceries, what happens to my safe spend?", using: brain, fixture: fixture)

        #expect(answer.kind == .comparison)
        let currentSafeSpend = answer.rows.first(where: { $0.title == "Current safe spend today" })?.amount ?? -1
        let safeSpendAfter = answer.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        #expect(abs(currentSafeSpend - 145) < 0.0001)
        #expect(abs(safeSpendAfter - 144.54545454545453) < 0.0001)
        #expect(answer.rows.first(where: { $0.title == "Period room after" })?.amount == 1_590)
    }

    @Test func safeSpendWhatIf_allCategoriesCappedReducesCategoryCapRoom() async throws {
        let fixture = try makeFixture(includeAppleMerchantExpense: false)
        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: fixture.workspace,
            modelContext: fixture.context,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            now: fixture.now
        )
        let budget = try #require(snapshot.budgets.first(where: { $0.name == "April 2026" }))
        let dining = try #require(snapshot.categories.first(where: { $0.name == "Dining" }))
        let bills = try #require(snapshot.categories.first(where: { $0.name == "Bills" }))
        let diningLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 200, budget: budget, category: dining)
        let billsLimit = BudgetCategoryLimit(minAmount: 0, maxAmount: 2_000, budget: budget, category: bills)
        budget.categoryLimits = (budget.categoryLimits ?? []) + [diningLimit, billsLimit]
        fixture.context.insert(diningLimit)
        fixture.context.insert(billsLimit)
        try fixture.context.save()

        let brain = MarinaBrain(interpreter: MarinaRuleBasedInterpreter())
        let answer = await answer("If I spend $5 on Groceries, what happens to my safe spend?", using: brain, fixture: fixture)

        #expect(answer.kind == .comparison)
        let currentSafeSpend = answer.rows.first(where: { $0.title == "Current safe spend today" })?.amount ?? -1
        let safeSpendAfter = answer.rows.first(where: { $0.title == "Safe spend after" })?.amount ?? -1
        #expect(abs(currentSafeSpend - 81.36363636363636) < 0.0001)
        #expect(abs(safeSpendAfter - 80.9090909090909) < 0.0001)
        #expect(answer.rows.first(where: { $0.title == "Period room after" })?.amount == 890)
    }

    @Test func conversationDisplayAdapter_preservesUserPromptAsSeparateMessage() throws {
        let suiteName = "MarinaSemanticPromptSuiteTests.conversationDisplay"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = MarinaConversationStore(userDefaults: defaults, storageKeyPrefix: "tests.marina.display")
        let workspaceID = UUID()
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            userPrompt: "What is my safe spend today?",
            title: "Safe Spend Today",
            primaryValue: "$42.00"
        )

        store.saveAnswers([answer], workspaceID: workspaceID)
        let loaded = store.loadAnswers(workspaceID: workspaceID)
        #expect(loaded.first?.userPrompt == "What is my safe spend today?")

        let messages = MarinaConversationDisplayAdapter.messages(from: loaded)
        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].prompt == "What is my safe spend today?")
        #expect(messages[1].role == .assistant)
        #expect(messages[1].answer?.title == "Safe Spend Today")
    }

    private func answer(
        _ prompt: String,
        using brain: MarinaBrain,
        fixture: Fixture,
        homeContext: MarinaPanelHomeContext? = nil
    ) async -> HomeAnswer {
        let resolvedHomeContext = homeContext ?? MarinaPanelHomeContext(dateRange: fixture.currentRange)
        return await brain.answer(
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: resolvedHomeContext,
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
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
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

    private func insightContext(
        kind: HomeAnswerKind,
        title: String,
        primaryValue: String?,
        rows: [HomeAnswerRow]
    ) -> MarinaInsightContext {
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: MarinaSemanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: kind == .comparison ? .comparison : (kind == .list ? .list : .metric)
            ),
            dateRange: HomeQueryDateRange(startDate: date(2026, 4, 1), endDate: date(2026, 4, 30)),
            comparisonDateRange: nil,
            now: date(2026, 4, 20)
        )
        return MarinaInsightContext(
            prompt: "What is my safe spend today?",
            result: MarinaExecutionResult(
                kind: kind,
                title: title,
                primaryValue: primaryValue,
                rows: rows
            ),
            plan: plan
        )
    }

    private func collect(_ stream: AsyncThrowingStream<String, Error>) async throws -> [String] {
        var values: [String] = []
        for try await value in stream {
            values.append(value)
        }
        return values
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

    private final class RecordingInsightNarrator: MarinaInsightNarrating {
        private let response: String?
        private(set) var contexts: [MarinaInsightContext] = []

        init(response: String?) {
            self.response = response
        }

        func narration(for context: MarinaInsightContext) async throws -> String? {
            contexts.append(context)
            return response
        }
    }

    private struct ThrowingInsightNarrator: MarinaInsightNarrating {
        func narration(for context: MarinaInsightContext) async throws -> String? {
            throw TestNarrationError.failed
        }
    }

    private enum TestNarrationError: Error {
        case failed
    }

    private func makeFixture(
        includeAppleMerchantExpense: Bool = true,
        includeTransportationCategory: Bool = false,
        includeGroceryOutletExpense: Bool = false,
        includeDebitCard: Bool = false
    ) throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#14B8A6")

        let appleCard = Card(name: "Apple Card", workspace: workspace)
        let chase = Card(name: "Chase", workspace: workspace)
        let debitCard = includeDebitCard ? Card(name: "Debit Card", workspace: workspace) : nil
        let otherAppleCard = Card(name: "Apple Card", workspace: otherWorkspace)

        let groceries = Category(name: "Groceries", hexColor: "#16A34A", workspace: workspace)
        let dining = Category(name: "Dining", hexColor: "#F97316", workspace: workspace)
        let bills = Category(name: "Bills", hexColor: "#2563EB", workspace: workspace)
        let transportation = includeTransportationCategory
            ? Category(name: "Transportation", hexColor: "#0F766E", workspace: workspace)
            : nil

        let currentBudget = Budget(
            name: "April 2026",
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30),
            workspace: workspace
        )
        let groceriesLimit = BudgetCategoryLimit(
            minAmount: 0,
            maxAmount: 200,
            budget: currentBudget,
            category: groceries
        )
        currentBudget.categoryLimits = [groceriesLimit]
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
        let debitPlan = debitCard.map { card in
            PlannedExpense(
                title: "Debit Subscription",
                plannedAmount: 70,
                expenseDate: date(2026, 4, 9),
                workspace: workspace,
                card: card,
                category: bills
            )
        }

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
        let groceryOutlet = includeGroceryOutletExpense
            ? VariableExpense(
                descriptionText: "Grocery Outlet of Midt",
                amount: 42,
                transactionDate: date(2026, 4, 12),
                workspace: workspace,
                card: chase,
                category: groceries
            )
            : nil
        let trainFare = transportation.map { category in
            VariableExpense(
                descriptionText: "Train fare",
                amount: 60,
                transactionDate: date(2026, 4, 14),
                workspace: workspace,
                card: chase,
                category: category
            )
        }
        let debitCoffee = debitCard.map { card in
            VariableExpense(
                descriptionText: "Debit Coffee",
                amount: 30,
                transactionDate: date(2026, 4, 15),
                workspace: workspace,
                card: card,
                category: dining
            )
        }
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
        if let debitCard {
            context.insert(debitCard)
        }
        context.insert(otherAppleCard)
        context.insert(groceries)
        context.insert(dining)
        context.insert(bills)
        if let transportation {
            context.insert(transportation)
        }
        context.insert(currentBudget)
        context.insert(groceriesLimit)
        context.insert(previousBudget)
        context.insert(rentPreset)
        context.insert(phonePreset)
        context.insert(groceryPreset)
        context.insert(rent)
        context.insert(phone)
        context.insert(groceriesPlan)
        if let debitPlan {
            context.insert(debitPlan)
        }
        context.insert(targetApril)
        context.insert(starbucks)
        if let appleStore {
            context.insert(appleStore)
        }
        if let groceryOutlet {
            context.insert(groceryOutlet)
        }
        if let trainFare {
            context.insert(trainFare)
        }
        if let debitCoffee {
            context.insert(debitCoffee)
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
