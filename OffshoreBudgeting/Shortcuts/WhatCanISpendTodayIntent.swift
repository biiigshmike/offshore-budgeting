import AppIntents
import Foundation

// MARK: - WhatCanISpendTodayIntent

struct WhatCanISpendTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "What Can I Spend Today?"
    static var description = IntentDescription("Get a safe-to-spend amount for today based on your default budgeting period.")
    static var openAppWhenRun: Bool = false

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
        let now = Date.now
        let rawBudgetingPeriod = UserDefaults.standard.string(forKey: "general_defaultBudgetingPeriod")
        let budgetingPeriod = BudgetingPeriod(rawValue: rawBudgetingPeriod ?? BudgetingPeriod.monthly.rawValue) ?? .monthly

        let summary = try OffshoreIntentDataStore.shared.performInSelectedWorkspace { _, workspace in
            SafeSpendTodayCalculator.calculate(
                workspace: workspace,
                budgetingPeriod: budgetingPeriod,
                now: now
            )
        }

        let periodRemainingText = CurrencyFormatter.string(from: summary.periodRemainingRoom)
        let safeSpendTodayText = CurrencyFormatter.string(from: summary.safeToSpendToday)

        var lines = [
            "Budget period: \(summary.budgetingPeriod.displayTitle)",
            "Period remaining room: \(periodRemainingText)",
            "Safe to spend today: \(safeSpendTodayText)"
        ]

        if !summary.isDaily {
            lines.append("Days left in period: \(summary.daysLeftInPeriod.formatted())")
        }

        return lines.joined(separator: "\n")
    }
}
