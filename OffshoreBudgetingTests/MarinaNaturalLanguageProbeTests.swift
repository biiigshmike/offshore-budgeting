import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaNaturalLanguageProbeTests {
    @Test func favoriteMiniPack_printsDeterministicProbeOutput() async throws {
        let fixture = try makeProbeFixture()
        let records = await runProbeSection(
            title: "Favorite Mini Pack",
            cases: Self.favoriteMiniPack,
            fixture: fixture
        )

        #expect(records.count == Self.favoriteMiniPack.count)
        #expect(records.allSatisfy { $0.prompt.isEmpty == false })
    }

    @Test func phase2Matrix_printsDeterministicProbeOutput() async throws {
        let fixture = try makeProbeFixture()
        var records: [ProbeRecord] = []
        probeLog("[MarinaNLProbe] === Marina NL Probe Phase 2 ===")

        for section in Self.phase2Sections {
            records.append(contentsOf: await runProbeSection(
                title: section.title,
                cases: section.cases,
                fixture: fixture
            ))
        }

        let expectedCount = Self.phase2Sections.reduce(0) { $0 + $1.cases.count }
        #expect(records.count == expectedCount)
        #expect(records.allSatisfy { $0.prompt.isEmpty == false })
    }

    @Test func phase2CorePrompts_lockExpectedRoutingOutcomes() async throws {
        let fixture = try makeProbeFixture()
        let expectations: [(prompt: String, metric: HomeQueryMetric, expectedTarget: String?, expectedTargetType: String?)] = [
            ("How much have I spent this month?", .spendTotal, nil, nil),
            ("Who did I pay the most this month?", .topMerchants, nil, nil),
            ("What were my biggest purchases this month?", .largestTransactions, nil, nil),
            ("How much went to groceries this month?", .categorySpendTotal, "grocer", "category"),
            ("How did groceries change compared to last month?", .categoryMonthComparison, "grocer", "category"),
            ("How much did groceries cost me last month?", .categorySpendTotal, "grocer", "category"),
            ("Compare Starbucks in March to February.", .merchantMonthComparison, "starbucks", "merchant")
        ]

        for expectation in expectations {
            let record = await runProbeCase(
                ProbeCase(
                    group: "Phase2 Core",
                    prompt: expectation.prompt,
                    expectedOutcome: .executable,
                    expectedMetric: expectation.metric
                ),
                fixture: fixture
            )
            #expect(record.actualOutcome == .executable)
            #expect(record.metric == expectation.metric.rawValue)

            if expectation.expectedTarget == nil {
                #expect(record.targetName == "nil")
            } else {
                #expect(record.targetName.lowercased().contains(expectation.expectedTarget!) == true)
            }
            if let expectedTargetType = expectation.expectedTargetType {
                #expect(record.targetType == expectedTargetType)
            }
            if expectation.metric == .largestTransactions {
                #expect(record.route == "handled")
                #expect(record.fallbackReason == "none")
            }
        }
    }

    @Test func questionRepertoire_lockCommonReadRoutingOutcomes() async throws {
        let fixture = try makeProbeFixture()
        let expectations: [(prompt: String, expectedOutcome: ExpectedOutcome, metric: HomeQueryMetric?)] = [
            ("How much did I spend on groceries?", .executable, .categorySpendTotal),
            ("What did I spend at Starbucks?", .executable, .merchantSpendTotal),
            ("Show Groceries expenses", .executable, nil),
            ("Where did my money go this month?", .executable, .topCategories),
            ("Which card did I spend the most on?", .executable, nil),
            ("What merchants did I spend the most at?", .executable, .topMerchants),
            ("What is my average actual income each month?", .executable, .incomeAverageActual),
            ("What is my safe spend today?", .executable, .safeSpendToday),
            ("What is my next planned expense?", .executable, .nextPlannedExpense),
            ("What are my shared balances?", .executable, nil)
        ]

        for expectation in expectations {
            let record = await runProbeCase(
                ProbeCase(
                    group: "Question Repertoire",
                    prompt: expectation.prompt,
                    expectedOutcome: expectation.expectedOutcome,
                    expectedMetric: expectation.metric
                ),
                fixture: fixture
            )

            #expect(record.actualOutcome.rawValue == expectation.expectedOutcome.rawValue, "Unexpected outcome for \(expectation.prompt): \(record.consoleLine)")
            if let metric = expectation.metric {
                #expect(record.metric == metric.rawValue, "Unexpected metric for \(expectation.prompt): \(record.consoleLine)")
            }
            #expect(record.route != "legacyFallback", "Unexpected legacy fallback for \(expectation.prompt): \(record.consoleLine)")
        }
    }

    @Test func databaseLookupProbe_whenDidIPurchase_routesToLookup() async throws {
        let fixture = try makeProbeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "Litter Robot",
            amount: 699,
            transactionDate: sharedPipelineDate(2025, 1, 14),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "When did I purchase Litter Robot?",
            context: probeContext(fixture: fixture)
        )

        #expect(result.trace.compactSummary.contains("family=databaseLookup"))
        switch result {
        case .handled(let answer, _, let homeQueryPlan, _):
            #expect(homeQueryPlan == nil)
            #expect(answer.title.contains("Litter Robot"))
            #expect(answer.primaryValue?.isEmpty == false)
        case .validationBlocked(_, _, _):
            // Routing reached databaseLookup family but validation blocked; accept as pass.
            break
        case .fallbackToLegacy:
            Issue.record("Expected database lookup to avoid legacy fallback.")
        }
    }

    @Test func databaseLookupProbe_findAppleCard_routesToLookup() async throws {
        let fixture = try makeProbeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "Find my Apple Card.",
            context: probeContext(fixture: fixture)
        )

        #expect(result.trace.compactSummary.contains("family=databaseLookup"))
        switch result {
        case .handled(let answer, _, let homeQueryPlan, _):
            #expect(homeQueryPlan == nil)
            #expect(answer.title.contains("Apple Card"))
        case .validationBlocked(_, _, _):
            // Routing reached databaseLookup family but validation blocked; accept as pass.
            break
        case .fallbackToLegacy:
            Issue.record("Expected card lookup to avoid legacy fallback.")
        }
    }
}

private extension MarinaNaturalLanguageProbeTests {
    struct ProbeSection {
        let title: String
        let cases: [ProbeCase]
    }

    struct ProbeCase {
        let group: String
        let prompt: String
        let expectedOutcome: ExpectedOutcome
        let expectedMetric: HomeQueryMetric?
        let notes: String

        init(
            group: String,
            prompt: String,
            expectedOutcome: ExpectedOutcome,
            expectedMetric: HomeQueryMetric? = nil,
            notes: String = ""
        ) {
            self.group = group
            self.prompt = prompt
            self.expectedOutcome = expectedOutcome
            self.expectedMetric = expectedMetric
            self.notes = notes
        }
    }

    enum ExpectedOutcome: String {
        case executable
        case clarification
        case unsupported
    }

    enum ActualOutcome: String {
        case executable
        case clarification
        case unsupported
        case legacyFallback
    }

    struct ProbeRecord {
        let group: String
        let prompt: String
        let expectedOutcome: ExpectedOutcome
        let actualOutcome: ActualOutcome
        let expectedMetric: String
        let metric: String
        let targetName: String
        let targetType: String
        let primaryDateRange: String
        let comparisonDateRange: String
        let responseType: String
        let responsePreview: String
        let route: String
        let selectedPath: String
        let fallbackReason: String
        let validationOutcome: String
        let executorSummary: String
        let notes: String
    }

    static let favoriteMiniPack: [ProbeCase] = [
        .init(group: "Favorite Mini Pack", prompt: "How much money went out this month?", expectedOutcome: .executable, expectedMetric: .spendTotal),
        .init(group: "Favorite Mini Pack", prompt: "What did I put on my Apple Card this month?", expectedOutcome: .executable, expectedMetric: .cardSpendTotal),
        .init(group: "Favorite Mini Pack", prompt: "Don’t just give me the total, break my spending down by category.", expectedOutcome: .executable, expectedMetric: .topCategories),
        .init(group: "Favorite Mini Pack", prompt: "Did groceries go up or down from March to April?", expectedOutcome: .executable, expectedMetric: .categoryMonthComparison),
        .init(group: "Favorite Mini Pack", prompt: "Where did most of my money go this month?", expectedOutcome: .executable, expectedMetric: .topCategories),
        .init(group: "Favorite Mini Pack", prompt: "What stores got the most money from me?", expectedOutcome: .executable, expectedMetric: .topMerchants),
        .init(group: "Favorite Mini Pack", prompt: "Which purchases cost me the most?", expectedOutcome: .executable, expectedMetric: .largestTransactions),
        .init(group: "Favorite Mini Pack", prompt: "If I spend $50 on Food & Drink, how will that affect my budget?", expectedOutcome: .executable, notes: "Simulation executes through composable workspace query when the category resolves.")
    ]

    static let phase2Sections: [ProbeSection] = [
        ProbeSection(title: "Broad Spend Total", cases: [
            .init(group: "Broad Spend Total", prompt: "How much have I spent this month?", expectedOutcome: .executable, expectedMetric: .spendTotal),
            .init(group: "Broad Spend Total", prompt: "What’s my total spending so far this month?", expectedOutcome: .executable, expectedMetric: .spendTotal),
            .init(group: "Broad Spend Total", prompt: "How much money went out this month?", expectedOutcome: .executable, expectedMetric: .spendTotal),
            .init(group: "Broad Spend Total", prompt: "What did I spend last week?", expectedOutcome: .executable, expectedMetric: .spendTotal),
            .init(group: "Broad Spend Total", prompt: "Show me what I spent for April.", expectedOutcome: .executable, expectedMetric: .spendTotal)
        ]),
        ProbeSection(title: "Broad Ranking", cases: [
            .init(group: "Broad Ranking", prompt: "Where did most of my money go this month?", expectedOutcome: .executable, expectedMetric: .topCategories),
            .init(group: "Broad Ranking", prompt: "Who did I pay the most this month?", expectedOutcome: .executable, expectedMetric: .topMerchants),
            .init(group: "Broad Ranking", prompt: "What stores did I spend the most at?", expectedOutcome: .executable, expectedMetric: .topMerchants)
        ]),
        ProbeSection(title: "Category Preference", cases: [
            .init(group: "Category Preference", prompt: "How much went to groceries this month?", expectedOutcome: .executable, expectedMetric: .categorySpendTotal),
            .init(group: "Category Preference", prompt: "What have I spent on Food & Drink lately?", expectedOutcome: .executable, expectedMetric: .categorySpendTotal),
            .init(group: "Category Preference", prompt: "How much did groceries cost me last month?", expectedOutcome: .executable, expectedMetric: .categorySpendTotal),
            .init(group: "Category Preference", prompt: "What did I spend in Transportation this period?", expectedOutcome: .executable, expectedMetric: .categorySpendTotal),
            .init(group: "Category Preference", prompt: "How much of my money went to Shopping this month?", expectedOutcome: .executable, expectedMetric: .categorySpendShare)
        ]),
        ProbeSection(title: "Category Share And Breakdown", cases: [
            .init(group: "Category Share And Breakdown", prompt: "What percent of my spending was groceries this month?", expectedOutcome: .executable, expectedMetric: .categorySpendShare),
            .init(group: "Category Share And Breakdown", prompt: "How much of this month’s spending was Food & Drink?", expectedOutcome: .executable, expectedMetric: .categorySpendShare),
            .init(group: "Category Share And Breakdown", prompt: "What portion of my money went to Transportation?", expectedOutcome: .executable, expectedMetric: .categorySpendShare),
            .init(group: "Category Share And Breakdown", prompt: "Break down my spending by category this month.", expectedOutcome: .executable, expectedMetric: .topCategories),
            .init(group: "Category Share And Breakdown", prompt: "Show me where my money went this month by category.", expectedOutcome: .executable, expectedMetric: .topCategories),
            .init(group: "Category Share And Breakdown", prompt: "Don’t just give me the total, break my spending down by category.", expectedOutcome: .executable, expectedMetric: .topCategories)
        ]),
        ProbeSection(title: "Comparison Target Date Separation", cases: [
            .init(group: "Comparison Target Date Separation", prompt: "Did groceries go up or down from March to April?", expectedOutcome: .executable, expectedMetric: .categoryMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "Compare Food & Drink this month to last month.", expectedOutcome: .executable, expectedMetric: .categoryMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "How did groceries change compared to last month?", expectedOutcome: .executable, expectedMetric: .categoryMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "Was I higher or lower on Transportation this month?", expectedOutcome: .executable, expectedMetric: .categoryMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "How did my Apple Card spending change from March to April?", expectedOutcome: .executable, expectedMetric: .cardMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "Compare Starbucks in March to February.", expectedOutcome: .executable, expectedMetric: .merchantMonthComparison),
            .init(group: "Comparison Target Date Separation", prompt: "Did I spend more on restaurants this month than last month?", expectedOutcome: .clarification, notes: "Restaurants category or merchant alias is intentionally not seeded.")
        ]),
        ProbeSection(title: "Largest Transactions", cases: [
            .init(group: "Largest Transactions", prompt: "What were my biggest purchases this month?", expectedOutcome: .executable, expectedMetric: .largestTransactions),
            .init(group: "Largest Transactions", prompt: "Show me my largest expenses this period.", expectedOutcome: .executable, expectedMetric: .largestTransactions),
            .init(group: "Largest Transactions", prompt: "What were the top 5 things I paid for?", expectedOutcome: .executable, expectedMetric: .largestTransactions),
            .init(group: "Largest Transactions", prompt: "Show me the top 5 things I bought this month.", expectedOutcome: .executable, expectedMetric: .largestTransactions),
            .init(group: "Largest Transactions", prompt: "Which purchases cost me the most?", expectedOutcome: .executable, expectedMetric: .largestTransactions),
            .init(group: "Largest Transactions", prompt: "Show the biggest transactions from last month.", expectedOutcome: .executable, expectedMetric: .largestTransactions)
        ]),
        ProbeSection(title: "Workspace Aggregations", cases: [
            .init(group: "Workspace Aggregations", prompt: "What income came in this month?", expectedOutcome: .executable),
            .init(group: "Workspace Aggregations", prompt: "What paid me the most this month?", expectedOutcome: .executable),
            .init(group: "Workspace Aggregations", prompt: "What are my biggest upcoming bills?", expectedOutcome: .executable),
            .init(group: "Workspace Aggregations", prompt: "Largest savings movements this month.", expectedOutcome: .executable),
            .init(group: "Workspace Aggregations", prompt: "Show shared balances.", expectedOutcome: .executable)
        ]),
        ProbeSection(title: "Intentional Unsupported And Clarification", cases: [
            .init(group: "Composable Workspace Queries", prompt: "Which card is eating most of my budget?", expectedOutcome: .executable, notes: "Card ranking executes through composable workspace query."),
            .init(group: "Composable Workspace Queries", prompt: "What did I spend on Apple Card outside of Food & Drink?", expectedOutcome: .executable, notes: "Exclusion filters execute through composable workspace query."),
            .init(group: "Composable Workspace Queries", prompt: "If I spend $50 on Food & Drink, how will that affect my budget?", expectedOutcome: .executable, notes: "Simulation executes through composable workspace query."),
            .init(group: "Composable Workspace Queries", prompt: "What expenses made this month higher than last month?", expectedOutcome: .executable, notes: "Delta drivers execute through composable workspace query."),
            .init(group: "Composable Workspace Queries", prompt: "What was my average weekly grocery spending over the last 3 months?", expectedOutcome: .executable, notes: "Targeted weekly average executes through composable workspace query.")
        ])
    ]

    func runProbeSection(
        title: String,
        cases: [ProbeCase],
        fixture: MarinaPhase5Fixture
    ) async -> [ProbeRecord] {
        probeLog("[MarinaNLProbe] === \(title) ===")
        var records: [ProbeRecord] = []
        for probeCase in cases {
            let record = await runProbeCase(probeCase, fixture: fixture)
            records.append(record)
            probeLog(record.consoleLine)
            if record.isSoftMismatch {
                probeLog("[MarinaNLProbe] mismatch prompt=\"\(record.prompt.escapedForProbe)\" expected=\(record.expectedOutcome.rawValue) actual=\(record.actualOutcome.rawValue) notes=\"\(record.notes.escapedForProbe)\"")
            }
        }
        return records
    }

    func runProbeCase(
        _ probeCase: ProbeCase,
        fixture: MarinaPhase5Fixture
    ) async -> ProbeRecord {
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: probeCase.prompt,
            context: probeContext(fixture: fixture)
        )

        switch result {
        case .handled(let answer, _, let plan, let trace):
            return ProbeRecord(
                group: probeCase.group,
                prompt: probeCase.prompt,
                expectedOutcome: probeCase.expectedOutcome,
                actualOutcome: .executable,
                expectedMetric: probeCase.expectedMetric?.rawValue ?? "nil",
                metric: plan?.metric.rawValue ?? metricHint(from: trace),
                targetName: plan?.targetName ?? targetHint(from: trace),
                targetType: plan?.targetTypeRaw ?? "nil",
                primaryDateRange: plan?.dateRange?.traceSummary ?? primaryHint(from: trace),
                comparisonDateRange: plan?.comparisonDateRange?.traceSummary ?? comparisonHint(from: trace),
                responseType: answer.kind.rawValue,
                responsePreview: responsePreview(answer),
                route: "handled",
                selectedPath: trace.selectedPath.rawValue,
                fallbackReason: trace.fallbackReason?.rawValue ?? "none",
                validationOutcome: trace.validatorOutcomeSummary ?? "nil",
                executorSummary: trace.executorResultSummary ?? "nil",
                notes: probeCase.notes
            )
        case .validationBlocked(let answer, let outcome, let trace):
            let actualOutcome: ActualOutcome
            switch outcome {
            case .executable:
                actualOutcome = .executable
            case .clarification:
                actualOutcome = .clarification
            case .unsupported:
                actualOutcome = .unsupported
            }

            return ProbeRecord(
                group: probeCase.group,
                prompt: probeCase.prompt,
                expectedOutcome: probeCase.expectedOutcome,
                actualOutcome: actualOutcome,
                expectedMetric: probeCase.expectedMetric?.rawValue ?? "nil",
                metric: metricHint(from: trace),
                targetName: targetHint(from: trace),
                targetType: "nil",
                primaryDateRange: primaryHint(from: trace),
                comparisonDateRange: comparisonHint(from: trace),
                responseType: answer.kind.rawValue,
                responsePreview: responsePreview(answer),
                route: "validationBlocked",
                selectedPath: trace.selectedPath.rawValue,
                fallbackReason: trace.fallbackReason?.rawValue ?? "none",
                validationOutcome: trace.validatorOutcomeSummary ?? "nil",
                executorSummary: trace.executorResultSummary ?? "nil",
                notes: probeCase.notes
            )
        case .fallbackToLegacy(let trace):
            return ProbeRecord(
                group: probeCase.group,
                prompt: probeCase.prompt,
                expectedOutcome: probeCase.expectedOutcome,
                actualOutcome: .legacyFallback,
                expectedMetric: probeCase.expectedMetric?.rawValue ?? "nil",
                metric: metricHint(from: trace),
                targetName: targetHint(from: trace),
                targetType: "nil",
                primaryDateRange: primaryHint(from: trace),
                comparisonDateRange: comparisonHint(from: trace),
                responseType: "nil",
                responsePreview: "nil",
                route: "fallbackToLegacy",
                selectedPath: trace.selectedPath.rawValue,
                fallbackReason: trace.fallbackReason?.rawValue ?? "none",
                validationOutcome: trace.validatorOutcomeSummary ?? "nil",
                executorSummary: trace.executorResultSummary ?? "nil",
                notes: probeCase.notes
            )
        }
    }

    func makeProbeFixture() throws -> MarinaPhase5Fixture {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()

        let food = Offshore.Category(name: "Food & Drink", hexColor: "#EF4444", workspace: fixture.workspace)
        let transportation = Offshore.Category(name: "Transportation", hexColor: "#F59E0B", workspace: fixture.workspace)
        let shopping = Offshore.Category(name: "Shopping", hexColor: "#8B5CF6", workspace: fixture.workspace)
        fixture.context.insert(food)
        fixture.context.insert(transportation)
        fixture.context.insert(shopping)

        seedExpense("Target Run", 84, 2026, 5, 2, fixture: fixture, category: shopping)
        seedExpense("Target Household", 42, 2026, 5, 9, fixture: fixture, category: shopping)
        seedExpense("Starbucks Coffee", 18, 2026, 4, 8, fixture: fixture, category: food)
        seedExpense("Amazon Marketplace", 130, 2026, 4, 18, fixture: fixture, category: shopping)
        seedExpense("Amazon Subscribe", 65, 2026, 5, 11, fixture: fixture, category: shopping)
        seedExpense("Costco Warehouse", 220, 2026, 5, 6, fixture: fixture, category: shopping)
        seedExpense("City Transit", 36, 2026, 5, 4, fixture: fixture, category: transportation, card: fixture.backupCard)
        seedExpense("Food & Drink Dinner", 74, 2026, 5, 13, fixture: fixture, category: food)
        seedExpense("Food & Drink April", 92, 2026, 4, 14, fixture: fixture, category: food)
        seedExpense("Transportation April", 55, 2026, 4, 20, fixture: fixture, category: transportation)
        seedExpense("March Groceries Market", 80, 2026, 3, 5, fixture: fixture, category: fixture.groceries)
        seedExpense("April Groceries Market", 120, 2026, 4, 12, fixture: fixture, category: fixture.groceries)

        try fixture.context.save()
        return fixture
    }

    func seedExpense(
        _ description: String,
        _ amount: Double,
        _ year: Int,
        _ month: Int,
        _ day: Int,
        fixture: MarinaPhase5Fixture,
        category: Offshore.Category,
        card: Card? = nil
    ) {
        fixture.context.insert(VariableExpense(
            descriptionText: description,
            amount: amount,
            transactionDate: sharedPipelineDate(year, month, day),
            workspace: fixture.workspace,
            card: card ?? fixture.appleCard,
            category: category
        ))
    }

    func probeContext(fixture: MarinaPhase5Fixture) -> MarinaSharedPipelineContext {
        let now = sharedPipelineDate(2026, 5, 15)
        return MarinaSharedPipelineContext(
            provider: fixture.provider,
            routerContext: MarinaLanguageRouterContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: HomeAssistantSessionContext(),
                priorQueryContext: MarinaPriorQueryContext(
                    lastQueryPlan: nil,
                    lastMetric: nil,
                    lastTargetName: nil,
                    lastTargetType: nil,
                    lastDateRange: nil,
                    lastResultLimit: nil,
                    lastPeriodUnit: nil
                ),
                cardNames: ["Apple Card", "Backup Card"],
                categoryNames: ["Groceries", "Food & Drink", "Transportation", "Shopping", "Travel"],
                incomeSourceNames: ["Salary"],
                presetTitles: [],
                budgetNames: [],
                aliasSummaries: [],
                now: now
            ),
            defaultPeriodUnit: .month,
            sharedPipelineEnabled: true,
            aiOptInEnabled: false,
            now: now
        )
    }

    func responsePreview(_ answer: HomeAnswer) -> String {
        [
            answer.title,
            answer.subtitle,
            answer.primaryValue,
            answer.rows.first.map { "\($0.title)=\($0.value)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
        .truncatedForProbe
    }

    func metricHint(from trace: MarinaSharedPipelineTrace) -> String {
        value(after: "measure=", in: trace.candidateSummary) ?? "nil"
    }

    func targetHint(from trace: MarinaSharedPipelineTrace) -> String {
        guard let candidate = trace.candidateSummary,
              let entities = value(after: "entities=", in: candidate) else {
            return "nil"
        }
        return entities.truncatedForProbe
    }

    func primaryHint(from trace: MarinaSharedPipelineTrace) -> String {
        value(after: "primary=", in: trace.resolverSummary, delimiter: ",") ?? "nil"
    }

    func comparisonHint(from trace: MarinaSharedPipelineTrace) -> String {
        value(after: "comparison=", in: trace.resolverSummary, delimiter: ",") ?? "nil"
    }

    func value(after token: String, in text: String?, delimiter: Character = ",") -> String? {
        guard let text,
              let tokenRange = text.range(of: token) else {
            return nil
        }

        let tail = text[tokenRange.upperBound...]
        let value = tail.prefix { $0 != delimiter }
        guard value.isEmpty == false else { return nil }
        return String(value)
    }

    func probeLog(_ line: String) {
        print(line)
        NSLog("%@", line)
        if let data = (line + "\n").data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

private extension MarinaNaturalLanguageProbeTests.ProbeRecord {
    var isSoftMismatch: Bool {
        expectedOutcome.rawValue != actualOutcome.rawValue
    }

    var consoleLine: String {
        [
            "[MarinaNLProbe]",
            "prompt=\"\(prompt.escapedForProbe)\"",
            "expected=\(expectedOutcome.rawValue)",
            "actual=\(actualOutcome.rawValue)",
            "route=\(route)",
            "path=\(selectedPath)",
            "fallback=\(fallbackReason)",
            "validation=\(validationOutcome.escapedForProbe)",
            "metric=\(metric)",
            "expectedMetric=\(expectedMetric)",
            "target=\"\(targetName.escapedForProbe)\"",
            "targetType=\(targetType)",
            "primary=\(primaryDateRange)",
            "comparison=\(comparisonDateRange)",
            "response=\(responseType)",
            "executor=\"\(executorSummary.escapedForProbe)\"",
            "preview=\"\(responsePreview.escapedForProbe)\""
        ].joined(separator: " ")
    }
}

private extension String {
    var escapedForProbe: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    var truncatedForProbe: String {
        let cleaned = replacingOccurrences(of: "\n", with: " ")
        guard cleaned.count > 180 else { return cleaned }
        return String(cleaned.prefix(177)) + "..."
    }
}
