import AppIntents
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

// MARK: - MixedClipboardRowsRoute

enum MixedClipboardRowsRoute: String, AppEnum {
    case routeToIncomeImport
    case routeToExpenseImport

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mixed Rows Route"

    static var caseDisplayRepresentations: [MixedClipboardRowsRoute: DisplayRepresentation] = [
        .routeToIncomeImport: "Route to Income Import",
        .routeToExpenseImport: "Route to Expense Import"
    ]
}

// MARK: - ImportFromClipboardIntent

struct ImportFromClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "Import From Clipboard"
    static var description = IntentDescription("Parse transaction text from clipboard-style input and return an import preview summary.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Clipboard Text",
        requestValueDialog: IntentDialog("Paste or enter transaction text to import.")
    )
    var clipboardText: String?

    @Parameter(title: "Open in Offshore")
    var openInOffshore: Bool

    @Parameter(
        title: "Expense Card",
        requestValueDialog: IntentDialog("Which card should expense rows import into?")
    )
    var expenseCard: OffshoreCardEntity?

    @Parameter(title: "When Mixed Rows")
    var mixedRowsRoute: MixedClipboardRowsRoute

    init() {
        self.clipboardText = nil
        self.openInOffshore = false
        self.expenseCard = nil
        self.mixedRowsRoute = .routeToExpenseImport
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> & OpensIntent {
        let resolvedClipboardText = await MainActor.run {
            resolveClipboardText()
        }
        guard !resolvedClipboardText.isEmpty else {
            throw $clipboardText.needsValueError(
                "Clipboard wasn't available. Pass text into 'Clipboard Text' or use Get Clipboard before this action."
            )
        }

        let preview: ShortcutImportPreview
        do {
            preview = try await MainActor.run {
                try ShortcutImportPreviewService.shared.previewFromClipboard(text: resolvedClipboardText)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not parse clipboard text into transactions."
            return .result(
                value: message,
                dialog: IntentDialog(stringLiteral: message)
            )
        }

        guard openInOffshore else {
            return .result(
                value: preview.summaryText,
                dialog: IntentDialog(stringLiteral: preview.summaryText)
            )
        }

        let hasExpenseRows = preview.expenseRows > 0
        let hasIncomeRows = preview.incomeRows > 0

        let routeToExpense = hasExpenseRows && (!hasIncomeRows || mixedRowsRoute == .routeToExpenseImport)
        let routeToIncome = hasIncomeRows && (!hasExpenseRows || mixedRowsRoute == .routeToIncomeImport)

        if routeToExpense {
            guard let expenseCard else {
                throw $expenseCard.needsValueError("Choose a card to import expense rows.")
            }

            let cardID = expenseCard.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cardID.isEmpty else {
                throw $expenseCard.needsValueError("Choose a valid card to import expense rows.")
            }

            await MainActor.run {
                UserDefaults.standard.set(
                    AppSection.cards.rawValue,
                    forKey: AppShortcutNavigationStore.pendingSectionKey
                )
                UserDefaults.standard.set(
                    AppShortcutNavigationStore.PendingAction.openCardImportReview.rawValue,
                    forKey: AppShortcutNavigationStore.pendingActionKey
                )
                UserDefaults.standard.set(
                    resolvedClipboardText,
                    forKey: AppShortcutNavigationStore.pendingImportClipboardTextKey
                )
                UserDefaults.standard.set(
                    cardID,
                    forKey: AppShortcutNavigationStore.pendingImportCardIDKey
                )
            }

            return .result(
                value: preview.summaryText,
                opensIntent: OpenOffshoreForImportIntent(),
                dialog: IntentDialog(stringLiteral: preview.summaryText)
            )
        }

        if routeToIncome {
            await MainActor.run {
                UserDefaults.standard.set(
                    AppSection.income.rawValue,
                    forKey: AppShortcutNavigationStore.pendingSectionKey
                )
                UserDefaults.standard.set(
                    AppShortcutNavigationStore.PendingAction.openIncomeImportReview.rawValue,
                    forKey: AppShortcutNavigationStore.pendingActionKey
                )
                UserDefaults.standard.set(
                    resolvedClipboardText,
                    forKey: AppShortcutNavigationStore.pendingImportClipboardTextKey
                )
                UserDefaults.standard.set(
                    "",
                    forKey: AppShortcutNavigationStore.pendingImportCardIDKey
                )
            }

            return .result(
                value: preview.summaryText,
                opensIntent: OpenOffshoreForImportIntent(),
                dialog: IntentDialog(stringLiteral: preview.summaryText)
            )
        }

        let message = "I parsed your clipboard, but couldn't classify any import rows."
        return .result(
            value: message,
            dialog: IntentDialog(stringLiteral: message)
        )
    }

    private func resolveClipboardText() -> String {
        #if canImport(UIKit)
        if let fromPasteboard = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           !fromPasteboard.isEmpty {
            return fromPasteboard
        }
        #endif

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        if let fromPasteboard = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fromPasteboard.isEmpty {
            return fromPasteboard
        }
        #endif

        let provided = (clipboardText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !provided.isEmpty { return provided }

        return ""
    }
}
