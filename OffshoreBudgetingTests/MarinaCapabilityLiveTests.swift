import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
/// Native acceptance is separate from deterministic calculation tests. These fixtures never
/// open a user's store, and disabled evaluations are not behavioral passes.
@MainActor
@Suite(.serialized)
struct MarinaCapabilityLiveTests {
    private nonisolated static var enabled: Bool { ProcessInfo.processInfo.environment["MARINA_MODEL_EVALUATION"] == "1" }
    private nonisolated static var queryRenewalExperimentEnabled: Bool {
        enabled && ProcessInfo.processInfo.environment["MARINA_QUERY_RENEWAL_EXPERIMENT"] == "1"
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func categoryWinnerComparisonKeepsTheQuestionAndBothPeriods(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.categoryComparison.turns
        let first = try await ask(turns[0], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .expenses && $0.grouping == .category })
        expectWords(["Dining"], in: first)
        expectMoney(530, in: first)

        let compared = try await ask(turns[1], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.operation == .comparison && $0.compareLeaders == true && $0.grouping == .category })
        let leaders = try #require(compared.presentations?.compactMap(\.report).compactMap(\.leaders).last)
        #expect(leaders.count == 2)
        #expect(leaders[0].title == "Dining" && leaders[0].amount == 530)
        #expect(leaders[1].title == "Travel" && leaders[1].amount == 800)
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(runtime.memory?.latestFinancialQuery?.comparisonPeriod?.startDate == "2026-06-01")
        expectWords(["Dining", "Travel"], in: compared)
        expectMoney(530, in: compared)
        expectMoney(800, in: compared)
        print("MarinaCapabilities scenario=category-comparison repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func cardSummaryExtremaAndMerchantKeepScopeAndMeasure(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.cardFollowUps.turns
        let summary = try await ask(turns[0], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.purpose == .cardSummary && $0.cardID == fixture.card.id.uuidString })
        expectMoney(785, in: summary)
        let highest = try await ask(turns[1], runtime: runtime, fixture: fixture, history: &history)
        expectCardScope(runtime, fixture: fixture)
        #expect(runtime.toolRequests.contains { $0.sort == .largest && $0.limit == 1 && $0.positiveOnly == true })
        expectWords(["Restaurant"], in: highest)
        expectMoney(400, in: highest)

        let lowest = try await ask(turns[2], runtime: runtime, fixture: fixture, history: &history)
        expectCardScope(runtime, fixture: fixture)
        #expect(runtime.toolRequests.contains { $0.sort == .smallest && $0.limit == 1 && $0.positiveOnly == true })
        expectWords(["Corner shop"], in: lowest)
        expectMoney(5, in: lowest)

        let merchant = try await ask(turns[3], runtime: runtime, fixture: fixture, history: &history)
        expectCardScope(runtime, fixture: fixture)
        #expect(runtime.toolRequests.contains { $0.operation == .ranking && $0.grouping == .merchant })
        #expect(!runtime.toolRequests.contains { $0.operation == .comparison })
        expectWords(["Restaurant"], in: merchant)
        print("MarinaCapabilities scenario=card-extrema-merchant repetition=\(repetition) complete")
    }

    /// Opt-in comparison with the unchanged persistent-session scenario above. Each
    /// follow-up receives saved memory and visible history, without prior tool payloads.
    @Test(.enabled(if: queryRenewalExperimentEnabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_RENEWAL_EXPERIMENT=1."), arguments: [1, 2, 3])
    func freshQueryExperimentCategoryComparison(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let firstRuntime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.categoryComparison.turns
        let first = try await ask(turns[0], runtime: firstRuntime, fixture: fixture, history: &history)
        expectWords(["Dining"], in: first)
        expectMoney(530, in: first)

        let fresh = try freshRuntime(after: firstRuntime, fixture: fixture)
        let compared = try await ask(turns[1], runtime: fresh.runtime, fixture: fixture,
            history: &history, restoredMemory: fresh.memory)
        let query = try #require(fresh.runtime.memory?.latestFinancialQuery)
        #expect(query.selection == nil)
        #expect(query.measure == .budgetImpact)
        #expect(query.period.startDate == "2026-10-01" && query.period.endDate == "2026-10-31")
        #expect(query.comparisonPeriod?.startDate == "2026-06-01" && query.comparisonPeriod?.endDate == "2026-06-30")
        let leaders = try #require(compared.presentations?.compactMap(\.report).compactMap(\.leaders).last)
        try #require(leaders.count == 2)
        #expect(leaders[0].title == "Dining" && leaders[0].amount == 530)
        #expect(leaders[1].title == "Travel" && leaders[1].amount == 800)
        expectWords(["Dining", "Travel"], in: compared)
        expectMoney(530, in: compared)
        expectMoney(800, in: compared)
        print("MarinaQueryRenewalExperiment scenario=category-comparison repetition=\(repetition) complete")
    }

    @Test(.enabled(if: queryRenewalExperimentEnabled, "Set MARINA_MODEL_EVALUATION=1 and MARINA_QUERY_RENEWAL_EXPERIMENT=1."), arguments: [1, 2, 3])
    func freshQueryExperimentCardFollowUpsAndTopicChange(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        var runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.cardFollowUps.turns
        let summary = try await ask(turns[0], runtime: runtime, fixture: fixture, history: &history)
        expectCardScope(runtime, fixture: fixture)
        expectMoney(785, in: summary)

        for (index, name, amount) in [(1, "Restaurant", 400.0), (2, "Corner shop", 5.0), (3, "Restaurant", 400.0)] {
            let fresh = try freshRuntime(after: runtime, fixture: fixture)
            runtime = fresh.runtime
            let answer = try await ask(turns[index], runtime: runtime, fixture: fixture,
                history: &history, restoredMemory: fresh.memory)
            expectCardScope(runtime, fixture: fixture)
            #expect(runtime.memory?.latestFinancialQuery?.measure == .spending)
            #expect(!runtime.toolRequests.contains { $0.operation == .comparison })
            expectWords([name], in: answer)
            expectMoney(amount, in: answer)
        }

        let fresh = try freshRuntime(after: runtime, fixture: fixture)
        runtime = fresh.runtime
        let income = try await ask("How much income have I received this month?", runtime: runtime,
            fixture: fixture, history: &history, restoredMemory: fresh.memory)
        #expect(runtime.toolRequests.contains { $0.tool == .income && $0.state == .actual && $0.cardID == nil })
        #expect(runtime.memory?.latestFinancialQuery?.tool == .income)
        #expect(runtime.memory?.latestFinancialQuery?.selection == nil)
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(runtime.memory?.latestFinancialQuery?.period.endDate == "2026-10-31")
        expectMoney(1000, in: income)
        print("MarinaQueryRenewalExperiment scenario=card-follow-ups-topic-change repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func spendingPatternsReturnTheRequestedReport(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let patterns = try await ask(MarinaCapabilityScenarios.spendingPatterns.turns[0], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.purpose == .spendingPatterns })
        #expect(!runtime.toolRequests.contains { $0.purpose == .upcomingPresets })
        let patternReport = try #require(patterns.presentations?.compactMap(\.report).first { $0.peak != nil })
        #expect(patternReport.groups?.first?.title == "Dining")
        #expect(patternReport.merchants?.isEmpty == false)
        #expect(patternReport.frequentMerchants?.isEmpty == false)
        #expect(patterns.presentations?.count == 1)
        #expect(patterns.presentations?.first?.chartIntent != .movementOverTime)
        print("MarinaCapabilities scenario=patterns repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func categoryWarningsReturnOnlyRequestedStatuses(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let availabilityRuntime = MarinaConversationRuntime(now: { fixture.now })
        var availabilityHistory: [HomeAnswer] = []
        let availability = try await ask(MarinaCapabilityScenarios.categoryWarnings.turns[0], runtime: availabilityRuntime, fixture: fixture, history: &availabilityHistory)
        let categories = try #require(availability.presentations?.compactMap(\.report).compactMap(\.categories).last)
        #expect(Set(categories.map(\.name)) == ["Dining", "Groceries"])
        #expect(categories.contains { $0.name == "Dining" && $0.status == "over" })
        #expect(categories.contains { $0.name == "Groceries" && $0.status == "near" })
        expectWords(["Dining", "Groceries"], in: availability)
        print("MarinaCapabilities scenario=category-warnings repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func categoryAvailabilityHasItsOwnReport(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let directRuntime = MarinaConversationRuntime(now: { fixture.now })
        var directHistory: [HomeAnswer] = []
        let direct = try await ask(MarinaCapabilityScenarios.categoryAvailability.turns[0], runtime: directRuntime, fixture: fixture, history: &directHistory)
        #expect(direct.presentations?.contains { $0.report?.categories != nil } == true)
        print("MarinaCapabilities scenario=category-availability repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func greetingThenWorkspaceSummaryRemainConversational(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.greetingAndWorkspace.turns
        let greeting = try await ask(turns[0], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.isEmpty)
        expectWords(["Marina"], in: greeting)
        #expect(!(greeting.explanation ?? "").localizedCaseInsensitiveContains("identifying the workspace"))
        let summary = try await ask(turns[1], runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.toolRequests.contains { $0.tool == .budgetSummary || $0.tool == .expenses || $0.tool == .income })
        #expect(summary.presentations?.isEmpty == false)
        #expect(!(summary.explanation ?? "").localizedCaseInsensitiveContains("couldn’t find"))
        print("MarinaCapabilities scenario=greeting-workspace repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func broadAssessmentClarifiesThenReadsTheChosenTopic(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let otherRuntime = MarinaConversationRuntime(now: { fixture.now })
        var otherHistory: [HomeAnswer] = []
        let clarifier = try await ask(MarinaCapabilityScenarios.broadAssessment.turns[0], runtime: otherRuntime, fixture: fixture, history: &otherHistory)
        #expect(clarifier.explanation?.contains("?") == true)
        #expect(!otherRuntime.toolRequests.contains { $0.tool == .budgetSummary })
        let chosen = try await ask(MarinaCapabilityScenarios.broadAssessment.turns[1], runtime: otherRuntime, fixture: fixture, history: &otherHistory)
        #expect(otherRuntime.toolRequests.contains { $0.purpose == .spendingPatterns })
        #expect(chosen.presentations?.contains { $0.report?.peak != nil } == true)
        print("MarinaCapabilities scenario=conversational-intent repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: 0..<12)
    func newMetricFamiliesAreSelectableAndPresentTheirActualFacts(_ scenario: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let cases: [(String, MarinaDataRequest.Purpose?, MarinaDataRequest.MetricFocus?, Double?)] = [
            ("How much have I actually saved this month?", nil, .actualSavings, 330),
            ("What is the Max Savings for my October budget?", nil, .maxSavings, 1120),
            ("Give me the complete income, expense, and savings breakdown for my October budget.", .budgetDetails, nil, nil),
            ("Show the minimum and maximum goals and spending contributions for Dining in my October budget.", .categoryAvailability, nil, nil),
            ("Which cards are linked to my October budget?", .budgetCards, nil, nil),
            ("Which presets are linked to my October budget?", .budgetPresets, nil, nil),
            ("Show planned and received income together over time this month.", .incomeTimeline, nil, nil),
            ("Show my cumulative actual and projected savings this month.", .savingsTimeline, nil, nil),
            ("How close am I to my projected savings this month?", .savingsOutlook, nil, nil),
            ("How many debit expenses did I record on Apple Card this month?", nil, .count, 4),
            ("What is the average original debit charge on Apple Card this month?", nil, .average, 176.25),
            ("What percentage of my spending this month is Dining?", nil, .share, nil)
        ]
        let (prompt, purpose, metric, amount) = cases[scenario]
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let answer = try await ask(prompt, runtime: runtime, fixture: fixture, history: &history)
        if let purpose { #expect(runtime.toolRequests.contains { $0.purpose == purpose }) }
        if let metric { #expect(runtime.toolRequests.contains { $0.metric == metric }) }
        if let amount {
            #expect(answer.presentations?.contains { $0.metrics.contains { abs($0.value - amount) < 0.001 } } == true)
            if metric != .count { expectMoney(amount, in: answer) }
        }
        if purpose == .categoryAvailability {
            let category = try #require(answer.presentations?.compactMap(\.report).flatMap { $0.categories ?? [] }.first)
            #expect(category.name == "Dining" && category.minimum == 100 && category.maximum == 500)
            #expect(category.planned == 80 && category.variable == 450)
        }
        if purpose == .incomeTimeline || purpose == .savingsTimeline {
            let report = try #require(answer.presentations?.compactMap(\.report).first { $0.series != nil })
            #expect(report.series?.count == 2)
            if purpose == .savingsTimeline {
                #expect(report.cumulative == true)
                #expect(report.series?.map(\.label) == ["Actual savings", "Projected savings"])
                #expect(answer.presentations?.contains { $0.metrics.contains { $0.label == "Actual savings" && $0.value == 330 } } == true)
            }
        }
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: 0..<3)
    func transactionDetailsAndNextPlannedExpensePreserveTheirMeaning(_ scenario: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let recorded = PlannedExpense(title: "Recorded appointment", plannedAmount: 60, actualAmount: 40,
            expenseDate: Fixture.date(month: 10, day: 18), workspace: fixture.workspace, card: fixture.card)
        fixture.context.insert(recorded)
        try fixture.context.save()
        let cases: [(String, MarinaDataRequest.TransactionFilter?)] = [
            ("Show the split purchases on Apple Card this month.", .split),
            ("Show refunds on Apple Card this month.", .credit),
            ("What is my next planned expense in this period?", nil)
        ]
        let (prompt, filter) = cases[scenario]
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let answer = try await ask(prompt, runtime: runtime, fixture: fixture, history: &history)
        if let filter {
            #expect(runtime.toolRequests.contains { $0.transactionFilter == filter })
            let transactions = answer.presentations?.compactMap(\.report).flatMap { $0.transactions ?? [] } ?? []
            if filter == .split {
                #expect(transactions.contains { $0.splitAmount == 50 && $0.grossAmount == 400 && $0.budgetImpact == 350 })
            } else {
                #expect(transactions.contains { $0.transactionKind == "credit" && $0.budgetImpact == -40 })
            }
        } else {
            #expect(runtime.toolRequests.contains { $0.purpose == .nextPlannedExpense })
            #expect(answer.presentations?.contains { $0.records.first?.id == recorded.id.uuidString } == true)
            expectWords(["Recorded appointment"], in: answer)
            expectMoney(40, in: answer)
        }
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."))
    func restoredFollowUpRetainsCardPeriodAndExtremeMeaning() async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let first = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        _ = try await ask("What was the highest positive expense on Apple Card this month?", runtime: first, fixture: fixture, history: &history)
        let memory = try #require(first.memory)
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        history = try JSONDecoder().decode([HomeAnswer].self, from: JSONEncoder().encode(history))
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        let answer = try await ask("And the lowest?", runtime: runtime, fixture: fixture, history: &history,
                                   restoredMemory: restored)
        expectCardScope(runtime, fixture: fixture)
        #expect(runtime.toolRequests.contains { $0.sort == .smallest && $0.limit == 1 && $0.positiveOnly == true })
        expectWords(["Corner shop"], in: answer)
        expectMoney(5, in: answer)
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."),
          arguments: ["leaders", "cheapest", "availability"])
    func heldOutParaphrasesPreserveFinancialIntent(_ scenario: String) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let prompt: String
        switch scenario {
        case "leaders": prompt = "Compare my highest category this month to June 2026."
        case "cheapest": prompt = "What’s my cheapest Apple Card purchase this month?"
        default: prompt = "How much room is left in each category this month?"
        }
        let answer = try await ask(prompt, runtime: runtime, fixture: fixture, history: &history)
        switch scenario {
        case "leaders":
            #expect(runtime.toolRequests.contains {
                $0.tool == .expenses && $0.operation == .comparison
                    && $0.grouping == .category && $0.compareLeaders == true
            })
            let leaders = try #require(answer.presentations?.compactMap(\.report).compactMap(\.leaders).last)
            #expect(leaders.count == 2)
            #expect(leaders.contains { $0.title == "Dining" && $0.amount == 530 })
            #expect(leaders.contains { $0.title == "Travel" && $0.amount == 800 })
            #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
            #expect(runtime.memory?.latestFinancialQuery?.comparisonPeriod?.startDate == "2026-06-01")
            expectWords(["Dining", "Travel"], in: answer)
            expectMoney(530, in: answer)
            expectMoney(800, in: answer)
        case "cheapest":
            expectCardScope(runtime, fixture: fixture)
            #expect(runtime.toolRequests.contains {
                $0.operation == .transactions && $0.sort == .smallest
                    && $0.positiveOnly == true && $0.limit == 1
            })
            #expect(answer.presentations?.contains { $0.records.first?.title == "Corner shop" && $0.records.first?.amount == 5 } == true)
            expectWords(["Corner shop"], in: answer)
            expectMoney(5, in: answer)
        default:
            #expect(runtime.toolRequests.contains { $0.purpose == .categoryAvailability })
            let categories = try #require(answer.presentations?.compactMap(\.report).compactMap(\.categories).last)
            #expect(categories.contains { $0.name == "Dining" && $0.available == -30 && $0.status == "over" })
            #expect(categories.contains { $0.name == "Groceries" && $0.available == 15 && $0.status == "near" })
            #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
            #expect(runtime.memory?.latestFinancialQuery?.period.endDate == "2026-10-31")
            expectWords(["Dining", "Groceries"], in: answer)
        }
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func offeredMerchantSurvivesNarrowingAndRestoration(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        for (name, amount) in [("DoorDash - BevMo!", 35.0), ("DoorDash - Market", 60.0),
                               ("DoorDash - BevMo! Delivery", 12.0)] {
            fixture.context.insert(VariableExpense(descriptionText: name, amount: amount,
                transactionDate: Fixture.date(month: 10, day: 9), workspace: fixture.workspace, card: fixture.card))
        }
        let secondCard = Card(name: "Travel Card", workspace: fixture.workspace)
        fixture.context.insert(secondCard)
        fixture.context.insert(VariableExpense(descriptionText: "DoorDash - BevMo!", amount: 99,
            transactionDate: Fixture.date(month: 10, day: 9), workspace: fixture.workspace, card: secondCard))
        try fixture.context.save()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let turns = MarinaCapabilityScenarios.merchantClarification.turns
        _ = try await ask(turns[0].prompt, runtime: runtime, fixture: fixture, history: &history)
        #expect(runtime.memory?.pendingClarification?.candidates.contains { $0.name == "DoorDash - BevMo!" } == true)
        _ = try await ask(turns[1].prompt, runtime: runtime, fixture: fixture, history: &history)
        let saved = try #require(runtime.memory)
        let restored = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(saved))
        history = try JSONDecoder().decode([HomeAnswer].self, from: JSONEncoder().encode(history))
        let resumed = MarinaConversationRuntime(now: { fixture.now })
        let answer = try await ask(turns[2].prompt, runtime: resumed, fixture: fixture, history: &history,
                                   restoredMemory: restored)
        #expect(resumed.toolRequests.contains { $0.tool == .expenses && $0.operation == .transactions })
        expectCardScope(resumed, fixture: fixture)
        let rows = answer.presentations?.filter { $0.operation == .transactions }.flatMap(\.records) ?? []
        #expect(rows.count == 1)
        #expect(rows.first?.title == "DoorDash - BevMo!" && rows.first?.amount == 35)
        expectMoney(35, in: answer)
        #expect(!(answer.explanation ?? "").localizedCaseInsensitiveContains("couldn’t find"))
        print("MarinaCapabilities scenario=merchant-clarification repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func expenseCardGroupingRemainsDistinctFromMerchantResolution(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let other = Card(name: "Travel Card", workspace: fixture.workspace)
        fixture.context.insert(other)
        fixture.context.insert(VariableExpense(descriptionText: "Train", amount: 42,
            transactionDate: Fixture.date(month: 10, day: 9), workspace: fixture.workspace, card: other))
        try fixture.context.save()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let answer = try await ask(MarinaCapabilityScenarios.cardGrouping.turns[0], runtime: runtime,
                                   fixture: fixture, history: &history)
        let read = try #require(runtime.toolRequests.last { $0.tool == .expenses })
        #expect(read.grouping == .card && read.cardID == nil)
        let labels = answer.presentations?.flatMap { $0.chartPoints.map(\.label) } ?? []
        #expect(labels.contains("Apple Card") && labels.contains("Travel Card"))
        print("MarinaCapabilities scenario=card-grouping repetition=\(repetition) complete")
    }

    @Test(.enabled(if: enabled, "Set MARINA_MODEL_EVALUATION=1 on an Apple Intelligence destination."), arguments: [1, 2, 3])
    func temporalProgressionSelectsLineWithoutChangingToCumulative(_ repetition: Int) async throws {
        try requireAvailableModel()
        let fixture = try Fixture()
        let runtime = MarinaConversationRuntime(now: { fixture.now })
        var history: [HomeAnswer] = []
        let answer = try await ask(MarinaCapabilityScenarios.movementOverTime.turns[0], runtime: runtime,
                                   fixture: fixture, history: &history)
        expectCardScope(runtime, fixture: fixture)
        let presentation = try #require(answer.presentations?.last)
        #expect(presentation.chartIntent == .movementOverTime)
        #expect(presentation.report?.cumulative != true)
        #expect(presentation.operation == .trend || presentation.purpose == .spendingPatterns)
        print("MarinaCapabilities scenario=movement-over-time repetition=\(repetition) complete")
    }

    private func ask(_ prompt: String, runtime: MarinaConversationRuntime, fixture: Fixture,
                     history: inout [HomeAnswer], restoredMemory: MarinaConversationMemory? = nil) async throws -> HomeAnswer {
        var latest: HomeAnswer?
        await runtime.respond(prompt: prompt, history: history, workspace: fixture.workspace,
            modelContext: fixture.context, homeContext: nil, defaultBudgetingPeriod: .monthly,
            answerID: UUID(), chatID: restoredMemory?.chatID, restoredMemory: restoredMemory) { latest = $0 }
        let answer = try #require(latest)
        if ProcessInfo.processInfo.environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" {
            print("MarinaCapabilitiesSynthetic prompt=\(prompt) state=\(answer.responseState?.rawValue ?? "none") error=\(runtime.lastErrorDescription ?? "none")")
            print("MarinaCapabilitiesSynthetic requests=\(runtime.toolRequests)")
            print("MarinaCapabilitiesSynthetic answer=\(answer.explanation ?? "")")
            print("MarinaCapabilitiesSynthetic failed_calls=\(runtime.diagnosticFailedToolCalls)")
        }
        try #require(runtime.lastErrorDescription == nil, "Native runtime failed: \(runtime.lastErrorDescription ?? "")")
        #expect(answer.explanation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        #expect(answer.responseState != .invalidRequest && answer.responseState != .generationFailed)
        #expect(!(answer.explanation ?? "").contains("{{"))
        #expect(!(answer.explanation ?? "").contains("——"))
        print("MarinaCapabilities turn=\(history.count + 1) request_count=\(runtime.toolRequests.count) completed=\(answer.responseState == .complete)")
        history.append(answer)
        return answer
    }

    private func ask(_ turn: MarinaCapabilityScenarios.Turn, runtime: MarinaConversationRuntime, fixture: Fixture,
                     history: inout [HomeAnswer], restoredMemory: MarinaConversationMemory? = nil) async throws -> HomeAnswer {
        let answer = try await ask(turn.prompt, runtime: runtime, fixture: fixture, history: &history,
            restoredMemory: restoredMemory)
        if turn.requiresFinancialRead {
            let matches = runtime.toolRequests.contains(where: turn.matches)
            if !matches, ProcessInfo.processInfo.environment["MARINA_LONG_EVALUATION_VERBOSE"] == "1" {
                print("MarinaCapabilitiesSynthetic route_mismatch=\(turn.id) requests=\(runtime.toolRequests)")
            }
            #expect(matches, "The native route must satisfy the shared scenario contract.")
        } else {
            #expect(runtime.toolRequests.isEmpty)
        }
        if turn.requiresClarification { #expect(answer.explanation?.contains("?") == true) }
        return answer
    }

    private func freshRuntime(after runtime: MarinaConversationRuntime, fixture: Fixture) throws
        -> (runtime: MarinaConversationRuntime, memory: MarinaConversationMemory) {
        let memory = try #require(runtime.memory)
        let saved = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(memory))
        return (MarinaConversationRuntime(now: { fixture.now }), saved)
    }

    private func expectCardScope(_ runtime: MarinaConversationRuntime, fixture: Fixture) {
        let reads = runtime.toolRequests.filter { $0.tool == .expenses }
        #expect(!reads.isEmpty)
        #expect(reads.allSatisfy { $0.cardID == fixture.card.id.uuidString })
        #expect(runtime.memory?.latestFinancialQuery?.period.startDate == "2026-10-01")
        #expect(runtime.memory?.latestFinancialQuery?.period.endDate == "2026-10-31")
    }

    private func expectWords(_ words: [String], in answer: HomeAnswer) {
        for word in words { #expect((answer.explanation ?? "").localizedCaseInsensitiveContains(word)) }
    }

    private func expectMoney(_ value: Double, in answer: HomeAnswer) {
        #expect((answer.explanation ?? "").contains(CurrencyFormatter.string(from: value)))
    }

    private func requireAvailableModel() throws {
        if let reason = MarinaConversationRuntime.availabilityMessage { throw EvaluationError.unavailable(reason) }
    }

    private enum EvaluationError: Error { case unavailable(String) }

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let workspace: Workspace
        let card: Card
        let now = Self.date(month: 10, day: 17)

        static func date(month: Int, day: Int) -> Date {
            Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }

        init() throws {
            let schema = Schema([Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
                BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self,
                VariableExpense.self, AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self,
                SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
                MarinaChatSession.self, IncomeSeries.self, Income.self])
            container = try ModelContainer(for: schema, configurations: ModelConfiguration(
                "MarinaCapabilityFixture-\(UUID())", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            context = ModelContext(container)
            workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
            card = Card(name: "Apple Card", workspace: workspace)
            let dining = Category(name: "Dining", hexColor: "#AA3366", workspace: workspace)
            let groceries = Category(name: "Groceries", hexColor: "#339966", workspace: workspace)
            let travel = Category(name: "Travel", hexColor: "#3366AA", workspace: workspace)
            let budget = Budget(name: "October", startDate: Self.date(month: 10, day: 1), endDate: Self.date(month: 10, day: 31), workspace: workspace)
            let june = Budget(name: "June", startDate: Self.date(month: 6, day: 1), endDate: Self.date(month: 6, day: 30), workspace: workspace)
            let preset = Preset(title: "Meal plan", plannedAmount: 80, workspace: workspace, defaultCard: card, defaultCategory: dining)
            context.insert(workspace); context.insert(card); context.insert(dining); context.insert(groceries); context.insert(travel)
            context.insert(budget); context.insert(june); context.insert(preset)
            context.insert(BudgetCardLink(budget: budget, card: card)); context.insert(BudgetCardLink(budget: june, card: card))
            context.insert(BudgetPresetLink(budget: budget, preset: preset))
            context.insert(BudgetCategoryLimit(minAmount: 100, maxAmount: 500, budget: budget, category: dining))
            context.insert(BudgetCategoryLimit(maxAmount: 180, budget: budget, category: groceries))
            let restaurant = VariableExpense(descriptionText: "Restaurant", amount: 400, transactionDate: Self.date(month: 10, day: 8), workspace: workspace, card: card, category: dining)
            context.insert(restaurant)
            let account = AllocationAccount(name: "Household", workspace: workspace)
            context.insert(account)
            context.insert(ExpenseAllocation(allocatedAmount: 50, preservesGrossAmount: true, workspace: workspace, account: account, expense: restaurant))
            for (title, amount, day, category) in [("Cafe", 100.0, 12, dining), ("Grocery market", 200.0, 14, groceries), ("Corner shop", 5.0, 16, groceries)] {
                context.insert(VariableExpense(descriptionText: title, amount: amount, transactionDate: Self.date(month: 10, day: day), workspace: workspace, card: card, category: category))
            }
            context.insert(VariableExpense(descriptionText: "Refund", amount: 40, kindRaw: VariableExpenseKind.credit.rawValue,
                transactionDate: Self.date(month: 10, day: 16), workspace: workspace, card: card, category: groceries))
            context.insert(PlannedExpense(title: "Meal plan", plannedAmount: 80, expenseDate: Self.date(month: 10, day: 20), workspace: workspace, card: card, category: dining, sourcePresetID: preset.id, sourceBudgetID: budget.id))
            context.insert(VariableExpense(descriptionText: "Hotel", amount: 800, transactionDate: Self.date(month: 6, day: 10), workspace: workspace, card: card, category: travel))
            context.insert(VariableExpense(descriptionText: "June cafe", amount: 100, transactionDate: Self.date(month: 6, day: 11), workspace: workspace, card: card, category: dining))
            context.insert(Income(source: "Salary", amount: 1200, date: Self.date(month: 10, day: 1), isPlanned: true, workspace: workspace))
            context.insert(Income(source: "Salary", amount: 1000, date: Self.date(month: 10, day: 15), isPlanned: false, workspace: workspace))
            context.insert(SavingsLedgerEntry(date: Self.date(month: 10, day: 16), amount: 25, note: "Manual savings",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: workspace))
            try context.save()
        }
    }
}
#endif
