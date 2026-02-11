import AppIntents
import Foundation
import SwiftData

// MARK: - OpenOffshoreAppIntent

private struct OpenOffshoreAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Offshore"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

// MARK: - ReviewTodaysSpendingIntent

struct ReviewTodaysSpendingIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Today's Spending"
    static var description = IntentDescription("Summarize today's spending and optionally open Offshore to the Cards tab for review.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Open in Offshore")
    var openInOffshore: Bool

    init() {
        self.openInOffshore = false
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        let summary = try await MainActor.run {
            let dataStore = OffshoreIntentDataStore.shared

            return try dataStore.performInSelectedWorkspace { modelContext, workspace in
                let calendar = Calendar.current
                let dayStart = calendar.startOfDay(for: .now)
                let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? dayStart

                let workspaceID = workspace.id

                let variableDescriptor = FetchDescriptor<VariableExpense>(
                    predicate: #Predicate<VariableExpense> { expense in
                        expense.workspace?.id == workspaceID
                        && expense.transactionDate >= dayStart
                        && expense.transactionDate <= dayEnd
                    }
                )

                let plannedDescriptor = FetchDescriptor<PlannedExpense>(
                    predicate: #Predicate<PlannedExpense> { expense in
                        expense.workspace?.id == workspaceID
                        && expense.expenseDate >= dayStart
                        && expense.expenseDate <= dayEnd
                    }
                )

                let variableExpenses = try modelContext.fetch(variableDescriptor)
                let plannedExpenses = try modelContext.fetch(plannedDescriptor)

                let variableTotal = variableExpenses.reduce(0.0) { $0 + $1.amount }
                let plannedTotal = plannedExpenses.reduce(0.0) { $0 + $1.effectiveAmount() }
                let total = variableTotal + plannedTotal

                let variableCount = variableExpenses.count
                let plannedCount = plannedExpenses.count

                var totalsByCardName: [String: Double] = [:]
                for expense in variableExpenses {
                    let cardName = expense.card?.name ?? "Unknown Card"
                    totalsByCardName[cardName, default: 0] += expense.amount
                }
                for expense in plannedExpenses {
                    let cardName = expense.card?.name ?? "Unknown Card"
                    totalsByCardName[cardName, default: 0] += expense.effectiveAmount()
                }

                let topCards = totalsByCardName
                    .sorted { $0.value > $1.value }
                    .prefix(2)
                    .map { "\($0.key): \(CurrencyFormatter.string(from: $0.value))" }

                var lines: [String] = []
                lines.append("Today: \(CurrencyFormatter.string(from: total))")
                lines.append("\(variableCount.formatted()) variable, \(plannedCount.formatted()) planned")
                if !topCards.isEmpty {
                    lines.append("Top cards: \(topCards.joined(separator: ", "))")
                }

                return lines.joined(separator: "\n")
            }
        }

        if openInOffshore {
            await MainActor.run {
                UserDefaults.standard.set(
                    AppSection.cards.rawValue,
                    forKey: AppShortcutNavigationStore.pendingSectionKey
                )
            }

            return .result(
                opensIntent: OpenOffshoreAppIntent(),
                dialog: IntentDialog(stringLiteral: summary)
            )
        }

        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
