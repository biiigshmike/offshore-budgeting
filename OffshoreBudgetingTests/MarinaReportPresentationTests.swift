import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaReportPresentationTests {
    @Test func oldSnapshotsDecodeWithoutReportData() throws {
        let old = MarinaPresentation(id: "old", operation: .summary, title: "Spending", scopeLabel: "October",
                                     metrics: [.init(label: "Total", value: 25)])
        let data = try JSONEncoder().encode(old)
        let decoded = try JSONDecoder().decode(MarinaPresentation.self, from: data)
        #expect(decoded.report == nil && decoded == old)
        #expect(decoded.chartIntent == nil)
    }

    @Test func optionalReportFactsDoNotReplaceTheOperationsPrimaryChart() {
        var presentation = MarinaPresentation(id: "ranking", report: .init(groups: [
            .init(id: "food", title: "Dining", amount: 25, plannedAmount: 5, variableAmount: 20)]),
            operation: .ranking, title: "Spending by category", scopeLabel: "October")
        #expect(MarinaPresentationLayout.resolve(presentation) == .chart)
        presentation.operation = .share
        #expect(MarinaPresentationLayout.resolve(presentation) == .chart)
        presentation.operation = .comparison
        #expect(MarinaPresentationLayout.resolve(presentation) == .chart)
        presentation.operation = .trend
        #expect(MarinaPresentationLayout.resolve(presentation) == .timeline)
        presentation.purpose = .spendingPatterns
        #expect(MarinaPresentationLayout.resolve(presentation) == .spendingPatterns)
    }

    @Test func semanticChartIntentSurvivesSavingAndOnlyChangesTheVisual() throws {
        var presentation = MarinaPresentation(id: "trend", topicKey: "expenses::trend:none",
            report: .init(series: [.init(id: "spending", label: "Spending", points: [
                .init(id: "first", label: "First", date: "2026-10-01", value: 20),
                .init(id: "second", label: "Second", date: "2026-10-02", value: -5)])], cumulative: false),
            operation: .trend, title: "Spending", scopeLabel: "October")
        #expect(MarinaPresentationLayout.timelineStyle(for: presentation) == .spendingBars)
        let amounts = presentation.report?.series?.first?.points.map(\.value)
        presentation.chartIntent = .movementOverTime
        let saved = try JSONDecoder().decode(MarinaPresentation.self, from: JSONEncoder().encode(presentation))
        #expect(saved.chartIntent == .movementOverTime)
        #expect(MarinaPresentationLayout.timelineStyle(for: saved) == .movementLines)
        #expect(saved.report?.series?.first?.points.map(\.value) == amounts)
        #expect(saved.report?.cumulative == false)
        presentation.chartIntent = .periodComparison
        #expect(MarinaPresentationLayout.timelineStyle(for: presentation) == .spendingBars)
    }

    @Test func sharedTimelineOrdersVerifiedDatesWithoutChangingAmountsOrInventingDates() {
        let series = HomeFinancialChartSeries(id: "flow", label: "Spending", points: [
            .init(id: "late", label: "A", value: -5, date: "2026-10-08"),
            .init(id: "early", label: "Z", value: 20, date: "2026-10-01")])
        #expect(series.points.map(\.id) == ["early", "late"])
        #expect(series.points.map(\.value) == [20, -5])
        let legacy = HomeFinancialChartSeries(id: "old", label: "Old", points: [
            .init(id: "z", label: "Z", value: 20), .init(id: "a", label: "A", value: -5)])
        #expect(legacy.points.map(\.id) == ["z", "a"])
        #expect(legacy.points.allSatisfy { $0.date == nil })
    }

    @Test func cardSummaryUsesSharedContentOnlyWhenAllComponentsWereVerified() {
        var presentation = MarinaPresentation(id: "card", purpose: .cardSummary, operation: .summary,
            title: "Card spending", scopeLabel: "October", metrics: [.init(label: "Total", value: 30)],
            card: .init(id: UUID().uuidString, name: "Card", theme: "ruby", effect: "plastic"))
        #expect(MarinaPresentationLayout.resolve(presentation) == .metrics)
        presentation.metrics += [.init(label: "Planned card spending", value: 10), .init(label: "Variable card spending", value: 20)]
        #expect(MarinaPresentationLayout.resolve(presentation) == .cardSummary)
    }

    @Test func detailedSnapshotsRoundTripWithoutLosingSeriesOrTransactionMeaning() throws {
        var drilldown = MarinaDataRequest(operation: .transactions, tool: .expenses)
        drilldown.startDate = "2026-10-01"
        drilldown.endDate = "2026-10-07"
        drilldown.cardID = "scoped-card"
        let report = MarinaReport(
            categories: [.init(id: UUID().uuidString, name: "Groceries", colorHex: "#00AA88", minimum: 100,
                maximum: 300, planned: 50, variable: 240, available: 10, percentUsed: 96.6667, status: "near")],
            transactions: [.init(id: "purchase", transactionKind: "debit", grossAmount: 100,
                effectiveAmount: 100, splitAmount: 30, savingsOffset: 20, budgetImpact: 50,
                accountName: "Shared", sourcePresetID: "preset", sourcePresetName: "Dinner")],
            series: [.init(id: "actual", label: "Actual", points: [.init(id: "oct", label: "October", value: 75)]),
                     .init(id: "projected", label: "Projected", points: [.init(id: "oct", label: "October", value: 100)])],
            cumulative: true,
            peak: .init(startDate: "2026-10-01", endDate: "2026-10-07", amount: 100,
                contributors: [.init(id: "food", title: "Groceries", amount: 100)],
                transactionIDs: ["purchase"], drilldownRequest: drilldown), budgetName: "October")
        let presentation = MarinaPresentation(id: "detailed", report: report, operation: .summary,
                                             title: "Report", scopeLabel: "Personal")
        let decoded = try JSONDecoder().decode(MarinaPresentation.self, from: JSONEncoder().encode(presentation))
        #expect(decoded == presentation)
        #expect(decoded.report?.series?.count == 2)
        #expect(decoded.report?.transactions?.first?.budgetImpact == 50)
        #expect(decoded.report?.peak?.contributors?.first?.title == "Groceries")
        #expect(decoded.report?.peak?.transactionIDs == ["purchase"])
        #expect(decoded.report?.peak?.drilldownRequest == drilldown)
    }

    @Test func changedReportFactsKeepTheNewVisualVisible() {
        var previous = MarinaPresentation(id: "previous", identityKey: "same", topicKey: "budget",
            report: .init(categories: []), operation: .summary, title: "Availability", scopeLabel: "October")
        var current = previous
        current.id = "current"
        #expect(!MarinaPresentationDisplayPolicy.shouldShow(current, after: [previous]))
        current.report?.categories = [.init(id: "category", name: "Food", colorHex: "#00AA88",
            maximum: 100, planned: 10, variable: 110, available: -20, percentUsed: 120, status: "over")]
        #expect(MarinaPresentationDisplayPolicy.shouldShow(current, after: [previous]))
        previous.report = nil
        #expect(MarinaPresentationDisplayPolicy.shouldShow(current, after: [previous]))
    }
}
