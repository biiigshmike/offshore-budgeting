#if canImport(UIKit)
import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Offshore

@MainActor
struct MarinaPresentationRenderingTests {
    @Test(arguments: ["phone", "tablet", "accessible-dark"])
    func nativePresentationsRenderAtSupportedWidths(_ layout: String) throws {
        let width: CGFloat = layout == "tablet" ? 640 : 350
        let largeText = layout == "accessible-dark"
        for (name, presentation) in fixtures {
            let content = MarinaPresentationView(presentation: presentation, onShowMore: {})
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
            try data.write(to: URL(fileURLWithPath: "/tmp/marina-ui-preview-\(layout)-\(name).png"))
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
        return [("income", income), ("pace", pace), ("presets", presets), ("shared-trend", sharedTrend), ("metric", metric), ("card", cardMetric), ("transactions", transactions), ("ranking", ranking),
                ("empty", empty), ("comparison", comparison), ("trend", trend), ("share", share)]
    }
}
#endif
