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
        title: "Date",
        requestValueDialog: IntentDialog("What date should I use for this expense?")
    )
    var date: Date?

    @Parameter(
        title: "Notes",
        requestValueDialog: IntentDialog("What should I use for notes or description?")
    )
    var notes: String?

    init() {
        self.amountText = nil
        self.card = nil
        self.category = nil
        self.date = nil
        self.notes = nil
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

        guard let card else {
            throw $card.needsValueError("Please choose a card.")
        }

        if card.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw $card.needsValueError("Please choose a card.")
        }

        guard let category else {
            throw $category.needsValueError("Please choose a category.")
        }

        if category.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw $category.needsValueError("Please choose a valid category.")
        }

        let trimmedNotes = (notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedNotes.isEmpty {
            throw $notes.needsValueError("Please provide notes or a description for the expense.")
        }

        guard let date else {
            throw $date.needsValueError("Please provide a date.")
        }

        do {
            let addedSummary = try await MainActor.run {
                let dataStore = OffshoreIntentDataStore.shared
                let service = TransactionEntryService()

                return try dataStore.performWrite { modelContext, workspace in
                    let resolvedCard = try dataStore.resolveCard(id: card.id, in: workspace, modelContext: modelContext)
                    let resolvedCategory = try dataStore.resolveCategory(id: category.id, in: workspace, modelContext: modelContext)
                    guard let resolvedCategory else {
                        throw OffshoreIntentDataStore.IntentDataError.categoryUnavailable
                    }

                    _ = try service.addExpense(
                        notes: trimmedNotes,
                        amount: parsedAmount,
                        date: date,
                        workspace: workspace,
                        card: resolvedCard,
                        category: resolvedCategory,
                        modelContext: modelContext
                    )

                    let amountText = CurrencyFormatter.string(from: parsedAmount)
                    return "Logged \(amountText) to \(resolvedCard.name) in \(resolvedCategory.name)."
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
