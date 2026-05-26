import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaCanonicalQueryTests {
    @Test func canonicalCatalog_coversAllPersistentModelsWithPolicies() {
        let catalog = MarinaCanonicalDomainCatalog()
        let expected = MarinaEntityCatalog.current.persistentModelEntityNames
        let policies = catalog.policies

        #expect(Set(policies.map(\.modelName)) == expected)
        for policy in policies {
            #expect(policy.searchableNames.isEmpty == false)
            #expect(policy.supportedOperations.isEmpty == false)
            #expect(policy.defaultOperation != .simulate)
        }
    }

    @Test func canonicalCompiler_actualIncomeDefaultsToActualCurrentMonth() throws {
        let result = MarinaCanonicalQueryCompiler().compile(
            prompt: "Actual income",
            now: date(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        guard case .success(let decision) = result else {
            Issue.record("Expected Actual income to compile into a canonical query.")
            return
        }

        #expect(decision.query.modelName == "Income")
        #expect(decision.query.subject == .income)
        #expect(decision.query.operation == .sum)
        #expect(decision.query.amountField == .incomeAmount)
        #expect(decision.query.amountBasis == .actualIncome)
        #expect(decision.query.statusScope == .actual)
        #expect(decision.query.filters.isEmpty)
        #expect(decision.query.dateSource == .defaultBudgetingPeriod)
        #expect(dayComponents(decision.query.dateScope?.resolvedRange?.startDate) == DateComponents(year: 2026, month: 5, day: 1))
        #expect(dayComponents(decision.query.dateScope?.resolvedRange?.endDate) == DateComponents(year: 2026, month: 5, day: 31))
        #expect(decision.query.assumptions.contains { $0.contains("current month") })
    }

    @Test func canonicalCompiler_compilesBroadSafeReadFamilies() throws {
        let compiler = MarinaCanonicalQueryCompiler()
        let expectations: [(prompt: String, model: String, operation: MarinaOperation, amountField: MarinaAmountField?)] = [
            ("spending this month", "VariableExpense", .sum, .budgetImpactAmount),
            ("how many cards", "Card", .count, nil),
            ("savings activity", "SavingsLedgerEntry", .list, .savingsAmount),
            ("income by source", "Income", .breakdown, .incomeAmount),
            ("recent transactions", "VariableExpense", .list, .budgetImpactAmount),
            ("list import merchant rules", "ImportMerchantRule", .list, nil)
        ]

        for expectation in expectations {
            let result = compiler.compile(
                prompt: expectation.prompt,
                now: date(2026, 5, 15),
                defaultPeriodUnit: .month
            )
            guard case .success(let decision) = result else {
                Issue.record("Expected \(expectation.prompt) to compile.")
                continue
            }
            #expect(decision.query.modelName == expectation.model)
            #expect(decision.query.operation == expectation.operation)
            #expect(decision.query.amountField == expectation.amountField)
        }
    }

    @Test func canonicalCompiler_doesNotFlattenNamedIncomeSourceQueries() {
        let result = MarinaCanonicalQueryCompiler().compile(
            prompt: "What is my income from Salary this month?",
            now: date(2026, 5, 15),
            defaultPeriodUnit: .month
        )

        guard case .failure(let failure) = result else {
            Issue.record("Expected named income source prompt to stay with resolver path.")
            return
        }
        #expect(failure.kind == .explicitNamedTargetRequired)
    }

    @Test func canonicalRewriter_dropsGenericIncomeTargetAndKeepsStatusModifier() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "What is my actual income this month?"
        let weakModelQuery = MarinaSemanticQuery(
            subject: .income,
            operation: .sum,
            filters: [
                MarinaFilter(
                    role: .primaryTarget,
                    relationship: .incomeSource,
                    value: "actual income",
                    matchMode: .semanticOrAlias,
                    entityTypeHint: .incomeSource,
                    allowedEntityTypeHints: [.incomeSource],
                    sourceID: nil
                )
            ],
            amountField: .incomeAmount,
            responseShape: .summaryCard
        )
        let weakCandidate = MarinaSemanticQueryAdapter().compatibilityCandidate(
            from: weakModelQuery,
            prompt: prompt
        )
        let rewritten = MarinaCanonicalQueryRewriter().rewrite(
            prompt: prompt,
            interpretation: MarinaTurnInterpretation(
                result: .query(weakModelQuery),
                compatibilityCandidate: weakCandidate
            ),
            candidate: weakCandidate,
            context: turnContext(provider: fixture.provider)
        )

        guard case .query(let query) = rewritten?.result else {
            Issue.record("Expected weak model query to be rewritten canonically.")
            return
        }

        #expect(rewritten?.generatedSchemaName == MarinaCanonicalQueryRewriter.generatedSchemaName)
        #expect(query.subject == .income)
        #expect(query.filters.isEmpty)
        #expect(query.incomeStatusScope == .actual)
        #expect(query.dateRange?.resolvedRange != nil)
    }

    @Test func targetedBalanceCanonicalizer_resolvesAllocationAccountPhrases() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        fixture.context.insert(account)
        try fixture.context.save()

        for prompt in ["What is Alejandro's balance?", "What is Alejandro’s balance", "Alejandro balance"] {
            let interpretation = MarinaCanonicalQueryRewriter().deterministicInterpretation(
                prompt: prompt,
                context: turnContext(provider: fixture.provider)
            )

            guard case .query(let query) = interpretation?.result else {
                Issue.record("Expected \(prompt) to become a canonical balance query.")
                continue
            }

            #expect(interpretation?.generatedSchemaName == MarinaTargetedBalanceCanonicalizer.generatedSchemaName)
            #expect(interpretation?.repairSummary?.contains("canonicalBalance:reconciliation") == true)
            #expect(query.subject == .reconciliationAccounts)
            #expect(query.operation == .lookupDetails)
            #expect(query.amountField == .reconciliationBalance)
            #expect(query.requestedDetail == .balance)
            #expect(query.routeIntent?.kind == .reconciliationBalance)
            #expect(query.routeIntent?.preferredExecutorRoute == .workspaceAggregation)
            #expect(query.filters.first?.relationship == .allocationAccount)
            #expect(query.filters.first?.sourceID == account.id)
            #expect(dayComponents(query.dateRange?.resolvedRange?.startDate) == DateComponents(year: 2026, month: 5, day: 1))
            #expect(dayComponents(query.dateRange?.resolvedRange?.endDate) == DateComponents(year: 2026, month: 5, day: 31))
        }
    }

    @Test func targetedBalanceCanonicalizer_resolvesAppleCardBalanceAsCardSpend() throws {
        let fixture = try makeFixture()

        let interpretation = MarinaCanonicalQueryRewriter().deterministicInterpretation(
            prompt: "What is my Apple Card balance",
            context: turnContext(provider: fixture.provider)
        )

        guard case .query(let query) = interpretation?.result else {
            Issue.record("Expected Apple Card balance to become a canonical card balance query.")
            return
        }

        #expect(interpretation?.generatedSchemaName == MarinaTargetedBalanceCanonicalizer.generatedSchemaName)
        #expect(interpretation?.repairSummary?.contains("canonicalBalance:card") == true)
        #expect(query.subject == .cards)
        #expect(query.operation == .lookupDetails)
        #expect(query.amountField == nil)
        #expect(query.requestedDetail == .balance)
        #expect(query.routeIntent?.kind == .broadSpend)
        #expect(query.routeIntent?.preferredExecutorRoute == .workspaceAggregation)
        #expect(query.filters.first?.relationship == .card)
        #expect(query.filters.first?.sourceID == fixture.appleCard.id)
        #expect(dayComponents(query.dateRange?.resolvedRange?.startDate) == DateComponents(year: 2026, month: 5, day: 1))
    }

    @Test func targetedBalanceCanonicalizer_promptVariantsProduceSameCardBalanceQuery() throws {
        let fixture = try makeFixture()
        let context = turnContext(provider: fixture.provider)
        let typedText = MarinaCanonicalQueryRewriter().deterministicInterpretation(
            prompt: "What is my Apple Card balance",
            context: context
        )
        let suggestionStyle = MarinaCanonicalQueryRewriter().deterministicInterpretation(
            prompt: "Apple Card balance",
            context: context
        )

        guard case .query(let typedQuery) = typedText?.result,
              case .query(let suggestionQuery) = suggestionStyle?.result else {
            Issue.record("Expected both balance prompt variants to compile.")
            return
        }

        #expect(typedQuery.subject == suggestionQuery.subject)
        #expect(typedQuery.operation == suggestionQuery.operation)
        #expect(typedQuery.requestedDetail == suggestionQuery.requestedDetail)
        #expect(typedQuery.routeIntent == suggestionQuery.routeIntent)
        #expect(typedQuery.filters.first?.sourceID == suggestionQuery.filters.first?.sourceID)
        #expect(typedQuery.dateRange?.resolvedRange == suggestionQuery.dateRange?.resolvedRange)
    }


    @Test func targetedBalanceCanonicalizer_ignoresNonBalanceCollisions() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let category = Offshore.Category(name: "Alejandro", hexColor: "#FFAA00", workspace: fixture.workspace)
        let expense = VariableExpense(
            descriptionText: "Alejandro",
            amount: 25,
            transactionDate: date(2026, 5, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: category
        )
        fixture.context.insert(account)
        fixture.context.insert(category)
        fixture.context.insert(expense)
        try fixture.context.save()

        let interpretation = MarinaCanonicalQueryRewriter().deterministicInterpretation(
            prompt: "Alejandro balance",
            context: turnContext(provider: fixture.provider)
        )

        guard case .query(let query) = interpretation?.result else {
            Issue.record("Expected balance-capable entity to win over merchant/category collisions.")
            return
        }

        #expect(query.subject == .reconciliationAccounts)
        #expect(query.filters.first?.sourceID == account.id)
    }

    @Test func targetedBalanceCanonicalizer_clarifiesMultipleBalanceCapableMatches() throws {
        let fixture = try makeFixture()
        let account = AllocationAccount(name: "Shared", workspace: fixture.workspace)
        let card = Card(name: "Shared", workspace: fixture.workspace)
        fixture.context.insert(account)
        fixture.context.insert(card)
        try fixture.context.save()

        let interpretation = MarinaCanonicalQueryRewriter().deterministicInterpretation(
            prompt: "Shared balance",
            context: turnContext(provider: fixture.provider)
        )

        guard case .clarification(let clarification) = interpretation?.result else {
            Issue.record("Expected duplicate balance-capable names to clarify.")
            return
        }

        #expect(interpretation?.generatedSchemaName == MarinaTargetedBalanceCanonicalizer.generatedSchemaName)
        #expect(clarification.kind == .ambiguousTarget)
        let choiceTypes = Set(clarification.choices.compactMap(\.entityTypeHint))
        #expect(choiceTypes.contains(.allocationAccount))
        #expect(choiceTypes.contains(.card))
        #expect(clarification.choices.count >= 2)
        #expect(clarification.choices.filter { $0.entityTypeHint == .allocationAccount || $0.entityTypeHint == .card }.allSatisfy { $0.resumeIntent?.semanticQuery?.requestedDetail == .balance })
    }

    @Test func targetedDetailCanonicalizer_compilesStatusLinkedDueActivityAndRemainingPrompts() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let alejandro = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        fixture.context.insert(alejandro)
        try fixture.context.save()
        let context = turnContext(provider: fixture.provider)
        let rewriter = MarinaCanonicalQueryRewriter()

        let expectations: [(prompt: String, route: MarinaRouteIntentKind, subject: MarinaSubject, detail: MarinaSemanticRequestedDetail?)] = [
            ("What is my active budget status?", .activeBudget, .budgets, .status),
            ("Savings status", .savingsStatus, .savingsAccounts, .status),
            ("How is income doing vs planned?", .incomePlannedVsActual, .income, .status),
            ("Which cards are linked to May Budget?", .budgetLinkedCards, .budgets, .linkedCards),
            ("Which presets are linked to May Budget?", .budgetLinkedPresets, .budgets, .linkedPresets),
            ("Is Apple Card linked to May Budget?", .budgetMembership, .budgets, .membership),
            ("Which budgets use Apple Card?", .budgetMembership, .budgets, .membership),
            ("What is due next?", .plannedExpenseRows, .plannedExpenses, .date),
            ("What bills are due this month?", .plannedExpenseRows, .plannedExpenses, .date),
            ("Rent due", .plannedExpenseRows, .plannedExpenses, .date),
            ("Savings activity", .savingsActivity, .savingsLedgerEntries, .general),
            ("Apple Card activity", .recentTransactionRows, .variableExpenses, .general),
            ("Groceries activity", .recentTransactionRows, .variableExpenses, .general),
            ("Alejandro activity", .reconciliationActivity, .reconciliationAccounts, .general),
            ("How much budget is remaining?", .generic, .budgets, .amount),
            ("How much can I still spend?", .generic, .budgets, .amount),
            ("How much is left in Groceries?", .budgetCategoryLimit, .budgets, .amount),
            ("remaining planned expenses", .plannedExpenseRows, .plannedExpenses, .date)
        ]

        for expectation in expectations {
            let interpretation = rewriter.deterministicInterpretation(
                prompt: expectation.prompt,
                context: context
            )

            guard case .query(let query) = interpretation?.result else {
                Issue.record("Expected \(expectation.prompt) to compile into a canonical detail query.")
                continue
            }

            #expect(interpretation?.generatedSchemaName == MarinaTargetedDetailCanonicalizer.generatedSchemaName)
            #expect(interpretation?.repairSummary?.contains("canonicalDetail") == true)
            #expect(query.routeIntent?.kind == expectation.route)
            #expect(query.subject == expectation.subject)
            #expect(query.requestedDetail == expectation.detail)
        }
    }

    @Test func targetedDetailCanonicalizer_clarifiesBareFragileDetailWords() throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let context = turnContext(provider: fixture.provider)

        for prompt in ["status", "activity", "linked", "remaining"] {
            let interpretation = MarinaCanonicalQueryRewriter().deterministicInterpretation(
                prompt: prompt,
                context: context
            )

            guard case .clarification(let clarification) = interpretation?.result else {
                Issue.record("Expected \(prompt) to clarify instead of guessing.")
                continue
            }

            #expect(interpretation?.generatedSchemaName == MarinaTargetedDetailCanonicalizer.generatedSchemaName)
            #expect(clarification.kind == .missingTarget)
            #expect(clarification.choices.isEmpty == false)
        }
    }

    private func turnContext(provider: MarinaDataProvider) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: "Personal",
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: [],
                categoryNames: [],
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: [],
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: date(2026, 5, 15)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dayComponents(_ date: Date?) -> DateComponents? {
        guard let date else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
    }
}
