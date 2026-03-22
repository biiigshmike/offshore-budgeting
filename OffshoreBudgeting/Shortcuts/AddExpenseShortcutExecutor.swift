import Foundation
import SwiftData

// MARK: - AddExpenseShortcutExecutor

@MainActor
enum AddExpenseShortcutExecutor {

    struct Request {
        let amountText: String?
        let offshoreCardID: String?
        let walletCardName: String?
        let categoryID: String?
        let merchant: String?
        let date: Date?
    }

    enum RequestValidationError: LocalizedError, Equatable {
        case invalidAmount
        case missingCard
        case missingMerchant
        case missingDate

        var errorDescription: String? {
            switch self {
            case .invalidAmount:
                return "Please provide a valid amount."
            case .missingCard:
                return "Please choose an Offshore card or provide the Wallet card name."
            case .missingMerchant:
                return "Please provide a merchant or description for the expense."
            case .missingDate:
                return "Please provide a date."
            }
        }
    }

    static func executeInSelectedWorkspace(
        request: Request
    ) throws -> String {
        let dataStore = OffshoreIntentDataStore.shared
        let transactionService = TransactionEntryService()
        return try dataStore.performWrite { modelContext, workspace in
            try execute(
                request: request,
                in: workspace,
                modelContext: modelContext,
                dataStore: dataStore,
                transactionService: transactionService
            )
        }
    }

    static func execute(
        request: Request,
        in workspace: Workspace,
        modelContext: ModelContext
    ) throws -> String {
        try execute(
            request: request,
            in: workspace,
            modelContext: modelContext,
            dataStore: OffshoreIntentDataStore.shared,
            transactionService: TransactionEntryService()
        )
    }

    static func execute(
        request: Request,
        in workspace: Workspace,
        modelContext: ModelContext,
        dataStore: OffshoreIntentDataStore,
        transactionService: TransactionEntryService
    ) throws -> String {
        let trimmedAmount = (request.amountText ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsedAmount = CurrencyFormatter.parseAmount(trimmedAmount) else {
            throw RequestValidationError.invalidAmount
        }

        guard parsedAmount > 0 else {
            throw RequestValidationError.invalidAmount
        }

        let trimmedMerchant = (request.merchant ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMerchant.isEmpty else {
            throw RequestValidationError.missingMerchant
        }

        let trimmedCardID = (request.offshoreCardID ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWalletCardName = (request.walletCardName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !(trimmedCardID.isEmpty && trimmedWalletCardName.isEmpty) else {
            throw RequestValidationError.missingCard
        }

        guard let date = request.date else {
            throw RequestValidationError.missingDate
        }

        let resolvedCard = try dataStore.resolveCard(
            id: trimmedCardID,
            name: trimmedWalletCardName,
            in: workspace,
            modelContext: modelContext
        )
        let resolvedCategory = try dataStore.resolveCategory(
            id: request.categoryID,
            merchant: trimmedMerchant,
            in: workspace,
            modelContext: modelContext
        )

        _ = try transactionService.addExpense(
            notes: trimmedMerchant,
            amount: parsedAmount,
            date: date,
            workspace: workspace,
            card: resolvedCard,
            category: resolvedCategory,
            allocationAccount: nil,
            allocationAmount: nil,
            modelContext: modelContext
        )

        let amountText = CurrencyFormatter.string(from: parsedAmount)
        let categoryName = resolvedCategory?.name ?? "Uncategorized"
        return "Logged \(amountText) to \(resolvedCard.name) in \(categoryName)."
    }
}
