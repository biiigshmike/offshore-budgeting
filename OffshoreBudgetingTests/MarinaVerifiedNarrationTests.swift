import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaVerifiedNarrationTests {
    @Test func clarificationNamesOnlyVerifiedCandidatesAndTheirActualKinds() throws {
        let result = MarinaDataResult(status: "candidates", scope: "Workspace", records: [
            .init(id: "card", kind: "card", title: "Apple Card"),
            .init(id: "merchant", kind: "merchant", title: "Apple")
        ], totalCount: 2)
        let text = try #require(MarinaVerifiedNarration.text(request: .init(tool: .findRecords), result: result))
        #expect(text == "Which did you mean: “Apple Card” (card), “Apple” (merchant)?")
        #expect(!text.contains("Total"))
    }

    @Test func reconciliationDirectionAndCurrentBalanceComeFromTheVerifiedMetric() throws {
        for amount in [-25.0, 0, 25] {
            let request = MarinaDataRequest(tool: .accounts, accountID: UUID().uuidString, scope: .reconciliation)
            let result = MarinaDataResult(scope: "September 2026", metrics: [
                .init(label: "Alex current reconciliation balance", value: amount),
                .init(label: "Selected period activity total", value: 12),
                .init(label: "Selected period activity count", value: 7, unit: .number)
            ])
            let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
            #expect(text.contains("Alex current reconciliation balance: \(CurrencyFormatter.string(from: amount))"))
            #expect(text.contains("Activity for September 2026: 7 entries"))
            #expect(text.contains("Money is owed to you.") == (amount > 0))
            #expect(text.contains("You owe money.") == (amount < 0))
            #expect(text.contains("This account is settled.") == (amount == 0))
        }
    }

    @Test func totalsAndDatesNeverComeFromThePartialRecordPage() throws {
        let request = MarinaDataRequest(operation: .transactions, tool: .expenses, limit: 1)
        let presentation = MarinaPresentation(id: "result", operation: .transactions, title: "Expenses",
            scopeLabel: "Blue Card · September 2026", qualifier: "Includes planned expenses.")
        let result = MarinaDataResult(presentation: presentation, scope: "September", metrics: [
            .init(label: "Total", value: 123.45)
        ], records: [.init(id: "row", kind: "variableExpense", title: "Purchase", amount: 10)],
            totalCount: 8, nextOffset: 1)
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.contains("Blue Card · September 2026"))
        #expect(text.contains(CurrencyFormatter.string(from: 123.45)))
        #expect(!text.contains(CurrencyFormatter.string(from: 10)))
        #expect(text.contains("Includes planned expenses."))
    }

    @Test func comparisonUsesCalculatedDirectionAndPercentWithoutRecomputing() throws {
        let request = MarinaDataRequest(operation: .comparison, tool: .expenses)
        let presentation = MarinaPresentation(id: "comparison", operation: .comparison, title: "Spending comparison",
            scopeLabel: "Card · October", chartPoints: [
                .init(id: "first", label: "Card · October", value: 30),
                .init(id: "second", label: "Card · September", value: 100)
            ])
        let result = MarinaDataResult(presentation: presentation, scope: "October", metrics: [
            .init(label: "Total", value: 30), .init(label: "Comparison total", value: 100),
            .init(label: "Difference", value: -70), .init(label: "Change percent", value: -70, unit: .percent)
        ])
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.hasPrefix("Card · October: \(CurrencyFormatter.string(from: 30)); Card · September: \(CurrencyFormatter.string(from: 100))"))
        #expect(text.contains("Difference: \(CurrencyFormatter.string(from: -70))"))
        #expect(text.contains(result.metrics[3].formatted))
    }

    @Test func emptyLookupAndInvalidRequestNeverBecomeFinancialZeroCaptions() throws {
        #expect(MarinaVerifiedNarration.text(request: .init(tool: .findRecords), result: .init(status: "empty", scope: "Workspace")) == nil)
        #expect(MarinaVerifiedNarration.text(request: .init(tool: .expenses), result: .init(status: "invalidRequest", scope: "Workspace")) == nil)
        let result = MarinaDataResult(status: "empty", scope: "Empty category · September", metrics: [.init(label: "Total", value: 0)])
        let text = try #require(MarinaVerifiedNarration.text(request: .init(tool: .expenses), result: result))
        #expect(text.contains("Empty category · September"))
        #expect(text.contains(CurrencyFormatter.string(from: 0)))
    }
}
