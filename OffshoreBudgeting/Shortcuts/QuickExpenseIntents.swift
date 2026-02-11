import AppIntents
import Foundation

// MARK: - QuickExpenseTemplate

enum QuickExpenseTemplate {
    case coffee
    case gas
    case groceries

    var defaultNotes: String {
        switch self {
        case .coffee: return "Coffee"
        case .gas: return "Gas"
        case .groceries: return "Groceries"
        }
    }

    var displayTitle: String {
        switch self {
        case .coffee: return "Coffee"
        case .gas: return "Gas"
        case .groceries: return "Groceries"
        }
    }
}

// MARK: - Quick Expense Base

private struct QuickExpenseExecutor {
    static func run(
        template: QuickExpenseTemplate,
        amount: Double,
        card: OffshoreCardEntity,
        category: OffshoreCategoryEntity?,
        date: Date,
        extraNotes: String
    ) throws -> String {
        let dataStore = OffshoreIntentDataStore.shared
        let service = TransactionEntryService()

        return try dataStore.performWrite { modelContext, workspace in
            let resolvedCard = try dataStore.resolveCard(id: card.id, in: workspace, modelContext: modelContext)
            let resolvedCategory = try dataStore.resolveCategory(id: category?.id, in: workspace, modelContext: modelContext)

            let trimmedExtra = extraNotes.trimmingCharacters(in: .whitespacesAndNewlines)
            let combinedNotes: String
            if trimmedExtra.isEmpty {
                combinedNotes = template.defaultNotes
            } else {
                combinedNotes = "\(template.defaultNotes) - \(trimmedExtra)"
            }

            _ = try service.addExpense(
                notes: combinedNotes,
                amount: amount,
                date: date,
                workspace: workspace,
                card: resolvedCard,
                category: resolvedCategory,
                modelContext: modelContext
            )

            let amountText = CurrencyFormatter.string(from: amount)
            return "Logged \(template.displayTitle.lowercased()) expense of \(amountText) to \(resolvedCard.name)."
        }
    }
}

// MARK: - LogCoffeeIntent

struct LogCoffeeIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Coffee"
    static var description = IntentDescription("Quickly log a coffee expense.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Card")
    var card: OffshoreCardEntity

    @Parameter(title: "Category")
    var category: OffshoreCategoryEntity?

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Notes")
    var notes: String

    init() {
        self.amount = 0
        self.card = OffshoreCardEntity(id: "", name: "")
        self.category = nil
        self.date = .now
        self.notes = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await MainActor.run {
            try QuickExpenseExecutor.run(
                template: .coffee,
                amount: amount,
                card: card,
                category: category,
                date: date,
                extraNotes: notes
            )
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - LogGasIntent

struct LogGasIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Gas"
    static var description = IntentDescription("Quickly log a gas expense.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Card")
    var card: OffshoreCardEntity

    @Parameter(title: "Category")
    var category: OffshoreCategoryEntity?

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Notes")
    var notes: String

    init() {
        self.amount = 0
        self.card = OffshoreCardEntity(id: "", name: "")
        self.category = nil
        self.date = .now
        self.notes = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await MainActor.run {
            try QuickExpenseExecutor.run(
                template: .gas,
                amount: amount,
                card: card,
                category: category,
                date: date,
                extraNotes: notes
            )
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}

// MARK: - LogGroceriesIntent

struct LogGroceriesIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Groceries"
    static var description = IntentDescription("Quickly log a groceries expense.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Amount")
    var amount: Double

    @Parameter(title: "Card")
    var card: OffshoreCardEntity

    @Parameter(title: "Category")
    var category: OffshoreCategoryEntity?

    @Parameter(title: "Date")
    var date: Date

    @Parameter(title: "Notes")
    var notes: String

    init() {
        self.amount = 0
        self.card = OffshoreCardEntity(id: "", name: "")
        self.category = nil
        self.date = .now
        self.notes = ""
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try await MainActor.run {
            try QuickExpenseExecutor.run(
                template: .groceries,
                amount: amount,
                card: card,
                category: category,
                date: date,
                extraNotes: notes
            )
        }
        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
