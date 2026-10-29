import Testing
@testable import Offshore

@MainActor
struct MarinaTurnPolicyTests {
    @Test func explicitIncomeProgressRejectsAModelPeriodComparison() {
        let policy = MarinaTurnPolicy(prompt: "Show my planned-to-actual income progress for that month.")
        let comparison = MarinaDataRequest(operation: .comparison, tool: .income, cardID: "old-card")
        #expect(policy.violation(for: comparison)?.contains("operation progress") == true)
        let corrected = policy.constrained(.init(tool: .income))
        #expect(corrected.purpose == .incomeProgress && corrected.state == .all)
        #expect(policy.violation(for: corrected) == nil)
        for prompt in ["Compare planned-to-actual income progress this month with last month",
                       "Show planned-to-actual income progress by source"] {
            #expect(MarinaTurnPolicy(prompt: prompt).violation(for: comparison) == nil)
        }
    }

    @Test func namedBudgetOnTrackFrameRequiresPaceWithoutChoosingItsID() {
        let policy = MarinaTurnPolicy(prompt: "Am I on track with my Monthly budget this month?")
        #expect(policy.requiresBudgetPace)
        let request = policy.constrained(.init(tool: .budgetSummary, budgetID: "resolved-monthly"))
        #expect(request.purpose == .budgetPace && request.budgetID == "resolved-monthly")
        #expect(request.relativePeriod == .currentMonth)
        for prompt in ["Am I on track with my Monthly and Quarterly budget?",
                       "Am I on track with my Monthly budget this month versus last month?",
                       "What if I am on track with my Monthly budget?", "Am I on track with my not Monthly budget?"] {
            #expect(!MarinaTurnPolicy(prompt: prompt).requiresBudgetPace)
        }
    }

    @Test func combinedCategoryComparisonMatchesCanonicalCategorySets() {
        let policy = MarinaTurnPolicy(prompt: "Compare this month's spending with last month.")
        var request = MarinaDataRequest(operation: .comparison, relativePeriod: .previousMonth, tool: .expenses)
        request.categoryIDs = ["dining", "groceries"]
        request.comparisonPeriod = .currentMonth
        request.comparisonFilter = .init(categoryIDs: ["groceries", "dining"])

        let corrected = policy.constrained(request)
        #expect(corrected.relativePeriod == .currentMonth && corrected.comparisonPeriod == .previousMonth)
        #expect(corrected.categoryIDs == request.categoryIDs && corrected.comparisonFilter == request.comparisonFilter)
        #expect(policy.violation(for: corrected) == nil)

        // Saved singular selections and newer category arrays represent the same scope.
        request.categoryIDs = nil
        request.categoryID = "dining"
        request.comparisonFilter = .init(categoryIDs: ["dining"])
        #expect(policy.violation(for: request) == nil)
        #expect(policy.constrained(request).relativePeriod == .currentMonth)

        // A different category must still require scope repair before period correction.
        request.comparisonFilter?.categoryIDs = ["dining", "groceries"]
        #expect(policy.constrained(request) == request)
        #expect(policy.violation(for: request)?.contains("Repair the differing selections") == true)
    }

    @Test func sameScopeComparisonPreservesExplicitPeriodOrderWithoutSwappingTargets() {
        var reversed = MarinaDataRequest(operation: .comparison, relativePeriod: .previousMonth, tool: .expenses,
            startDate: "2026-09-01", endDate: "2026-09-30", cardID: "card", categoryID: "category", search: "Coffee")
        reversed.comparisonPeriod = .currentMonth
        reversed.comparisonStartDate = "2026-10-01"
        reversed.comparisonEndDate = "2026-10-31"
        reversed.comparisonFilter = .init(cardID: "card", categoryID: "category", search: "Coffee")
        let policy = MarinaTurnPolicy(prompt: "Compare this month’s spending on that card with last month.")
        let corrected = policy.constrained(reversed)
        #expect(corrected.relativePeriod == .currentMonth && corrected.comparisonPeriod == .previousMonth)
        #expect(corrected.startDate == nil && corrected.endDate == nil)
        #expect(corrected.comparisonStartDate == nil && corrected.comparisonEndDate == nil)
        #expect(corrected.cardID == reversed.cardID && corrected.categoryID == reversed.categoryID && corrected.search == reversed.search)
        #expect(corrected.comparisonFilter == reversed.comparisonFilter)
        #expect(policy.violation(for: corrected) == nil)
        let otherOrder = MarinaTurnPolicy(prompt: "Compare last month's spending on that card with this month.").constrained(corrected)
        #expect(otherOrder.relativePeriod == .previousMonth && otherOrder.comparisonPeriod == .currentMonth)
        var different = reversed
        different.comparisonFilter?.categoryID = "other-category"
        let unchanged = policy.constrained(different) == different
        #expect(unchanged)
        #expect(policy.violation(for: different)?.contains("Repair the differing selections") == true)
        for prompt in ["Compare 2026-10-01 through 2026-10-31 with last month",
                       "Compare this month on Apple Card with last month on Blue Card",
                       "Compare this month on \"Monthly\" with last month", "Do not compare this month with last month",
                       "Compare spending this month with income last month"] {
            let preserved = MarinaTurnPolicy(prompt: prompt).constrained(reversed) == reversed
            #expect(preserved)
        }
    }

    @Test func dueSoonPresetsUseNextSevenDaysOnlyWithoutAnExplicitUserPeriod() {
        let stale = MarinaDataRequest(purpose: .upcomingPresets, tool: .expenses, allTime: true,
            presetID: "rent", startDate: "2026-10-01", endDate: "2026-10-23", cardID: "card")
        for prompt in ["Oh, and what about my presets? Do I have any due soon?", "Show my upcoming presets", "Muestra mis presets por vencer"] {
            let corrected = MarinaTurnPolicy(prompt: prompt).constrained(stale)
            #expect(corrected.relativePeriod == .nextSevenDays && corrected.startDate == nil && corrected.endDate == nil)
            #expect(!corrected.allTime && corrected.purpose == .upcomingPresets)
            #expect(corrected.presetID == "rent" && corrected.cardID == "card" && corrected.operation == stale.operation)
        }
        let explicitMonth = MarinaTurnPolicy(prompt: "Show upcoming presets this month").constrained(stale)
        #expect(explicitMonth.relativePeriod == .currentMonth && explicitMonth.startDate == nil && explicitMonth.endDate == nil)
        for prompt in ["Show upcoming presets from 2026-10-01 to 2026-10-23", "Show upcoming presets on Monday",
                       "Show upcoming presets tomorrow", "Show upcoming presets before payday", "Show upcoming presets until Friday",
                       "Do not show upcoming presets", "What if I have presets due soon?", "Would I have presets due soon?",
                       "Compare upcoming presets this month with last month", "Show my presets"] {
            let preserved = MarinaTurnPolicy(prompt: prompt).constrained(stale) == stale
            #expect(preserved)
        }
        var comparison = stale
        comparison.operation = .comparison
        comparison.comparisonPeriod = .previousMonth
        let preservedComparison = MarinaTurnPolicy(prompt: "Show upcoming presets").constrained(comparison) == comparison
        #expect(preservedComparison)
        var ordinary = stale
        ordinary.purpose = nil
        let preservedOrdinary = MarinaTurnPolicy(prompt: "Show upcoming presets").constrained(ordinary) == ordinary
        #expect(preservedOrdinary)
    }

    @Test func plannedIncomeReceiptPercentageUsesCalculatedProgressWithoutChangingOtherOperations() {
        for prompt in ["What percentage of my planned income have I received this month?",
                       "What share of my expected income have I received?", "What fraction of planned income has been received this month?",
                       "Qué porcentaje de mis ingresos previstos he recibido este mes?"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            let corrected = policy.constrained(.init(tool: .income, cardID: "payroll", state: .actual))
            #expect(corrected.purpose == .incomeProgress && corrected.state == .all)
            #expect(corrected.operation == .summary && corrected.cardID == "payroll")
            #expect(policy.violation(for: .init(tool: .expenses))?.contains("readIncome") == true)
            #expect(policy.violation(for: .init(tool: .budgetSummary)) != nil)
            #expect(policy.violation(for: .init(tool: .findRecords)) == nil)
            #expect(policy.violation(for: corrected) == nil)
            for operation in [MarinaDataRequest.Operation.comparison, .ranking, .trend, .transactions] {
                let preserved = policy.constrained(.init(operation: operation, tool: .income, state: .actual))
                #expect(preserved.operation == operation && preserved.state == .actual && preserved.purpose == nil)
                #expect(policy.violation(for: preserved)?.contains("operation progress") == true)
            }
            let grouped = policy.constrained(.init(tool: .income, state: .actual, grouping: .source))
            #expect(grouped.grouping == .source && grouped.state == .actual && grouped.purpose == nil)
        }
        for prompt in ["What if I received a percentage of my planned income?",
                       "What percentage of my planned income have I not received this month?",
                       "Compare what percentage of my planned income I received this month with last month",
                       "What percentage of my planned income have I received this month and last month?",
                       "What percentage of my planned income have I received? Show expenses too.",
                       "What percentage of my planned income from \"Salary\" have I received this month?",
                       "What percentage of my planned income have I received by source?",
                       "What percentage of my planned income have I received yesterday?"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.constrained(.init(tool: .income)).purpose == nil)
            #expect(policy.violation(for: .init(tool: .expenses)) == nil)
        }
        var periodComparison = MarinaDataRequest(operation: .comparison, relativePeriod: .currentMonth, tool: .income)
        periodComparison.comparisonPeriod = .previousMonth
        let nativePrompt = MarinaTurnPolicy(prompt: "What percentage of my planned income have I received this month?")
        #expect(nativePrompt.violation(for: periodComparison)?.contains("operation progress") == true)
        let comparisonPrompt = MarinaTurnPolicy(prompt: "Compare income this month with last month")
        #expect(comparisonPrompt.violation(for: periodComparison) == nil)
    }

    @Test func budgetPacePlanComparisonRetainsItsSingleExplicitCalendarPeriod() {
        let policy = MarinaTurnPolicy(prompt: "How is my spending tracking against the plan this month?")
        #expect(policy.requiresBudgetPace)
        #expect(policy.periodCue == .relative(.currentMonth))
        let corrected = policy.constrained(.init(tool: .budgetSummary,
            startDate: "2026-09-01", endDate: "2026-09-30"))
        #expect(corrected.purpose == .budgetPace && corrected.relativePeriod == .currentMonth)
        #expect(corrected.startDate == nil && corrected.endDate == nil)
        let comparison = MarinaTurnPolicy(prompt: "Compare spending this month against last month")
        #expect(!comparison.requiresBudgetPace && comparison.periodCue == .other)
    }

    @Test func explicitBudgetPacePhrasingRequiresThePaceCalculation() {
        for prompt in ["Am I on track with my budget this month?", "Is my budget on track?",
                       "How is my spending tracking against the plan this month?",
                       "How is my spending tracking against my plan this month?", "Voy bien con mi presupuesto este mes?"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.requiresBudgetPace)
            let corrected = policy.constrained(.init(tool: .budgetSummary, budgetID: "budget"))
            #expect(corrected.purpose == .budgetPace && corrected.budgetID == "budget")
            #expect(corrected.operation == .summary)
            #expect(policy.violation(for: .init(tool: .expenses))?.contains("readBudgetSummary") == true)
            #expect(policy.violation(for: .init(operation: .comparison, tool: .expenses)) != nil)
            #expect(policy.violation(for: .init(tool: .findRecords)) == nil)
            #expect(policy.violation(for: corrected) == nil)
        }
        for prompt in ["What if I am on track with my budget this month?", "Am I not on track with my budget?",
                       "Am I on track with my budget this month versus last month?",
                       "Am I on track with my budget this month and how much income did I receive?",
                       "Am I on track with my budget? Show income too.", "Am I on track with my budget \"Travel\"?",
                       "Show the category called On Track With My Budget", "How much have I spent this month?",
                       "Compare spending against last month", "How is my spending tracking against the plan yesterday?"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(!policy.requiresBudgetPace)
            #expect(policy.constrained(.init(tool: .budgetSummary)).purpose == nil)
            #expect(policy.violation(for: .init(tool: .expenses)) == nil)
        }
        let policy = MarinaTurnPolicy(prompt: "Is my budget on track?")
        #expect(policy.constrained(.init(operation: .comparison, tool: .budgetSummary)).purpose == nil)
        #expect(policy.constrained(.init(operation: .ranking, tool: .budgetSummary)).purpose == nil)
    }

    @Test func correctedFinancialToolRequiresTheSoleAffirmativeDomainWithoutAQuestionPrefix() {
        #expect(MarinaTurnPolicy(prompt: "Spending this month").acceptsCorrectedFinancialTool(.expenses))
        #expect(MarinaTurnPolicy(prompt: "My actual income this month").acceptsCorrectedFinancialTool(.income))
        #expect(MarinaTurnPolicy(prompt: "Income, not spending").acceptsCorrectedFinancialTool(.income))
        #expect(!MarinaTurnPolicy(prompt: "Income, not spending").acceptsCorrectedFinancialTool(.expenses))
        for tool in [MarinaDataRequest.Tool.expenses, .income, .budgetSummary, .accounts, .findRecords] {
            #expect(!MarinaTurnPolicy(prompt: "Income and spending this month").acceptsCorrectedFinancialTool(tool))
            #expect(!MarinaTurnPolicy(prompt: "").acceptsCorrectedFinancialTool(tool))
        }
        #expect(!MarinaTurnPolicy(prompt: "Spending this month").acceptsCorrectedFinancialTool(.income))
        #expect(!MarinaTurnPolicy(prompt: "Find my spending").acceptsCorrectedFinancialTool(.findRecords))
    }

    @Test func unfilteredSelectionRepairRequiresAnEntirelyUnnamedTotalsQuestion() {
        for prompt in ["How much have I spent this month?", "How much did I spend last month?",
                       "Show my total income this month.", "What is my actual income total?",
                       "Show total spending across all my cards this month.",
                       "How much income have I received across the whole workspace this month?",
                       "Cuánto he gastado este mes?", "Muestra el total de ingresos este mes.",
                       "Cuánto he gastado en todas mis tarjetas este mes?"] {
            #expect(MarinaTurnPolicy(prompt: prompt).permitsUnfilteredSelectionRepair)
        }
        for prompt in ["", "How much did I spend at Apple this month?", "How much did I spend on Apple Card?",
                       "Show total income from Salary", "Show spending on the card named Total",
                       "How much did I spend at Spending?", "Show total spending for Travel across the whole workspace",
                       "Show total spending Apple across all cards", "Show total spending at 🍵 across all cards",
                       "Show total spending on \"Income\"", "Show total spending on ‘Total’",
                       "How much did I spend on all cards except Apple?", "Compare total spending this month with last month",
                       "And how much income was planned for this month?", "Show that spending total", "What about total income?",
                       "Show total spending and income", "Show total spending. Use Apple Card.",
                       "Show the highest spending category", "Show my account balance total", "How much did I spend yesterday?",
                       "Cuánto he gastado en Apple?", "Muestra el total de ingresos de Salario"] {
            #expect(!MarinaTurnPolicy(prompt: prompt).permitsUnfilteredSelectionRepair)
        }
    }

    @Test func genericFinancialNounsDoNotBecomeInventedCategoryNames() {
        for (prompt, name) in [
            ("Which category has the highest spending this month?", "spending"),
            ("Which category has the highest expenses this month?", "expenses"),
            ("Show my recent transactions", "transactions"),
            ("Show the totals this month", "totals"),
            ("Show all account balances", "balances"),
            ("Que categoria tiene mas gastos este mes?", "gastos"),
            ("Muestra mis transacciones recientes", "transacciones"),
            ("Muestra los saldos de mis cuentas", "saldos")
        ] {
            #expect(MarinaTurnPolicy(prompt: prompt).ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: name)))
        }
        for prompt in ["Show the category Spending", "Show the category named Spending", "Show the category called Spending",
                       "Show spending from Spending", "Show the category \"Spending\""] {
            #expect(!MarinaTurnPolicy(prompt: prompt).ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: "Spending")))
        }
        #expect(!MarinaTurnPolicy(prompt: "Muestra la categoria Gastos").ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: "Gastos")))
        #expect(MarinaTurnPolicy(prompt: "Show all spending, not category Spending").ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: "Spending")))
        #expect(!MarinaTurnPolicy(prompt: "Show my expenses").ignoresNamedLookup(.init(tool: .findRecords, search: "Spending Plan")))
    }

    @Test func genericRecordNounsDoNotBecomeNamesButExplicitNamesAndInventoryRemainAvailable() {
        for (prompt, name, kind) in [
            ("How much did I spend this month?", "workspace", "workspace"),
            ("Am I on track with my budget this month?", "budget", "budget"),
            ("Show my category spending", "category", "category"),
            ("Show my card spending", "card", "card"),
            ("Muestra mis ingresos", "ingresos", "incomeSource")
        ] {
            #expect(MarinaTurnPolicy(prompt: prompt).ignoresNamedLookup(.init(tool: .findRecords, recordKind: kind, search: name)))
        }
        for prompt in ["Show the card called Budget", "Show the card named Budget", "Show the card \"Budget\"",
                       "Muestra la tarjeta llamada Budget"] {
            #expect(!MarinaTurnPolicy(prompt: prompt).ignoresNamedLookup(.init(tool: .findRecords, recordKind: "card", search: "Budget")))
        }
        #expect(!MarinaTurnPolicy(prompt: "List my cards").ignoresNamedLookup(.init(operation: .inventory, tool: .findRecords, recordKind: "card")))
        #expect(!MarinaTurnPolicy(prompt: "").ignoresNamedLookup(.init(tool: .findRecords, recordKind: "card", search: "Budget")))
        #expect(!MarinaTurnPolicy(prompt: "Show Apple spending").ignoresNamedLookup(.init(tool: .findRecords, search: "Apple")))
    }

    @Test func oneCardAmountNormalizesOnlyRedundantCardRanking() {
        let ranking = MarinaDataRequest(operation: .ranking, tool: .expenses, expenseMeasure: .spending,
            startDate: "2026-09-01", endDate: "2026-09-30", cardID: "card", scope: .variable, grouping: .card)
        let amount = MarinaTurnPolicy(prompt: "How much did I spend on Blue Card?").constrained(ranking)
        #expect(amount.operation == .summary && amount.grouping == .none)
        #expect(amount.cardID == "card" && amount.scope == .variable && amount.expenseMeasure == .spending)
        #expect(amount.startDate == ranking.startDate && amount.endDate == ranking.endDate)
        for prompt in ["Show the spending ranking by card", "How much does each card rank?", "List card spending",
                       "How much is each card's share?", "Compare Blue Card with Apple Card"] {
            let unchanged = MarinaTurnPolicy(prompt: prompt).constrained(ranking) == ranking
            #expect(unchanged)
        }
        var categoryRanking = ranking
        categoryRanking.grouping = .category
        #expect(MarinaTurnPolicy(prompt: "How much did I spend?").constrained(categoryRanking).operation == .ranking)
        var allCards = ranking
        allCards.cardID = nil
        #expect(MarinaTurnPolicy(prompt: "How much did I spend?").constrained(allCards).operation == .ranking)
    }

    @Test func summaryAccountActivityUsesExplicitNewPeriodWhileBalanceKeepsItsLedgerScope() {
        let account = MarinaDataRequest(tool: .accounts, allTime: true,
            startDate: "2026-09-01", endDate: "2026-09-30", accountID: "rainy", scope: .savings)
        let activity = MarinaTurnPolicy(prompt: "Show Rainy Day account activity this month.").constrained(account)
        #expect(activity.operation == .summary && activity.accountID == "rainy" && activity.scope == .savings)
        #expect(activity.relativePeriod == .currentMonth && activity.startDate == nil && activity.endDate == nil && !activity.allTime)
        let balance = MarinaTurnPolicy(prompt: "Show Rainy Day balance this month.").constrained(account)
        let preservesBalance = balance == account
        #expect(preservesBalance)
    }

    @Test func explicitPairedPeriodsRequireComparisonWithoutHijackingOtherRequests() {
        for prompt in ["Compare this month's spending on that card with last month.",
                       "Compare income this month versus last month.", "Compara gastos de este mes con el mes pasado."] {
            #expect(MarinaTurnPolicy(prompt: prompt).requiresPeriodComparison)
        }
        for prompt in ["Show spending this month.", "Compare categories this month versus last month.",
                       "List transactions this month versus last month.", "Do not compare this month with last month.",
                       "Show planned-to-actual income progress this month.", "Compare this month with last month and show income.",
                       "Compare this month with last month; show savings.", "Compare September 2026 with last month."] {
            #expect(!MarinaTurnPolicy(prompt: prompt).requiresPeriodComparison)
        }
    }

    @Test func explicitNewTopicAndFullQuestionsDoNotInheritAnOldClarificationPeriod() {
        let original = "How much did I spend at Apple last month?"
        let income = MarinaTurnPolicy(prompt: "Show my income this month.")
        #expect(income.explicitlyChangesFinancialTopic(from: original, to: .income))
        #expect(!income.explicitlyChangesFinancialTopic(from: original, to: .expenses))
        #expect(!income.shouldRetainPendingPeriod(from: original))
        let repeated = MarinaTurnPolicy(prompt: "How much did I spend on Apple Card?")
        #expect(!repeated.explicitlyChangesFinancialTopic(from: original, to: .expenses))
        #expect(!repeated.shouldRetainPendingPeriod(from: original))
        let reply = MarinaTurnPolicy(prompt: "I mean the merchant, not Apple Card.")
        #expect(!reply.explicitlyChangesFinancialTopic(from: original, to: .income))
        #expect(reply.shouldRetainPendingPeriod(from: original))
        #expect(!MarinaTurnPolicy(prompt: "Yes").explicitlyChangesFinancialTopic(from: original, to: .income))
        #expect(MarinaTurnPolicy(prompt: "And how much was spent that month?").shouldRetainPendingPeriod(from: original))
    }

    @Test func restoredAmbiguityNeedsAnExplicitCandidateChoice() {
        let candidates = [(kind: "card", name: "Apple Card"), (kind: "merchant", name: "Apple")]
        for prompt in ["Yes", "How much did I spend at Apple this month?"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            for candidate in candidates {
                #expect(!policy.confirmsPendingCandidate(kind: candidate.kind, name: candidate.name,
                                                        candidates: candidates, ambiguousSearch: "Apple"))
            }
        }
        let merchant = MarinaTurnPolicy(prompt: "I mean the merchant, not Apple Card.")
        #expect(merchant.confirmsPendingCandidate(kind: "merchant", name: "Apple", candidates: candidates, ambiguousSearch: "Apple"))
        #expect(!merchant.confirmsPendingCandidate(kind: "card", name: "Apple Card", candidates: candidates, ambiguousSearch: "Apple"))
        let sameKind = [(kind: "card", name: "Blue Rewards"), (kind: "card", name: "Blue Travel")]
        #expect(!MarinaTurnPolicy(prompt: "The card").confirmsPendingCandidate(kind: "card", name: "Blue Rewards",
                                                                            candidates: sameKind, ambiguousSearch: "Blue"))
        #expect(MarinaTurnPolicy(prompt: "Blue Rewards").confirmsPendingCandidate(kind: "card", name: "Blue Rewards",
                                                                               candidates: sameKind, ambiguousSearch: "Blue"))
    }

    @Test func offeredPunctuationAndOverlappingNamesResolveWithoutSelectingNegatedNames() {
        let candidates = [(kind: "merchant", name: "DoorDash"),
                          (kind: "merchant", name: "DoorDash - BevMo!"),
                          (kind: "merchant", name: "DoorDash - BevMo! Delivery"),
                          (kind: "merchant", name: "DoorDash - Market")]
        for prompt in ["DoorDash - BevMo!", "The DoorDash - BevMo! one", "DoorDash BevMo"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.confirmsPendingCandidate(kind: "merchant", name: "DoorDash - BevMo!", candidates: candidates, ambiguousSearch: "DoorDash"))
            #expect(!policy.confirmsPendingCandidate(kind: "merchant", name: "DoorDash", candidates: candidates, ambiguousSearch: "DoorDash"))
        }
        for prompt in ["Not DoorDash - BevMo!", "Not DoorDash BevMo", "Everything except DoorDash - BevMo!"] {
            #expect(!MarinaTurnPolicy(prompt: prompt).confirmsPendingCandidate(kind: "merchant", name: "DoorDash - BevMo!", candidates: candidates, ambiguousSearch: "DoorDash"))
        }
        #expect(!MarinaTurnPolicy(prompt: "The merchant, but not DoorDash - BevMo!").confirmsPendingCandidate(
            kind: "merchant", name: "DoorDash - BevMo!", candidates: [(kind: "merchant", name: "DoorDash - BevMo!")], ambiguousSearch: "DoorDash"))
        #expect(MarinaTurnPolicy(prompt: "The merchant DoorDash - BevMo!").confirmsPendingCandidate(
            kind: "merchant", name: "DoorDash - BevMo!", candidates: candidates, ambiguousSearch: "DoorDash - BevMo!"))
    }

    @Test func typeOnlyClarificationCannotSilentlySubstituteAnotherNamedTarget() {
        let candidates = [(kind: "card", name: "Apple Card"), (kind: "merchant", name: "Apple")]
        for prompt in ["The merchant Target", "The merchant called Target", "The merchant named Costco", "El comercio Target",
                       "The merchant October", "The merchant called October", "The merchant Target on October 17, 2026"] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(!policy.confirmsOnlyPendingKind("merchant"))
            #expect(!policy.confirmsPendingCandidate(kind: "merchant", name: "Apple", candidates: candidates, ambiguousSearch: "Apple"))
        }
        for prompt in ["The merchant, please.", "I mean the merchant, not Apple Card.", "The merchant this month.", "El comercio, por favor.",
                       "I mean the merchant, only on October 17, 2026."] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.confirmsOnlyPendingKind("merchant"))
            #expect(policy.confirmsPendingCandidate(kind: "merchant", name: "Apple", candidates: candidates, ambiguousSearch: "Apple"))
        }
    }

    @Test func currentSpanishPeriodDoesNotMeanReceivedIncome() {
        let original = MarinaDataRequest(tool: .income, state: .all)
        #expect(MarinaTurnPolicy(prompt: "Muestra los ingresos del mes actual.").constrained(original).state == .all)
        #expect(MarinaTurnPolicy(prompt: "Muestra los ingresos previstos del mes actual.").constrained(original).state == .planned)
        #expect(MarinaTurnPolicy(prompt: "Muestra los ingresos recibidos del mes actual.").constrained(original).state == .actual)
    }

    @Test func explicitNewPeriodOverridesStaleDatesButPreservesComparisonsAndAccountBalances() {
        let stale = MarinaDataRequest(tool: .expenses, allTime: true, startDate: "2026-09-01", endDate: "2026-09-30")
        let policy = MarinaTurnPolicy(prompt: "Show spending this month.")
        let current = policy.constrained(stale)
        #expect(current.relativePeriod == .currentMonth && current.startDate == nil && current.endDate == nil && !current.allTime)
        for prompt in ["Compare this month with last month", "Show spending during September 2025"] {
            let unchanged = MarinaTurnPolicy(prompt: prompt).constrained(stale) == stale
            #expect(unchanged)
        }
        let account = MarinaDataRequest(tool: .accounts, allTime: true, scope: .savings)
        let unchangedBalance = policy.constrained(account) == account
        #expect(unchangedBalance)
        var activity = account
        activity.operation = .transactions
        #expect(policy.constrained(activity).relativePeriod == .currentMonth)
    }

    @Test func genericWholeWorkspaceIncomeLookupsCannotInventASource() {
        let policy = MarinaTurnPolicy(prompt: "Show actual income across the whole workspace.")
        for name in ["income", "workspace"] {
            #expect(policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "incomeSource", search: name)))
        }
        for prompt in ["Show income from Workspace across the whole workspace.",
                       "Show income for the source Workspace across the whole workspace.",
                       "Show income for \"Workspace\" across the whole workspace."] {
            #expect(!MarinaTurnPolicy(prompt: prompt).ignoresNamedLookup(.init(tool: .findRecords, recordKind: "incomeSource", search: "Workspace")))
        }
    }

    @Test func lookupSearchRemovesOnlyUnmentionedTypeSuffixesFromTheUsersLiteralName() {
        #expect(MarinaTurnPolicy(prompt: "How much did I spend at Apple this month?").lookupSearch(proposed: "Apple Card") == "Apple")
        #expect(MarinaTurnPolicy(prompt: "Show Dining spending.").lookupSearch(proposed: "Dining Category") == "Dining")
        #expect(MarinaTurnPolicy(prompt: "Show Travel.").lookupSearch(proposed: "Travel Budget") == "Travel")
        #expect(MarinaTurnPolicy(prompt: "Show Rainy Day.").lookupSearch(proposed: "Rainy Day Savings Account") == "Rainy Day")
        #expect(MarinaTurnPolicy(prompt: "Show Shared.").lookupSearch(proposed: "Shared Reconciliation Account") == "Shared")
        #expect(MarinaTurnPolicy(prompt: "Gastos en CAFÉ.").lookupSearch(proposed: "Café Tarjeta") == "Café")
        #expect(MarinaTurnPolicy(prompt: "Show cafe spending.").lookupSearch(proposed: "Café Card") == "Café")
    }

    @Test func lookupSearchPreservesExplicitNamesKindsUnmatchedNamesAndWordBoundaries() {
        #expect(MarinaTurnPolicy(prompt: "Show Apple Card spending.").lookupSearch(proposed: "Apple Card") == "Apple Card")
        #expect(MarinaTurnPolicy(prompt: "I mean the Apple card.").lookupSearch(proposed: "Apple Card") == "Apple Card")
        #expect(MarinaTurnPolicy(prompt: "Show the card named Apple.").lookupSearch(proposed: "Apple Card") == "Apple Card")
        #expect(MarinaTurnPolicy(prompt: "Show Pineapple spending.").lookupSearch(proposed: "Apple Card") == "Apple Card")
        #expect(MarinaTurnPolicy(prompt: "Show Apple spending.").lookupSearch(proposed: "Travel Card") == "Travel Card")
        #expect(MarinaTurnPolicy(prompt: "Show Apple spending.").lookupSearch(proposed: "AppleCard") == "AppleCard")
        #expect(MarinaTurnPolicy(prompt: "Use Apple, not Apple Card.").lookupSearch(proposed: "Apple Card") == "Apple")
        #expect(MarinaTurnPolicy(prompt: "Not Apple; show Travel.").lookupSearch(proposed: "Apple Card") == "Apple Card")
        #expect(MarinaTurnPolicy(prompt: "").lookupSearch(proposed: "Apple Card") == "Apple Card")
    }

    @Test func explicitIncomeStateCorrectsSpuriousProgressWithoutChangingScopeOrDates() {
        let request = MarinaDataRequest(purpose: .incomeProgress, tool: .income,
            startDate: "2026-10-01", endDate: "2026-10-31", cardID: "selected", state: .all)
        let planned = MarinaTurnPolicy(prompt: "And how much income was planned for this month?").constrained(request)
        #expect(planned.state == .planned && planned.purpose == nil)
        #expect(planned.cardID == "selected" && planned.relativePeriod == .currentMonth)
        #expect(planned.startDate == nil && planned.endDate == nil)
        let received = MarinaTurnPolicy(prompt: "How much income was received this month?").constrained(request)
        #expect(received.state == .actual && received.purpose == nil)
        let progress = MarinaTurnPolicy(prompt: "Show my planned-to-actual income progress for that month.")
            .constrained(.init(tool: .income, state: .planned))
        #expect(progress.state == .all && progress.purpose == .incomeProgress)
        #expect(MarinaTurnPolicy(prompt: "Los ingresos previstos este mes").constrained(request).state == .planned)
    }

    @Test func incomeStateCorrectionPreservesComparisonsListsAveragesAndNegation() {
        var comparison = MarinaDataRequest(operation: .comparison, tool: .income, state: .all)
        comparison.comparisonPeriod = .previousMonth
        let planned = MarinaTurnPolicy(prompt: "How much income was planned this month?")
        let preservesComparison = planned.constrained(comparison) == comparison
        #expect(preservesComparison)
        let list = MarinaDataRequest(operation: .transactions, tool: .income, state: .all, offset: 5)
        let preservedList = planned.constrained(list)
        #expect(preservedList.operation == .transactions && preservedList.offset == 5 && preservedList.state == .all)
        let average = MarinaDataRequest(periodUnit: .month, tool: .income, state: .all)
        let preservedAverage = planned.constrained(average)
        #expect(preservedAverage.periodUnit == .month && preservedAverage.state == .all)
        let request = MarinaDataRequest(purpose: .incomeProgress, tool: .income, state: .all)
        for prompt in ["Not planned income", "Compare planned income with last month", "Average planned income", "List planned income"] {
            let unchanged = MarinaTurnPolicy(prompt: prompt).constrained(request) == request
            #expect(unchanged)
        }
        let expenses = MarinaDataRequest(tool: .expenses)
        let preservedExpenses = planned.constrained(expenses)
        #expect(preservedExpenses.state == .all && preservedExpenses.purpose == nil)
    }

    @Test func genericFollowUpFlagRequiresContinuationAndRejectsNewTargetsOrScope() {
        for prompt in ["And how much income was planned for this month?",
                       "Show my planned-to-actual income progress for that month.",
                       "What about actual income?", "Y los ingresos previstos de ese mes?"] {
            #expect(MarinaTurnPolicy(prompt: prompt).isContextualFinancialFollowUp)
        }
        for prompt in ["How much income was planned this month?", "And income from Acme this month?",
                       "Show that card's planned income", "And planned income in the new budget?",
                       "And income across the whole workspace?", "And income on all cards?",
                       "And income for the Salary source?", "Compare that month's income with last month",
                       "And not planned income", "And Apple income?", "Show that category"] {
            #expect(!MarinaTurnPolicy(prompt: prompt).isContextualFinancialFollowUp)
        }
    }

    @Test func authoritativeUniversalsRemoveOnlyTheUnrequestedIndividualSelection() {
        let policy = MarinaTurnPolicy(prompt: "Show all cards in Dining last month.")
        let original = MarinaDataRequest(tool: .expenses, startDate: "2026-09-01", endDate: "2026-09-30",
            cardID: "apple", categoryID: "dining", search: "Coffee", sort: .oldest, offset: 5, limit: 5)
        var expected = original
        expected.cardID = nil
        expected.relativePeriod = .previousMonth
        expected.startDate = nil
        expected.endDate = nil
        let preservesOtherFilters = policy.constrained(original) == expected
        #expect(preservesOtherFilters)
        #expect(policy.ignoresSelection(kind: "card", for: original))
        #expect(!policy.ignoresSelection(kind: "category", for: original))
        #expect(policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "card", search: "Apple")))
        #expect(!policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: "Dining")))
        #expect(!policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "card")))

        let accounts = MarinaTurnPolicy(prompt: "Todas mis cuentas de conciliación.")
        let wrongAccount = MarinaDataRequest(tool: .accounts, accountID: "savings", scope: .savings)
        let corrected = accounts.constrained(wrongAccount)
        #expect(corrected.accountID == nil && corrected.scope == .reconciliation)
        #expect(accounts.ignoresSelection(kind: "card", for: wrongAccount))
        #expect(!accounts.ignoresSelection(kind: "unknown", for: wrongAccount))
    }

    @Test func comparisonsExclusionsAndMultipleScopesNeverBroadenAutomatically() {
        let request = MarinaDataRequest(tool: .expenses, cardID: "apple")
        for prompt in ["Compare all cards against Apple Card.", "All cards except Apple Card.",
                       "All cards and the Dining category.", "All cards plus Apple Card.",
                       "All cards, not the merchant.", "All cards and savings accounts.",
                       "Todas mis tarjetas excepto Apple Card."] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            let unchanged = policy.constrained(request) == request
            #expect(unchanged)
            #expect(!policy.ignoresSelection(kind: "card", for: request))
            #expect(!policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "card", search: "Apple")))
        }
        let policy = MarinaTurnPolicy(prompt: "All cards this month.")
        var comparison = request
        comparison.operation = .comparison
        let preservesComparison = policy.constrained(comparison) == comparison
        #expect(preservesComparison)
        #expect(!policy.ignoresSelection(kind: "card", for: comparison))
        comparison.operation = .summary
        comparison.comparisonFilter = .init(cardID: "other")
        let preservesComparisonFilter = policy.constrained(comparison) == comparison
        #expect(preservesComparisonFilter)
    }

    @Test func periodCueDistinguishesNoOverrideFromExplicitOrAmbiguousNewDates() {
        for prompt in ["Apple last month", "Apple el mes pasado", "Apple mes anterior"] {
            #expect(MarinaTurnPolicy(prompt: prompt).periodCue == .relative(.previousMonth))
        }
        #expect(MarinaTurnPolicy(prompt: "The merchant this month.").periodCue == .relative(.currentMonth))
        #expect(MarinaTurnPolicy(prompt: "La tarjeta este mes.").periodCue == .relative(.currentMonth))
        #expect(MarinaTurnPolicy(prompt: "Income year-to-date").periodCue == .relative(.yearToDate))
        #expect(MarinaTurnPolicy(prompt: "Los próximos siete días").periodCue == .relative(.nextSevenDays))
        #expect(MarinaTurnPolicy(prompt: "The merchant, not Apple Card.").periodCue == .none)
        for prompt in ["September 2026", "2026-09-01 to 2026-09-30", "Last month versus this month",
                       "Not last month", "Last month and September", "Last week", "All time", "Yesterday"] {
            #expect(MarinaTurnPolicy(prompt: prompt).periodCue == .other)
        }
    }

    @Test func explicitAllCardsRejectsOnlyCardFiltersAndNamedCardLookups() {
        for prompt in ["Show spending across all my cards in the Dining category.", "Gastos de todas mis tarjetas en la categoría Dining."] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.violation(for: .init(tool: .expenses, cardID: "card")) != nil)
            #expect(policy.violation(for: .init(tool: .expenses, categoryID: "dining")) == nil)
            #expect(policy.violation(for: .init(tool: .findRecords, recordKind: "card", search: "Apple")) != nil)
            #expect(policy.violation(for: .init(tool: .findRecords, recordKind: "category", search: "Dining")) == nil)
            var comparison = MarinaDataRequest(operation: .comparison, tool: .expenses)
            comparison.comparisonFilter = .init(cardID: "card")
            #expect(policy.violation(for: comparison) == nil)
            comparison.comparisonFilter = .init(categoryID: "dining")
            #expect(policy.violation(for: comparison) == nil)
        }
    }

    @Test func allTransactionsAndUnrelatedWordPartsDoNotMeanAllCards() {
        for prompt in ["Show all transactions on Apple Card.", "All postcards in Dining.", "Not all cards, just Apple Card."] {
            #expect(MarinaTurnPolicy(prompt: prompt).violation(for: .init(tool: .expenses, cardID: "apple")) == nil)
        }
        #expect(!MarinaTurnPolicy(prompt: "Discard the previous question.").confirms(kind: "card"))
        #expect(!MarinaTurnPolicy(prompt: "Show a cardiology purchase.").confirms(kind: "card"))
    }

    @Test func explicitAllAccountsRemainScopedToTheirDomain() {
        let savings = ["Show all my savings accounts.", "Muestra todas mis cuentas de ahorro."]
        let reconciliation = ["Show all reconciliation accounts.", "Muestra todas las cuentas de conciliación."]
        for prompt in savings {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.violation(for: .init(tool: .accounts, accountID: "one", scope: .savings)) != nil)
            #expect(policy.violation(for: .init(tool: .accounts, accountID: "one", scope: .all)) != nil)
            #expect(policy.violation(for: .init(tool: .accounts, scope: .savings)) == nil)
            #expect(policy.violation(for: .init(tool: .accounts, accountID: "one", scope: .reconciliation)) == nil)
            #expect(policy.violation(for: .init(tool: .findRecords, recordKind: "savingsAccount", search: "Rainy Day")) != nil)
        }
        for prompt in reconciliation {
            let policy = MarinaTurnPolicy(prompt: prompt)
            #expect(policy.violation(for: .init(tool: .accounts, accountID: "one", scope: .reconciliation)) != nil)
            #expect(policy.violation(for: .init(tool: .accounts, scope: .reconciliation)) == nil)
            #expect(policy.violation(for: .init(tool: .accounts, accountID: "one", scope: .savings)) == nil)
            #expect(policy.violation(for: .init(tool: .findRecords, recordKind: "reconciliationAccount", search: "Shared")) != nil)
        }
    }

    @Test func wholeWorkspacePreservesCategoryMerchantAndOtherNonCardFilters() {
        for prompt in ["Food category spending across the whole workspace.", "Coffee merchant spending across my workspace.", "Gastos en la categoría Food en todo mi espacio de trabajo."] {
            let policy = MarinaTurnPolicy(prompt: prompt)
            let named = MarinaDataRequest(tool: .expenses, presetID: "preset", cardID: "card",
                categoryID: "dining", budgetID: "budget", accountID: "account", search: "Coffee")
            let constrained = policy.constrained(named)
            #expect(constrained.cardID == nil)
            #expect(constrained.categoryID == "dining" && constrained.search == "Coffee")
            #expect(constrained.budgetID == "budget" && constrained.presetID == "preset" && constrained.accountID == "account")
            #expect(policy.violation(for: constrained) == nil)
            #expect(!policy.ignoresSelection(kind: "category", for: named))
            #expect(!policy.ignoresSelection(kind: "merchant", for: named))
            #expect(!policy.ignoresSelection(kind: "savingsAccount", for: named))
            #expect(!policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "merchant", search: "Coffee")))
            #expect(!policy.ignoresNamedLookup(.init(tool: .findRecords, recordKind: "category", search: "Food")))
            #expect(policy.violation(for: .init(tool: .expenses)) == nil)
            #expect(policy.violation(for: .init(tool: .findRecords, search: "Apple")) == nil)
            #expect(policy.violation(for: .init(tool: .findRecords, recordKind: "card")) == nil)
            var comparison = MarinaDataRequest(operation: .comparison, tool: .expenses)
            comparison.comparisonFilter = .init(budgetID: "budget")
            #expect(policy.violation(for: comparison) == nil)
        }
    }

    @Test func lookupKindRequiresAnAffirmativeExplicitNoun() {
        #expect(MarinaTurnPolicy(prompt: "Apple Card spending this month.").confirms(kind: "card"))
        #expect(!MarinaTurnPolicy(prompt: "Spending at Apple this month.").confirms(kind: "merchant"))
        #expect(!MarinaTurnPolicy(prompt: "Spending at Apple this month.").confirms(kind: "card"))
        let merchant = MarinaTurnPolicy(prompt: "I mean the merchant, not Apple Card.")
        #expect(merchant.confirms(kind: "merchant"))
        #expect(!merchant.confirms(kind: "card"))
        let card = MarinaTurnPolicy(prompt: "Not the merchant but the card.")
        #expect(card.confirms(kind: "card"))
        #expect(!card.confirms(kind: "merchant"))
        let spanish = MarinaTurnPolicy(prompt: "El comercio, no la tarjeta.")
        #expect(spanish.confirms(kind: "merchant"))
        #expect(!spanish.confirms(kind: "card"))
        #expect(!MarinaTurnPolicy(prompt: "Don't use Apple Card.").confirms(kind: "card"))
        #expect(MarinaTurnPolicy(prompt: "No la tarjeta sino el comercio.").confirms(kind: "merchant"))
    }

    @Test func supportedKindNounsUseWordBoundariesAndFoldAccents() {
        let examples = [
            ("category", "La categoría Dining"), ("budget", "El presupuesto mensual"),
            ("preset", "La plantilla Rent"), ("savingsAccount", "Mis ahorros"),
            ("reconciliationAccount", "La cuenta de conciliación"), ("incomeSource", "Los ingresos de Salary"),
            ("workspace", "Mi espacio de trabajo")
        ]
        for (kind, prompt) in examples { #expect(MarinaTurnPolicy(prompt: prompt).confirms(kind: kind)) }
        #expect(!MarinaTurnPolicy(prompt: "Something unrelated").confirms(kind: "unknown"))
        #expect(!MarinaTurnPolicy(prompt: "The budgeting app").confirms(kind: "budget"))
        #expect(MarinaTurnPolicy(prompt: "  ").confirms(kind: "card"))
        #expect(MarinaTurnPolicy(prompt: "").violation(for: .init(tool: .expenses, cardID: "card")) == nil)
    }
}
