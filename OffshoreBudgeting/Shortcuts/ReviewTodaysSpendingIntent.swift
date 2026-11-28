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
                    let amount = CurrencyFormatter.string(from: $0.amount)
                    return String(localized: "\($0.name): \(amount)", comment: "A card name followed by its spending total in the Review Today's Spending shortcut.")
                }

                var lines = [
                    String(localized: "Today: \(CurrencyFormatter.string(from: summary.total))"),
                    String(localized: "\(summary.variableCount.formatted()) variable, \(summary.plannedCount.formatted()) planned")
                ]
                if !topCards.isEmpty {
                    let cardList = ListFormatter.localizedString(byJoining: topCards)
                    lines.append(String(localized: "Top cards: \(cardList)"))
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
