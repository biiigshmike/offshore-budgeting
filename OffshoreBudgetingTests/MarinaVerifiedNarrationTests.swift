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
            #expect(text.contains("Alex"))
            #expect(text.contains("there are 7 entries"))
            #expect(text.contains("Alex owes you") == (amount > 0))
            #expect(text.contains("You owe Alex") == (amount < 0))
            #expect(text.contains("is settled") == (amount == 0))
            if amount != 0 { #expect(text.contains(CurrencyFormatter.string(from: abs(amount)))) }
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
        #expect(text.contains("Card · October") && text.contains("Card · September"))
        #expect(text.contains(CurrencyFormatter.string(from: 30)) && text.contains(CurrencyFormatter.string(from: 100)))
        #expect(text.contains("\(CurrencyFormatter.string(from: 70)) lower"))
        #expect(!text.contains("higher"))
        #expect(text.contains((0.7).formatted(.percent.precision(.fractionLength(0...1)))))
    }

    @Test func emptyLookupAndInvalidRequestNeverBecomeFinancialZeroCaptions() throws {
        #expect(MarinaVerifiedNarration.text(request: .init(tool: .findRecords), result: .init(status: "empty", scope: "Workspace")) == nil)
        #expect(MarinaVerifiedNarration.text(request: .init(tool: .expenses), result: .init(status: "invalidRequest", scope: "Workspace")) == nil)
        let result = MarinaDataResult(status: "empty", scope: "Empty category · September", metrics: [.init(label: "Total", value: 0)])
        let text = try #require(MarinaVerifiedNarration.text(request: .init(tool: .expenses), result: result))
        #expect(text.contains("Empty category · September"))
        #expect(text.contains(CurrencyFormatter.string(from: 0)))
    }

    @Test func categoryWinnerAndSmallestExpenseAreTheFocalAnswer() throws {
        let result = MarinaDataResult(scope: "October", metrics: [.init(label: "Total", value: 600)],
            records: [.init(id: "dining", kind: "group", title: "Dining", amount: 125.38)], totalCount: 4)
        let ranking = MarinaDataRequest(operation: .ranking, tool: .expenses, grouping: .category)
        let rankedText = try #require(MarinaVerifiedNarration.text(request: ranking, result: result))
        #expect(rankedText.contains("Dining") && rankedText.contains(CurrencyFormatter.string(from: 125.38)))
        #expect(!rankedText.contains(CurrencyFormatter.string(from: 600)))
        let minimum = MarinaDataRequest(operation: .transactions, tool: .expenses, sort: .smallest, limit: 1)
        let minimumText = try #require(MarinaVerifiedNarration.text(request: minimum, result: result))
        #expect(minimumText.contains("lowest expense"))
        #expect(minimumText.contains(CurrencyFormatter.string(from: 125.38)))
    }

    @Test func periodChoiceIsAQuestionRatherThanAnInvalidFilterCaption() throws {
        let result = MarinaDataResult(status: "needsPeriodChoice", scope: "Personal", records: [
            .init(id: "one", kind: "budget", title: "October"), .init(id: "two", kind: "budget", title: "Fall")
        ], totalCount: 2)
        let text = try #require(MarinaVerifiedNarration.text(request: .init(tool: .expenses), result: result))
        #expect(text.contains("October") && text.contains("Fall"))
        #expect(text.contains("Which one"))
        #expect(!text.contains("filters"))
    }

    @Test func requestedAvailabilityCountPrecedesTheCategoryBreakdown() throws {
        var request = MarinaDataRequest(purpose: .categoryAvailability, tool: .budgetSummary)
        request.metric = .count
        let result = MarinaDataResult(report: MarinaReport(categories: []), scope: "October", metrics: [
            .init(label: "Count", value: 7, unit: .number), .init(label: "Total", value: 900)
        ])
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.contains("7 matching categories"))
        #expect(!text.contains("No categories"))
    }

    @Test func transactionEvidenceRetainsKindAndBudgetImpact() throws {
        let request = MarinaDataRequest(operation: .transactions, tool: .expenses)
        let transaction = MarinaReport.Transaction(id: "refund", transactionKind: "credit", grossAmount: 50,
            recordedAmount: 50, effectiveAmount: -50, budgetImpact: -50)
        let result = MarinaDataResult(report: MarinaReport(transactions: [transaction]), scope: "October", records: [
            .init(id: "refund", kind: "variableExpense", title: "Returned shoes", amount: -50)
        ], totalCount: 1)
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.contains("credit"))
        #expect(text.contains("budget impact"))
        #expect(text.contains(CurrencyFormatter.string(from: -50)))
    }

    @Test func missingPeriodLeaderDoesNotBecomeAZeroAmountComparison() throws {
        let request = MarinaDataRequest(operation: .comparison, tool: .expenses, grouping: .category)
        let report = MarinaReport(leaders: [
            .init(scope: "October", title: "Dining", amount: 500),
            .init(scope: "June", title: nil, amount: nil)
        ])
        let result = MarinaDataResult(report: report, scope: "October", metrics: [.init(label: "Difference", value: 500)])
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.contains("no matching expenses for June"))
        #expect(!text.contains("higher") && !text.contains("lower"))
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
        #expect(!facts.contains { $0.subject.contains("difference") })
    }

    @Test func successfulInventoryHasFreshNameEvidence() {
        let request = MarinaDataRequest(tool: .findRecords, recordKind: "card")
        let result = MarinaDataResult(scope: "Personal", records: [.init(id: "card", kind: "card", title: "Apple Card")], totalCount: 1)
        let facts = MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0")
        #expect(facts.contains { $0.subject == "Apple Card" && $0.value == "card" })
        #expect(facts.first?.isFocus == true)
    }

    @Test func budgetNarrationRetainsDistinctComponentsInNaturalPropositions() throws {
        let request = MarinaDataRequest(purpose: .budgetDetails, tool: .budgetSummary)
        let values: [(String, Double)] = [("Actual income", 3000), ("Planned income", 3200),
            ("Planned spending", 700), ("Recorded planned expenses", 500), ("Effective planned spending", 550),
            ("Variable spending", 50), ("Total", 600), ("Actual savings", 2400), ("Projected savings", 2600), ("Max savings", 2650)]
        let result = MarinaDataResult(scope: "October", metrics: values.map { .init(label: $0.0, value: $0.1) })
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        for (_, value) in values { #expect(text.contains(CurrencyFormatter.string(from: value))) }
        #expect(text.contains("You have received"))
        #expect(text.contains("Your savings are"))
        #expect(!text.contains("savings is"))
    }

}
