#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Offshore

@MainActor
struct MarinaPresentationRenderingTests {
    @Test(arguments: ["phone", "tablet", "accessible-dark"])
    func patternOverviewStaysBoundedWhenSupportingDatasetsGrow(_ layout: String) throws {
        let width: CGFloat = layout == "tablet" ? 640 : 350
        func height(_ count: Int) throws -> CGFloat {
            let content = MarinaPresentationView(presentation: densePatterns(groupCount: count), onPeakTransactions: {}, onShowMore: {})
                .padding(20).frame(width: width, alignment: .leading)
                .environment(\.dynamicTypeSize, layout == "accessible-dark" ? .accessibility3 : .large)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            let image = try #require(renderer.uiImage)
            return image.size.height
        }
        let previewHeight = try height(3)
        let denseHeight = try height(30)
        // Additional categories, merchants, frequency rows and contributors remain
        // available in disclosures; they must not inflate the initial chat bubble.
        #expect(abs(denseHeight - previewHeight) <= 1)
    }

    @Test(arguments: ["phone", "tablet", "accessible-dark"])
    func nativePresentationsRenderAtSupportedWidths(_ layout: String) throws {
        // Use the test app's sandbox and isolate previews from concurrent or previous runs.
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarinaPresentationRenderingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        print("Marina rendering previews (\(layout)): \(outputDirectory.path)")
        let width: CGFloat = layout == "tablet" ? 640 : 350
        let largeText = layout == "accessible-dark"
        for (name, presentation) in fixtures {
            let content = MarinaPresentationView(presentation: presentation, onPeakTransactions: {}, onShowMore: {})
                .padding(20)
                .frame(width: width, alignment: .leading)
                .background(Color(uiColor: .systemBackground))
                .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
                .environment(\.colorScheme, largeText ? .dark : .light)
            let renderer = ImageRenderer(content: content)
            renderer.proposedSize = ProposedViewSize(width: width, height: nil)
            renderer.scale = 2
            let image = try #require(renderer.uiImage)
            #expect(image.size.width == width)
            #expect(image.size.height > 0)
            let data = try #require(image.pngData())
            try data.write(to: outputDirectory.appendingPathComponent("marina-ui-preview-\(layout)-\(name).png"),
                           options: .atomic)
        }
    }

    private var fixtures: [(String, MarinaPresentation)] {
        let points: [MarinaPresentation.ChartPoint] = [
            .init(id: "rent", label: "Bills & Utilities", value: 1200, colorHex: "#5C8BDB"),
            .init(id: "food", label: "Groceries", value: 318.38, colorHex: "#54A380"),
            .init(id: "hair", label: "Hair Care", value: 40, colorHex: "#C46B9C")
        ]
        let card = MarinaPresentation.CardSnapshot(id: "card", name: "Apple Card", theme: "aqua", effect: "metal")
        let records: [MarinaPresentation.Record] = [
            .init(id: "first", kind: "plannedExpense", title: "MacBook Pro", date: "2026-10-31", amount: 233.25,
                  categoryName: "Electronics", categoryColorHex: "#5C8BDB", cardName: "Apple Card", plannedAmount: 233.25, actualAmount: 0),
            .init(id: "second", kind: "variableExpense", title: "A neighborhood grocery store with a longer name", date: "2026-10-17", amount: 318.38,
                  categoryName: "Groceries", categoryColorHex: "#54A380", cardName: "Apple Card"),
            .init(id: "third", kind: "variableExpense", title: "Salon", date: "2026-10-16", amount: 40,
                  categoryName: "Hair Care", categoryColorHex: "#C46B9C", cardName: "Apple Card")
        ]
        var listRequest = MarinaDataRequest(tool: .expenses)
        listRequest.operation = .transactions
        listRequest.limit = 5
        let metric = MarinaPresentation(id: "metric", operation: .summary, title: "Spending", scopeLabel: "Personal · October 2026",
                                        metrics: [.init(label: "Total", value: 3177.38)])
        var cardMetric = metric
        cardMetric.id = "card-metric"
        cardMetric.scopeLabel = "Apple Card · October 2026"
        cardMetric.metrics = [.init(label: "Total", value: 602.40)]
        cardMetric.card = card
        var cardSummary = cardMetric
        cardSummary.id = "card-summary"
        cardSummary.purpose = .cardSummary
        cardSummary.metrics = [.init(label: "Total", value: 602.40),
                               .init(label: "Planned card spending", value: 233.25),
                               .init(label: "Variable card spending", value: 369.15)]
        let transactions = MarinaPresentation(
            id: "transactions", operation: .transactions, title: "Expenses", scopeLabel: "Apple Card · October 2026",
            qualifier: "Includes planned expenses.", records: records, totalCount: 8,
            pagination: .init(workspaceID: UUID(), request: listRequest, visibleCount: records.count)
        )
        let ranking = MarinaPresentation(id: "ranking", operation: .ranking, title: "Spending by category", scopeLabel: "Personal · October 2026",
                                         chartPoints: points, totalCount: points.count)
        let empty = MarinaPresentation(id: "empty", operation: .summary, title: "Spending", scopeLabel: "Hair Care · October 2026",
                                       metrics: [.init(label: "Total", value: 0)], isEmpty: true)
        let comparison = MarinaPresentation(
            id: "comparison", operation: .comparison, title: "Spending comparison", scopeLabel: "Apple Card · October 2026",
            metrics: [.init(label: "Difference", value: -200), .init(label: "Change percent", value: -25, unit: .percent)],
            chartPoints: [.init(id: "now", label: "Apple Card · October 2026", value: 600),
                          .init(id: "then", label: "Apple Card · September 2026", value: 800)], totalCount: 31
        )
        let trend = MarinaPresentation(id: "trend", topicKey: "expenses::trend:none", operation: .trend, title: "Spending over time", scopeLabel: "Personal · October 2026",
                                      chartPoints: [.init(id: "1", label: "Oct 1", value: 1200), .init(id: "2", label: "Oct 2", value: -50), .init(id: "3", label: "Oct 3", value: 200)])
        let share = MarinaPresentation(id: "share", operation: .share, title: "Share of spending", scopeLabel: "Personal · October 2026", chartPoints: points)
        let income = MarinaPresentation(id: "income", incomeProgress: .init(actual: 1500.38, planned: 1000), operation: .summary, title: "Income progress", scopeLabel: "Personal · October 2026")
        let pace = MarinaPresentation(id: "pace", budgetPace: .init(actual: 700.38, expected: 800, planned: 1600, difference: -99.62, elapsedPercent: 0.5), operation: .summary, title: "Budget pace", scopeLabel: "Personal · October 2026")
        let presets = MarinaPresentation(id: "presets", operation: .transactions, title: "Upcoming preset expenses", scopeLabel: "Personal · Oct 17–23, 2026", records: [
            .init(id: "preset-occurrence", kind: "plannedExpense", title: "Subscription", date: "2026-10-20", amount: 10.38,
                  preset: .init(id: "preset", title: "A subscription with a longer descriptive name", plannedAmount: 10.38, schedule: "Monthly • 20th", assignedBudgetCount: 2))])
        let sharedTrend = MarinaPresentation(id: "shared-trend", topicKey: "expenses::trend:none", operation: .trend, title: "Spending over time", scopeLabel: "Personal · October 2026", chartPoints: [
            .init(id: "a", label: "Oct 17", value: 150.38, slices: [.init(name: "Groceries", colorHex: "#54A380", amount: 100.38), .init(name: "Bills", colorHex: "#5C8BDB", amount: 50)]),
            .init(id: "b", label: "Oct 18", value: 200, slices: [.init(name: "Groceries", colorHex: "#54A380", amount: 100), .init(name: "Bills", colorHex: "#5C8BDB", amount: 100)])])
        let availability = MarinaPresentation(id: "availability", purpose: .categoryAvailability,
            report: .init(categories: [
                .init(id: UUID().uuidString, name: "Dining and restaurants with a longer category name", colorHex: "#C46B9C", minimum: 50, maximum: 200,
                      planned: 80, variable: 160, available: -40, percentUsed: 120, status: "over"),
                .init(id: UUID().uuidString, name: "Groceries", colorHex: "#54A380", maximum: 500,
                      planned: 300, variable: 150, available: 50, percentUsed: 90, status: "near")], budgetName: "October household budget"),
            operation: .summary, title: "Category availability", scopeLabel: "Personal · October 2026")
        let timelineSeries: [MarinaReport.Series] = [
            .init(id: "actual", label: "Received income", points: [.init(id: "1", label: "Oct 1", value: 400), .init(id: "2", label: "Oct 8", value: 800)]),
            .init(id: "planned", label: "Planned income", points: [.init(id: "1", label: "Oct 1", value: 500), .init(id: "2", label: "Oct 8", value: 700)])]
        let pairedIncome = MarinaPresentation(id: "paired-income", purpose: .incomeTimeline,
            report: .init(series: timelineSeries, cumulative: false), operation: .trend,
            title: "Income over time", scopeLabel: "Personal · October 2026")
        let pairedSavings = MarinaPresentation(id: "paired-savings", purpose: .savingsTimeline,
            report: .init(series: [
                .init(id: "actual", label: "Actual savings", points: [.init(id: "1", label: "Oct 1", value: -100), .init(id: "2", label: "Oct 8", value: 400)]),
                .init(id: "projected", label: "Projected savings", points: [.init(id: "1", label: "Oct 1", value: 200), .init(id: "2", label: "Oct 8", value: 300)])], cumulative: true),
            operation: .trend, title: "Cumulative savings", scopeLabel: "Personal · October 2026")
        let patterns = densePatterns(groupCount: 5)
        var movement = patterns
        movement.id = "movement"
        movement.chartIntent = .movementOverTime
        movement.title = "Spending movement"
        let split = MarinaPresentation(id: "split", report: .init(transactions: [
            .init(id: "split-row", transactionKind: "debit", grossAmount: 100, recordedAmount: 100, effectiveAmount: 100,
                  splitAmount: 30, savingsOffset: 20, budgetImpact: 50, accountName: "Shared holiday expenses",
                  sourcePresetName: "Monthly dinner", sourceBudgetName: "October")]),
            operation: .transactions, title: "Expense details", scopeLabel: "Apple Card · October 2026",
            records: [.init(id: "split-row", kind: "variableExpense", title: "Dinner", date: "2026-10-17", amount: 50, cardName: "Apple Card")])
        return [("availability", availability), ("paired-income", pairedIncome), ("paired-savings", pairedSavings), ("patterns", patterns), ("movement", movement), ("split", split), ("income", income), ("pace", pace), ("presets", presets), ("shared-trend", sharedTrend), ("metric", metric), ("card", cardMetric), ("card-summary", cardSummary), ("transactions", transactions), ("ranking", ranking),
                ("empty", empty), ("comparison", comparison), ("trend", trend), ("share", share)]
    }

    private func densePatterns(groupCount: Int) -> MarinaPresentation {
        let categories: [MarinaReport.Group] = (1...groupCount).map { index in
            .init(id: "category-\(index)", title: "Category \(index)", amount: Double(200 - index), colorHex: "#527DC4",
                  plannedAmount: 50, variableAmount: Double(150 - index), count: index + 1, sharePercent: 10)
        }
        let merchants: [MarinaReport.Group] = (1...groupCount).map { index in
            .init(id: "merchant-\(index)", title: "Merchant \(index)", amount: Double(100 - index),
                  plannedAmount: 0, variableAmount: Double(100 - index), count: index + 1, sharePercent: 5)
        }
        let points: [MarinaPresentation.ChartPoint] = (1...5).map { index -> MarinaPresentation.ChartPoint in
            let date = "2026-10-0\(index)"
            let total = Double(100 + index * 20)
            let dining = Double(80 + index * 20)
            let slices: [MarinaPresentation.ChartSlice] = [
                .init(name: "Dining", colorHex: "#527DC4", amount: dining),
                .init(name: "Groceries", colorHex: "#54A380", amount: 20)]
            return MarinaPresentation.ChartPoint(id: date, label: "Oct \(index)", value: total,
                                                  date: date, slices: slices)
        }
        let seriesPoints: [MarinaReport.Point] = points.map { point in
            MarinaReport.Point(id: point.id, label: point.label, date: point.date, value: point.value)
        }
        let series = MarinaReport.Series(id: "spending", label: "Spending", points: seriesPoints)
        var drilldown = MarinaDataRequest(operation: .transactions, tool: .expenses)
        drilldown.startDate = "2026-10-05"; drilldown.endDate = "2026-10-05"
        let peak = MarinaReport.Peak(startDate: "2026-10-05", endDate: "2026-10-05", amount: 200,
                                    leadingCategory: "Dining", leadingCategoryAmount: 180, contributors: categories,
                                    drilldownRequest: drilldown)
        let report = MarinaReport(groups: categories, merchants: merchants, frequentMerchants: merchants,
                                  series: [series], cumulative: false, peak: peak)
        return MarinaPresentation(id: "patterns", purpose: .spendingPatterns, topicKey: "expenses:spendingPatterns:trend:none",
            report: report,
            operation: .trend, title: "Spending patterns", scopeLabel: "Personal · October 2026",
            metrics: [.init(label: "Total", value: 800)], chartPoints: points, totalCount: 5)
    }
}
#endif
