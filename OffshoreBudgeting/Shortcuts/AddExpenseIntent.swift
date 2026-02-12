import AppIntents
import Foundation

// MARK: - AddExpenseIntent

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Create a new expense in your selected Offshore workspace.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        requestValueDialog: IntentDialog("What amount should I log?")
    )
    var amountText: String?

    @Parameter(
        title: "Card",
        requestValueDialog: IntentDialog("Which card should this expense use?")
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
        let parsedAmount = await MainActor.run {
            CurrencyFormatter.parseAmount((amountText ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
        }
        guard let parsedAmount else {
            throw $amountText.needsValueError("Please provide a valid amount.")
        }

        if parsedAmount <= 0 {
            throw $amountText.needsValueError("Amount must be greater than 0.")
        }

        let trimmedMerchant = (merchant ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCardID = (card?.id ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedCardID.isEmpty {
            throw $card.needsValueError("Please choose a card.")
        }

        if trimmedMerchant.isEmpty {
            throw $merchant.needsValueError("Please provide a merchant or description for the expense.")
        }

        guard let date else {
            throw $date.needsValueError("Please provide a date.")
        }

        do {
            let addedSummary = try await MainActor.run {
                let dataStore = OffshoreIntentDataStore.shared
                let service = TransactionEntryService()

                return try dataStore.performWrite { modelContext, workspace in
                    let resolvedCard = try dataStore.resolveCard(id: trimmedCardID, in: workspace, modelContext: modelContext)
                    let resolvedCategory = try dataStore.resolveCategory(
                        id: category?.id,
                        merchant: trimmedMerchant,
                        in: workspace,
                        modelContext: modelContext
                    )

                    _ = try service.addExpense(
                        notes: trimmedMerchant,
                        amount: parsedAmount,
                        date: date,
                        workspace: workspace,
                        card: resolvedCard,
                        category: resolvedCategory,
                        modelContext: modelContext
                    )

                    let amountText = CurrencyFormatter.string(from: parsedAmount)
                    let categoryName = resolvedCategory?.name ?? "Uncategorized"
                    return "Logged \(amountText) to \(resolvedCard.name) in \(categoryName)."
                }
            }

            return .result(dialog: IntentDialog(stringLiteral: addedSummary))
        } catch let validation as TransactionEntryService.ValidationError {
            return .result(dialog: IntentDialog(stringLiteral: validation.errorDescription ?? "Couldn't add expense."))
        } catch let intentError as OffshoreIntentDataStore.IntentDataError {
            return .result(dialog: IntentDialog(stringLiteral: intentError.errorDescription ?? "Couldn't add expense."))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't add expense. \(error.localizedDescription)"))
        }
    }
}
