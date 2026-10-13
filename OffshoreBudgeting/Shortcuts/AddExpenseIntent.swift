import AppIntents
import Foundation

// MARK: - AddExpenseIntent

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Add an expense in your selected Offshore workspace using the fields in Shortcuts.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        requestValueDialog: IntentDialog("What amount should I log?")
    )
    var amountText: String?

    @Parameter(
        title: "Offshore Card",
        requestValueDialog: IntentDialog("Which Offshore card should this expense use?")
    )
    var card: OffshoreCardEntity?

    @Parameter(
        title: "Category",
        requestValueDialog: IntentDialog("Which category should this expense use?")
    )
    var category: OffshoreCategoryEntity?

    @Parameter(
        title: "Merchant",
        requestValueDialog: IntentDialog("What merchant should I use for category matching?")
    )
    var merchant: String?

    @Parameter(
        title: "Date",
        requestValueDialog: IntentDialog("What date should I use for this expense?")
    )
    var date: Date?

    init() {
        self.amountText = nil
        self.card = nil
        self.category = nil
        self.merchant = nil
        self.date = nil
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let card, !card.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw $card.needsValueError("Please choose an Offshore card.")
        }

        let request = AddExpenseShortcutExecutor.Request(
            amountText: amountText,
            offshoreCardID: card.id,
            walletCardName: nil,
            categoryID: category?.id,
            merchant: merchant,
            date: date
        )

        do {
            let addedSummary = try await MainActor.run {
                try AddExpenseShortcutExecutor.executeInSelectedWorkspace(request: request)
            }

            return .result(dialog: IntentDialog(stringLiteral: addedSummary))
        } catch let requestError as AddExpenseShortcutExecutor.RequestValidationError {
            switch requestError {
            case .invalidAmount:
                throw $amountText.needsValueError(
                    IntentDialog(stringLiteral: requestError.errorDescription ?? "Please provide a valid amount.")
                )
            case .missingCard:
                throw $card.needsValueError("Please choose an Offshore card.")
            case .missingMerchant:
                throw $merchant.needsValueError(
                    IntentDialog(
                        stringLiteral: requestError.errorDescription
                            ?? "Please provide a merchant or description for the expense."
                    )
                )
            case .missingDate:
                throw $date.needsValueError(
                    IntentDialog(stringLiteral: requestError.errorDescription ?? "Please provide a date.")
                )
            }
        } catch let validation as TransactionEntryService.ValidationError {
            return .result(dialog: IntentDialog(stringLiteral: validation.errorDescription ?? "Couldn't add expense."))
        } catch let intentError as OffshoreIntentDataStore.IntentDataError {
            return .result(dialog: IntentDialog(stringLiteral: intentError.errorDescription ?? "Couldn't add expense."))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't add expense. \(error.localizedDescription)"))
        }
    }
}
