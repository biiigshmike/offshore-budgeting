import AppIntents
import Foundation

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
                let summary = try ReviewTodaySummary.load(workspaceID: workspace.id, in: modelContext)
                let topCards = summary.topCards.map {
                    "\($0.name): \(CurrencyFormatter.string(from: $0.amount))"
                }

                var lines = [
                    "Today: \(CurrencyFormatter.string(from: summary.total))",
                    "\(summary.variableCount.formatted()) variable, \(summary.plannedCount.formatted()) planned"
                ]
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
