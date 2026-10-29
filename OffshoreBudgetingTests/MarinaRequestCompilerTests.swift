import Foundation
import Testing
@testable import Offshore

struct MarinaRequestCompilerTests {
    private let workspaceID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    private let cardID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!.uuidString
    private let budgetID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!.uuidString

    @Test func catalogueMapsEveryExistingReportWithoutPhraseRouting() throws {
        let context = context("requested report")
        for capability in MarinaCapability.allCases {
            var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(capability, .userText("requested report")))
            if capability.requiresGroupingSelection { patch.grouping = .set(capability == .incomeGroups ? .source : .category, .userText("report")) }
            if capability.isComparison { patch.comparisonDates = .set(.relative(.previousMonth), .userText("report")) }
            if capability == .cardSummary { patch.targets = [.init(field: .card, change: .set([.reference("r1")], .contextReference("r1")))] }
            if [.linkedCards, .linkedPresets].contains(capability) { patch.targets = [.init(field: .budget, change: .set([.reference("r2")], .contextReference("r2")))] }
            let compiled = try MarinaRequestCompiler.compile(patch, context: context)
            #expect(compiled.isReady)
            #expect(compiled.request.tool == capability.tool)
            #expect(MarinaCapability.matching(compiled.request) == (capability == .rankedSpending ? .categoryRanking : capability))
            #expect(!capability.summary.isEmpty)
            #expect(compiled.request.hypotheticalSpending == nil)
        }
    }

    @Test func rankingLeafDerivesGroupingAndRestoresMeaningWithoutAnotherModelDecision() throws {
        for capability in [MarinaCapability.categoryRanking, .cardRanking, .merchantRanking] {
            var context = context("Show the top one.")
            var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(capability, .userText("top")))
            let defaults = try MarinaRequestCompiler.compile(patch, context: context)
            #expect(defaults.request.grouping == capability.fixedGrouping)
            #expect(defaults.request.sort == .largest && defaults.request.limit == 5)
            #expect(capability.usesGrouping && !capability.requiresGroupingSelection)
            patch.limit = .set(1, .userText("one"))
            let first = try MarinaRequestCompiler.compile(patch, context: context)
            #expect(first.request.operation == .ranking && first.request.limit == 1)
            context.activeRequest = try JSONDecoder().decode(MarinaDataRequest.self, from: JSONEncoder().encode(first.request))
            let resumed = try MarinaRequestCompiler.compile(.init(base: .active), context: context)
            #expect(resumed.capability == capability && resumed.request == first.request)
            #expect(MarinaCapability.matching(resumed.request) == capability)
        }
    }

    @Test func smallestDeltaPreservesScopeAndDatesWhileDerivingTheExtreme() throws {
        var context = context("And the lowest?")
        context.activeRequest = .init(metric: .count, chartIntent: .movementOverTime, transactionFilter: .debit,
            positiveOnly: true, operation: .transactions, tool: .expenses, expenseMeasure: .spending,
            includeFuture: true, startDate: "2026-10-01", endDate: "2026-10-31", cardID: cardID,
            scope: .variable, sort: .largest, limit: 1)
        let before = context.activeRequest
        var patch = MarinaTurnPatch(base: .active, capability: .set(.smallestExpense, .userText("lowest")))
        patch.limit = .set(20, .userText("lowest"))
        let request = try MarinaRequestCompiler.compile(patch, context: context).request
        #expect(request.cardID == cardID && request.scope == .variable && request.expenseMeasure == .spending)
        #expect(request.includeFuture && request.transactionFilter == .debit && request.chartIntent == .movementOverTime)
        #expect(request.startDate == "2026-10-01" && request.endDate == "2026-10-31")
        #expect(request.operation == .transactions && request.sort == .smallest && request.limit == 1 && request.positiveOnly == true)
        #expect(request.metric == nil, "A changed operation cannot accidentally retain a count answer focus.")
        #expect(context.activeRequest == before, "Compilation must not mutate committed context.")

        patch.measure = .set(.ledger, .userText("lowest"))
        let ledger = try MarinaRequestCompiler.compile(patch, context: context).request
        #expect(ledger.expenseMeasure == .ledger && ledger.positiveOnly == false)
    }

    @Test func keepSetAndClearAreDistinctAndNewQuestionsDoNotInheritScope() throws {
        var context = context("Show expenses for all cards, use budget impact.")
        context.activeRequest = .init(merchantName: "Cafe", tool: .expenses, expenseMeasure: .spending,
            startDate: "2026-09-01", endDate: "2026-09-30", cardID: cardID, scope: .variable)
        let keep = try MarinaRequestCompiler.compile(.init(base: .active), context: context)
        #expect(keep.request.cardID == cardID && keep.request.merchantName == "Cafe")
        var patch = MarinaTurnPatch(base: .active)
        patch.targets = [.init(field: .card, change: .clear(.userText("all cards")))]
        patch.measure = .set(.budgetImpact, .userText("budget impact"))
        let clear = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(clear.request.cardID == nil && clear.request.merchantName == "Cafe")
        #expect(clear.request.expenseMeasure == .budgetImpact && clear.request.scope == .variable)
        let fresh = try MarinaRequestCompiler.compile(.init(base: .newQuestion, capability: .set(.expenses, .userText("expenses"))), context: context)
        #expect(fresh.request.cardID == nil && fresh.request.merchantName == nil && fresh.request.scope == .all)
        #expect(fresh.request.startDate == "2026-10-01" && fresh.request.endDate == "2026-10-31")
    }

    @Test func earlierAndPendingBasesRemainExplicitAndSerializable() throws {
        var context = context("And the lowest?")
        let earlier = MarinaDataRequest(purpose: .cardSummary, tool: .expenses, expenseMeasure: .spending,
            startDate: "2026-06-01", endDate: "2026-06-30", cardID: cardID)
        context.earlierRequests = ["t1": earlier]
        context.pendingRequest = earlier
        let patch = MarinaTurnPatch(base: .earlier("t1"), capability: .set(.smallestExpense, .userText("lowest")))
        let restored = try JSONDecoder().decode(MarinaTurnPatch.self, from: JSONEncoder().encode(patch))
        let compiled = try MarinaRequestCompiler.compile(restored, context: context)
        #expect(compiled.request.cardID == cardID && compiled.request.startDate == "2026-06-01")
        #expect(compiled.request.expenseMeasure == .spending)
        let pending = try MarinaRequestCompiler.compile(.init(base: .pending), context: context)
        #expect(pending.request.purpose == .cardSummary && pending.request.startDate == "2026-06-01")
        #expect(throws: MarinaRequestCompiler.Failure.self) {
            try MarinaRequestCompiler.compile(.init(base: .earlier("t999")), context: context)
        }
        #expect(throws: MarinaRequestCompiler.Failure.self) {
            try MarinaRequestCompiler.compile(.init(base: .active), context: context)
        }
    }

    @Test func categoryLeaderComparisonKeepsTheFirstPeriodAndResolvesJuneInItsYear() throws {
        var context = context("What about in June? Can you compare?")
        context.now = date("2027-01-05")
        context.activeRequest = .init(operation: .ranking, tool: .expenses, expenseMeasure: .spending,
            startDate: "2026-10-01", endDate: "2026-10-31", grouping: .category, sort: .largest, limit: 1)
        var patch = MarinaTurnPatch(base: .active, capability: .set(.leaderComparison, .userText("compare")))
        patch.comparisonDates = .set(.month(year: nil, month: 6), .userText("June"))
        let request = try MarinaRequestCompiler.compile(patch, context: context).request
        #expect(request.operation == .comparison && request.compareLeaders == true && request.grouping == .category)
        #expect(request.startDate == "2026-10-01" && request.endDate == "2026-10-31")
        #expect(request.comparisonStartDate == "2026-06-01" && request.comparisonEndDate == "2026-06-30")
        #expect(request.categoryID == nil && request.categoryIDs == nil, "A previous winning category is not a selected category filter.")
        #expect(request.expenseMeasure == .spending)
    }

    @Test func selectedCategoryComparisonRemainsTheSameSubject() throws {
        var context = context("Compare Dining with June 2026.")
        let categoryID = UUID().uuidString
        context.activeRequest = .init(tool: .expenses, startDate: "2026-10-01", endDate: "2026-10-31", categoryID: categoryID)
        var patch = MarinaTurnPatch(base: .active, capability: .set(.spendingComparison, .userText("Compare")))
        patch.comparisonDates = .set(.month(year: 2026, month: 6), .userText("June 2026"))
        let result = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(result.request.compareLeaders != true && result.request.grouping == .none)
        #expect(result.request.categoryID == categoryID && result.request.comparisonFilter?.categoryID == categoryID)
    }

    @Test func comparisonNeedsAnotherPeriodUnlessItSelectsADifferentSubject() throws {
        var context = context("Compare that card with the other card.")
        context.activeRequest = .init(tool: .expenses, startDate: "2026-10-01", endDate: "2026-10-31", cardID: cardID)
        var patch = MarinaTurnPatch(base: .active, capability: .set(.spendingComparison, .userText("Compare")))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        context.entities.append(.init(reference: "r3", workspaceID: workspaceID, kind: "card", id: UUID().uuidString, name: "Other Card"))
        patch.comparisonTargets = [.init(field: .card, change: .set([.reference("r3")], .contextReference("r3")))]
        let separate = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(separate.request.cardID != separate.request.comparisonFilter?.cardID)
        #expect(separate.request.comparisonStartDate == nil && separate.request.comparisonPeriod == nil)
        context.activeRequest = separate.request
        let resumed = try MarinaRequestCompiler.compile(.init(base: .active), context: context)
        #expect(resumed.request.comparisonFilter == separate.request.comparisonFilter)
        patch.comparisonTargets = [.init(field: .card, change: .set([.reference("r1")], .contextReference("r1")))]
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
    }

    @Test func defaultBudgetDatesRemainIndependentFromExpenseFilters() throws {
        let context = context("Use October for the period.")
        var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.rankedSpending, .userText("period")))
        patch.grouping = .set(.category, .userText("period"))
        patch.targets = [.init(field: .periodBudget, change: .set([.reference("r2")], .contextReference("r2")))]
        let result = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(result.request.periodBudgetID == budgetID && result.request.budgetID == nil)
        #expect(result.request.startDate == nil && result.request.relativePeriod == nil)
        #expect(result.dateOrigin == .budgetDefault)
        patch.dates = .set(.range(start: "2026-06-01", end: "2026-06-30"), .userText("period"))
        let explicit = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(explicit.request.periodBudgetID == nil && explicit.request.startDate == "2026-06-01")
        #expect(explicit.dateOrigin == .explicit)
    }

    @Test func unresolvedNamesCannotBecomeExecutableAndFillWithoutReparsing() throws {
        var context = context("Compare Cafe expenses on Blue Card with June.")
        var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.spendingComparison, .userText("Compare")))
        patch.targets = [
            .init(field: .card, change: .set([.name("Blue Card")], .userText("Blue Card"))),
            .init(field: .merchant, change: .set([.name("Cafe")], .userText("Cafe")))
        ]
        patch.comparisonDates = .set(.month(year: 2026, month: 6), .userText("June"))
        var result = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(!result.isReady && result.unresolvedTargets.count == 2)
        result = try MarinaRequestCompiler.resolving("primary.card.0", with: "r1", in: result, context: context)
        #expect(!result.isReady && result.request.cardID == cardID)
        #expect(result.request.comparisonFilter?.cardID == cardID)
        context.entities.append(.init(reference: "r3", workspaceID: workspaceID, kind: "merchant", id: "Cafe", name: "Cafe"))
        result = try MarinaRequestCompiler.resolving("primary.merchant.0", with: "r3", in: result, context: context)
        #expect(result.isReady && result.request.merchantName == "Cafe" && result.request.search == nil)
        #expect(result.request.comparisonFilter?.merchantName == "Cafe")
        #expect(result.request.comparisonStartDate == "2026-06-01")
        #expect(throws: MarinaRequestCompiler.Failure.self) {
            try MarinaRequestCompiler.resolving("primary.merchant.0", with: "r3", in: result, context: context)
        }
    }

    @Test func foreignUnknownAndWrongKindReferencesNeverBroadenTheRequest() throws {
        var context = context("Show my card.")
        context.entities.append(.init(reference: "r3", workspaceID: UUID(), kind: "card", id: UUID().uuidString, name: "Foreign"))
        for reference in ["r999", "r3", "r2"] {
            var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.cardSummary, .userText("card")))
            patch.targets = [.init(field: .card, change: .set([.reference(reference)], .userText("card")))]
            #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        }
        #expect(throws: MarinaRequestCompiler.Failure.self) {
            try MarinaRequestCompiler.compile(.init(base: .newQuestion, capability: .set(.cardSummary, .userText("card"))), context: context)
        }
    }

    @Test func pendingChangesPreserveUnresolvedSlotsUntilTheyAreExplicitlyFilled() throws {
        var context = context("Show Cafe expenses on Blue Card.")
        var original = MarinaTurnPatch(base: .newQuestion, capability: .set(.transactions, .userText("expenses")))
        original.targets = [.init(field: .card, change: .set([.name("Blue Card")], .userText("Blue Card"))),
                            .init(field: .merchant, change: .set([.name("Cafe")], .userText("Cafe")))]
        let pending = try MarinaRequestCompiler.compile(original, context: context)
        context.pendingCompilation = pending
        context.pendingRequest = pending.request
        context.prompt = "The merchant, please."
        let unchanged = try MarinaRequestCompiler.compile(.init(base: .pending), context: context)
        #expect(!unchanged.isReady && unchanged.unresolvedTargets == pending.unresolvedTargets)

        context.prompt = "Use November instead."
        var changedDates = MarinaTurnPatch(base: .pending)
        changedDates.dates = .set(.month(year: 2026, month: 11), .userText("November"))
        let dated = try MarinaRequestCompiler.compile(changedDates, context: context)
        #expect(!dated.isReady && dated.unresolvedTargets == pending.unresolvedTargets)
        #expect(dated.request.startDate == "2026-11-01" && dated.request.endDate == "2026-11-30")

        context.entities.append(.init(reference: "r3", workspaceID: workspaceID, kind: "merchant", id: "Cafe", name: "Cafe"))
        context.prompt = "Cafe"
        var chosen = MarinaTurnPatch(base: .pending)
        chosen.targets = [.init(field: .merchant, change: .set([.reference("r3")], .contextReference("r3")))]
        let merchant = try MarinaRequestCompiler.compile(chosen, context: context)
        #expect(!merchant.isReady && merchant.unresolvedTargets.map(\.field) == [.card])
        #expect(merchant.request.merchantName == "Cafe" && merchant.request.cardID == nil)
        context.pendingCompilation = merchant
        context.prompt = "Blue Card"
        chosen.targets = [.init(field: .card, change: .set([.reference("r1")], .contextReference("r1")))]
        let complete = try MarinaRequestCompiler.compile(chosen, context: context)
        #expect(complete.isReady && complete.request.cardID == cardID && complete.request.merchantName == "Cafe")
    }

    @Test func sourceSpansAndContextReferencesMustExist() throws {
        let context = context("Show expenses.")
        for source in [MarinaPatchSource.userText("income"), .userText(""), .contextReference("t999")] {
            #expect(throws: MarinaRequestCompiler.Failure.self) {
                try MarinaRequestCompiler.compile(.init(base: .newQuestion, capability: .set(.expenses, source)), context: context)
            }
        }
        var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.expenses, .userText("expenses")))
        patch.targets = [.init(field: .merchant, change: .set([.name("Personal")], .userText("expenses")))]
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
    }

    @Test func validContextReferenceCannotInventScalarChangesOrUnrelatedTargets() throws {
        var context = context("Show expenses.")
        context.earlierRequests["t1"] = .init(tool: .expenses, startDate: "2026-06-01", endDate: "2026-06-30", cardID: cardID)
        var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.expenses, .userText("expenses")))
        patch.scope = .set(.planned, .contextReference("r1"))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        patch.scope = .keep
        patch.targets = [.init(field: .budget, change: .set([.reference("r2")], .contextReference("r1")))]
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        patch.targets = [.init(field: .card, change: .set([.reference("r1")], .contextReference("t1")))]
        patch.dates = .set(.relative(.currentMonth), .contextReference("t1"))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        patch.dates = .set(.query("t1"), .contextReference("t1"))
        let copied = try MarinaRequestCompiler.compile(patch, context: context)
        #expect(copied.request.cardID == cardID && copied.request.startDate == "2026-06-01")
        patch.targets = [.init(field: .card, change: .clear(.contextReference("r1")))]
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
    }

    @Test func availabilityAndCardGroupingUseDistinctCapabilities() throws {
        let context = context("Show over or near categories, then expenses by card.")
        var availability = MarinaTurnPatch(base: .newQuestion, capability: .set(.categoryAvailability, .userText("categories")))
        availability.availabilityFilter = .set(.overOrNear, .userText("over or near"))
        let categories = try MarinaRequestCompiler.compile(availability, context: context)
        #expect(categories.request.tool == .budgetSummary && categories.request.purpose == .categoryAvailability)
        #expect(categories.request.availabilityFilter == .overOrNear)
        var grouped = MarinaTurnPatch(base: .newQuestion, capability: .set(.rankedSpending, .userText("expenses by card")))
        grouped.grouping = .set(.card, .userText("by card"))
        let cards = try MarinaRequestCompiler.compile(grouped, context: context)
        #expect(cards.request.tool == .expenses && cards.request.operation == .ranking && cards.request.grouping == .card)
        #expect(cards.request.cardID == nil && cards.request.budgetID == nil && cards.request.purpose == nil)
    }

    @Test func invalidDatesAndConflictingTargetsFailBeforeExecution() throws {
        let context = context("Show expenses in February.")
        var patch = MarinaTurnPatch(base: .newQuestion, capability: .set(.expenses, .userText("expenses")))
        patch.dates = .set(.range(start: "2026-02-30", end: "2026-03-01"), .userText("February"))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        patch.dates = .set(.range(start: "2026-03-02", end: "2026-03-01"), .userText("February"))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
        patch.dates = .keep
        patch.targets = [.init(field: .card, change: .clear(.userText("expenses"))), .init(field: .card, change: .clear(.userText("expenses")))]
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(patch, context: context) }
    }

    @Test func incompatibleMetricCannotSilentlyBecomeAGenericTotal() throws {
        let context = context("Show actual savings.")
        var wrong = MarinaTurnPatch(base: .newQuestion, capability: .set(.expenses, .userText("actual savings")))
        wrong.metric = .set(.actualSavings, .userText("actual savings"))
        #expect(throws: MarinaRequestCompiler.Failure.self) { try MarinaRequestCompiler.compile(wrong, context: context) }
        wrong.capability = .set(.savingsOutlook, .userText("actual savings"))
        let result = try MarinaRequestCompiler.compile(wrong, context: context)
        #expect(result.request.purpose == .savingsOutlook && result.request.metric == .actualSavings)
    }

    private func context(_ prompt: String) -> MarinaRequestCompiler.Context {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return .init(workspaceID: workspaceID, prompt: prompt, now: date("2026-10-17"), calendar: calendar,
            entities: [.init(reference: "r1", workspaceID: workspaceID, kind: "card", id: cardID, name: "Blue Card"),
                       .init(reference: "r2", workspaceID: workspaceID, kind: "budget", id: budgetID, name: "October")],
            defaultPeriod: .relative(.currentMonth))
    }
    private func date(_ value: String) -> Date {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)!
    }
}
