import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaNarrationAnswerFocusTests {
    @Test func explicitTotalKeepsTheLeadingGroupAsTheAnswer() throws {
        for operation in [MarinaDataRequest.Operation.ranking, .share] {
            for grouping in [MarinaDataRequest.Grouping.category, .card, .merchant] {
                let request = MarinaDataRequest(metric: .total, operation: operation, tool: .expenses,
                                               grouping: grouping, sort: .largest)
                let result = MarinaDataResult(report: .init(groups: [
                    .init(id: "leader", title: "Leader", amount: 400, sharePercent: 50.96)
                ]), scope: "Apple Card · October 2026", metrics: [.init(label: "Total", value: 785)],
                    records: [.init(id: "leader", kind: "group", title: "Leader", amount: 400)], totalCount: 5)
                let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
                let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
                let focus = try #require(facts.first)
                #expect(focus.subject == "Leader" && focus.isFocus)
                #expect(focus.relation.contains("highest \(grouping.rawValue) total"))
                #expect(focus.value == CurrencyFormatter.string(from: 400))
                #expect(fallback.contains("Leader") && fallback.contains(CurrencyFormatter.string(from: 400)))
                #expect(!fallback.contains(CurrencyFormatter.string(from: 785)))
                #expect(!facts.contains { $0.value == CurrencyFormatter.string(from: 785) })
                #expect(facts.contains { $0.subject == "Its share of the total" })
            }
        }
    }

    @Test func explicitTotalKeepsHighestAndLowestExpensesAsTheAnswer() throws {
        for sort in [MarinaDataRequest.Sort.largest, .smallest] {
            let request = MarinaDataRequest(metric: .total, operation: .transactions, tool: .expenses,
                                           sort: sort, limit: 1)
            let result = MarinaDataResult(scope: "Apple Card · October 2026", metrics: [
                .init(label: "Total", value: 785), .init(label: "Tied expenses", value: 2, unit: .number)
            ], records: [.init(id: "purchase", kind: "variableExpense", title: "Selected purchase", amount: 40)],
                totalCount: 8, nextOffset: 1)
            let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
            let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
            let focus = try #require(facts.first)
            let direction = sort == .largest ? "highest" : "lowest"
            #expect(focus.subject == "Selected purchase" && focus.isFocus)
            #expect(focus.relation.contains("tied for your \(direction) expense"))
            #expect(focus.value == CurrencyFormatter.string(from: 40))
            #expect(fallback.contains("tied for your \(direction) expense"))
            #expect(fallback.contains(CurrencyFormatter.string(from: 40)))
            #expect(!fallback.contains(CurrencyFormatter.string(from: 785)))
        }
    }

    @Test func explicitTotalPreservesBothComparisonSidesAndCalculatedDirection() throws {
        for difference in [-70.0, 0, 70] {
            // Both request-driven and saved-presentation comparisons retain their focus.
            for operation in [MarinaDataRequest.Operation.comparison, .summary] {
                let request = MarinaDataRequest(metric: .total, operation: operation, tool: .expenses)
                let first = 100 + difference
                let result = MarinaDataResult(presentation: .init(id: "comparison", operation: .comparison,
                    title: "Spending comparison", scopeLabel: "Apple Card · October 2026", chartPoints: [
                        .init(id: "first", label: "Apple Card · October 2026", value: first),
                        .init(id: "second", label: "Apple Card · June 2026", value: 100)
                    ]), scope: "October 2026", metrics: [
                        .init(label: "Total", value: first), .init(label: "Comparison total", value: 100),
                        .init(label: "Difference", value: difference)
                    ])
                let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
                let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
                #expect(facts.count == 3 && facts.allSatisfy(\.isFocus))
                #expect(facts[0].value == CurrencyFormatter.string(from: first))
                #expect(facts[0].scope == "Apple Card · October 2026")
                #expect(facts[1].value == CurrencyFormatter.string(from: 100))
                #expect(facts[1].scope == "Apple Card · June 2026")
                #expect(fallback.contains("Apple Card · October 2026") && fallback.contains("Apple Card · June 2026"))
                #expect(fallback.contains(CurrencyFormatter.string(from: first)) && fallback.contains(CurrencyFormatter.string(from: 100)))
                #expect(fallback.contains(difference < 0 ? "lower" : difference > 0 ? "higher" : "amounts are the same"))
                #expect(facts[2].relation == (difference < 0 ? "is a decrease of" : difference > 0 ? "is an increase of" : "is"))
            }
        }
    }

    @Test func explicitTotalPreservesEachPeriodsDistinctLeader() throws {
        let request = MarinaDataRequest(metric: .total, operation: .comparison, tool: .expenses, grouping: .merchant)
        let result = MarinaDataResult(report: .init(leaders: [
            .init(scope: "Apple Card · October 2026", title: "Market", amount: 400),
            .init(scope: "Apple Card · June 2026", title: "Cafe", amount: 250)
        ]), scope: "October 2026", metrics: [
            .init(label: "Total", value: 785), .init(label: "Comparison total", value: 650),
            .init(label: "Difference", value: 150)
        ])
        let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
        #expect(facts.count == 3 && facts.allSatisfy(\.isFocus))
        #expect(facts[0].subject == "Market" && facts[0].value == CurrencyFormatter.string(from: 400))
        #expect(facts[1].subject == "Cafe" && facts[1].value == CurrencyFormatter.string(from: 250))
        #expect(facts[0].scope == "Apple Card · October 2026" && facts[1].scope == "Apple Card · June 2026")
        #expect(fallback.contains("Market") && fallback.contains("Cafe"))
        #expect(fallback.contains(CurrencyFormatter.string(from: 400)) && fallback.contains(CurrencyFormatter.string(from: 250)))
        #expect(fallback.contains("\(CurrencyFormatter.string(from: 150)) higher"))
        #expect(!fallback.contains(CurrencyFormatter.string(from: 785)) && !fallback.contains(CurrencyFormatter.string(from: 650)))
    }

    @Test func explicitCountAndAverageStillUseWholeDatasetMetrics() throws {
        for operation in [MarinaDataRequest.Operation.summary, .ranking, .transactions] {
            for metric in [MarinaDataRequest.MetricFocus.count, .average] {
                let request = MarinaDataRequest(metric: metric, operation: operation, tool: .expenses,
                                               grouping: .merchant, sort: .largest, limit: 1)
                let result = MarinaDataResult(scope: "Apple Card · October 2026", metrics: [
                    .init(label: "Total", value: 785), .init(label: "Count", value: 10, unit: .number),
                    .init(label: "Average per record", value: 78.5)
                ], records: [.init(id: "leader", kind: "group", title: "Market", amount: 400)], totalCount: 10)
                let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
                let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
                let focus = try #require(facts.first)
                #expect(facts.count == 1 && focus.isFocus)
                #expect(focus.value == (metric == .count ? "10" : CurrencyFormatter.string(from: 78.5)))
                #expect(fallback.contains(metric == .count ? "10 matching records" : CurrencyFormatter.string(from: 78.5)))
                #expect(!fallback.contains("Market") && !fallback.contains(CurrencyFormatter.string(from: 400)))
            }
        }
    }

    @Test func ordinarySummaryAndTransactionPageKeepTheGlobalTotal() throws {
        for operation in [MarinaDataRequest.Operation.summary, .transactions] {
            let request = MarinaDataRequest(metric: .total, operation: operation, tool: .expenses,
                                           sort: .largest, limit: 20)
            let result = MarinaDataResult(scope: "Apple Card · October 2026", metrics: [.init(label: "Total", value: 785)],
                records: [.init(id: "purchase", kind: "variableExpense", title: "Purchase", amount: 400)], totalCount: 10)
            let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
            let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
            #expect(facts.first?.value == CurrencyFormatter.string(from: 785))
            #expect(fallback.contains(CurrencyFormatter.string(from: 785)))
            #expect(!fallback.contains(CurrencyFormatter.string(from: 400)))
        }
    }

    @Test func explicitTotalOnALaterPageDoesNotRelabelItsRowAsTheLeader() throws {
        for operation in [MarinaDataRequest.Operation.ranking, .share, .transactions] {
            let request = MarinaDataRequest(metric: .total, operation: operation, tool: .expenses,
                                           grouping: .merchant, sort: .largest, offset: 5, limit: 1)
            let result = MarinaDataResult(scope: "Apple Card · October 2026", metrics: [.init(label: "Total", value: 785)],
                records: [.init(id: "later", kind: "group", title: "Cafe", amount: 20)], totalCount: 10)
            let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
            let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
            let text = fallback + facts.map(\.statement).joined(separator: " ")
            #expect(text.contains("Cafe") && text.contains(CurrencyFormatter.string(from: 20)))
            #expect(!text.contains("highest") && !text.contains("lowest"))
            #expect(!text.contains(CurrencyFormatter.string(from: 785)))
        }
    }
}
