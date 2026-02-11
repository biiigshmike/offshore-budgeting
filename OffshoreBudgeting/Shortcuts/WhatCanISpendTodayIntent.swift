import AppIntents
import Foundation

// MARK: - WhatCanISpendTodayIntent

struct WhatCanISpendTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "What Can I Spend Today?"
    static var description = IntentDescription("Get your current month remaining budget, a category remaining amount, and a safe daily spend amount.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Category")
    var category: OffshoreCategoryEntity?

    init() {
        self.category = nil
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let summary = try await MainActor.run {
            try buildSummary()
        }

        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: summary)
        )
    }

    // MARK: - Summary

    @MainActor
    private func buildSummary() throws -> String {
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart

        let result = try OffshoreIntentDataStore.shared.performInSelectedWorkspace { _, workspace in
            HomeCategoryLimitsAggregator.build(
                budgets: workspace.budgets ?? [],
                categories: workspace.categories ?? [],
                plannedExpenses: workspace.plannedExpenses ?? [],
                variableExpenses: workspace.variableExpenses ?? [],
                rangeStart: monthStart,
                rangeEnd: monthEnd,
                inclusionPolicy: .allCategoriesInfinityWhenMissing
            )
        }

        guard result.activeBudget != nil else {
            return "No active budget overlaps this month, so I can't compute a safe spend amount yet."
        }

        let limitedMetrics = result.metrics.filter { $0.maxAmount != nil }
        guard !limitedMetrics.isEmpty else {
            return "This budget has no category limits, so there is no monthly cap to calculate safe daily spending from."
        }

        let monthlyRemaining = limitedMetrics.reduce(0.0) { partial, metric in
            partial + (metric.availableRaw(for: .all) ?? 0)
        }

        let todayStart = calendar.startOfDay(for: now)
        let monthEndStart = calendar.startOfDay(for: monthEnd)
        let remainingDays = max(1, (calendar.dateComponents([.day], from: todayStart, to: monthEndStart).day ?? 0) + 1)
        let safeDailyAmount = max(0, monthlyRemaining) / Double(remainingDays)

        let categoryLine = categorySummaryLine(
            from: result,
            selectedCategoryID: category?.id
        )

        let monthlyRemainingText = CurrencyFormatter.string(from: monthlyRemaining)
        let safeDailyText = CurrencyFormatter.string(from: safeDailyAmount)
        let daysText = remainingDays.formatted()

        return [
            "Category remaining: \(categoryLine)",
            "Monthly budget remaining: \(monthlyRemainingText)",
            "Safe to spend today: \(safeDailyText) (\(daysText) day(s) left this month)"
        ].joined(separator: "\n")
    }

    private func categorySummaryLine(from result: HomeCategoryAvailabilityResult, selectedCategoryID: String?) -> String {
        let limitedMetrics = result.metrics.filter { $0.maxAmount != nil }

        if let selectedCategoryID {
            if let metric = limitedMetrics.first(where: { $0.categoryID.uuidString == selectedCategoryID }) {
                let remaining = metric.availableRaw(for: .all) ?? 0
                return "\(metric.name): \(CurrencyFormatter.string(from: remaining))"
            }
            return "Selected category has no limit in this budget"
        }

        guard let tightest = limitedMetrics.min(by: { ($0.availableRaw(for: .all) ?? 0) < ($1.availableRaw(for: .all) ?? 0) }) else {
            return "No limited categories"
        }

        let remaining = tightest.availableRaw(for: .all) ?? 0
        return "\(tightest.name): \(CurrencyFormatter.string(from: remaining))"
    }
}
