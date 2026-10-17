import AppIntents
import Foundation

// MARK: - IncomeKind

enum IncomeKind: String, AppEnum {
    case planned
    case actual

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Income Kind"

    static var caseDisplayRepresentations: [IncomeKind: DisplayRepresentation] = [
        .planned: "Planned",
        .actual: "Actual"
    ]

    var isPlanned: Bool {
        switch self {
        case .planned: return true
        case .actual: return false
        }
    }
}

// MARK: - AddIncomeIntent

struct AddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Income"
    static var description = IntentDescription("Create a new income entry in your selected Offshore workspace.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Amount",
        requestValueDialog: IntentDialog("What income amount should I log?")
    )
    var amountText: String?

    @Parameter(
        title: "Description",
        requestValueDialog: IntentDialog("What description or source should I use for this income?")
    )
    var source: String?

    @Parameter(
        title: "Date",
        requestValueDialog: IntentDialog("What date should I use for this income?")
    )
    var date: Date?

    @Parameter(
        title: "Type",
        requestValueDialog: IntentDialog("Should this income be planned or actual?")
    )
    var kind: IncomeKind?

    init() {
        self.amountText = nil
        self.source = nil
        self.date = nil
        self.kind = nil
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

        guard let kind else {
            throw $kind.needsValueError("Please choose planned or actual.")
        }

        let trimmedSource = (source ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw $source.needsValueError("Please provide a description or source.")
        }

        guard let date else {
            throw $date.needsValueError("Please provide a date.")
        }

        do {
            let summary = try await MainActor.run {
                let dataStore = OffshoreIntentDataStore.shared
                let service = TransactionEntryService()

                return try dataStore.performWrite { modelContext, workspace in
                    _ = try service.addIncome(
                        source: trimmedSource,
                        amount: parsedAmount,
                        date: date,
                        isPlanned: kind.isPlanned,
                        workspace: workspace,
                        modelContext: modelContext
                    )

                    let amountString = CurrencyFormatter.string(from: parsedAmount)
                    let label = kind.isPlanned ? "planned" : "actual"
                    return "Logged \(amountString) income from \(trimmedSource) as \(label)."
                }
            }

            return .result(dialog: IntentDialog(stringLiteral: summary))
        } catch let validation as TransactionEntryService.ValidationError {
            return .result(dialog: IntentDialog(stringLiteral: validation.errorDescription ?? "Couldn't add income."))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "Couldn't add income. \(error.localizedDescription)"))
        }
    }
}
