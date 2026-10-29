import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaNarrationPaginationTests {
    @Test func laterPagesCannotClaimTheirFirstRowIsTheGlobalExtreme() throws {
        for operation in [MarinaDataRequest.Operation.ranking, .share, .transactions] {
            for sort in [MarinaDataRequest.Sort.largest, .smallest] {
                var request = MarinaDataRequest(operation: operation, tool: .expenses,
                                               grouping: .category, sort: sort, limit: 1)
                request.offset = 5
                let result = MarinaDataResult(scope: "October 2026", metrics: [
                    .init(label: "Total", value: 900), .init(label: "Tied leading groups", value: 2)
                ], records: [.init(id: "later", kind: "group", title: "Books", amount: 20)], totalCount: 10)
                let fallback = try #require(MarinaVerifiedNarration.text(request: request, result: result))
                let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
                let text = fallback + facts.map(\.statement).joined(separator: " ")
                #expect(text.contains("Books") && text.contains(CurrencyFormatter.string(from: 20)))
                #expect(!text.contains("highest") && !text.contains("lowest") && !text.contains("tied"))
                request.offset = 0
                let firstPage = try #require(MarinaVerifiedNarration.text(request: request, result: result))
                #expect(firstPage.contains(sort == .largest ? "highest" : "lowest"))
            }
        }
    }
}
