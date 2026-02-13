import Foundation
import SwiftData

// MARK: - TransactionEntryService

@MainActor
final class TransactionEntryService {

    // MARK: - ValidationError

    enum ValidationError: LocalizedError {
        case missingDescription
        case invalidAmount
        case missingIncomeSource

        var errorDescription: String? {
            switch self {
            case .missingDescription:
                return "Please provide notes or a description for the expense."
            case .invalidAmount:
                return "Amount must be greater than 0."
            case .missingIncomeSource:
                return "Please provide an income source."
            }
        }
    }

    // MARK: - Expense

    @discardableResult
    func addExpense(
        notes: String,
        amount: Double,
        date: Date,
        workspace: Workspace,
        card: Card,
        category: Category?,
        allocationAccount: AllocationAccount? = nil,
        allocationAmount: Double? = nil,
        modelContext: ModelContext
    ) throws -> VariableExpense {

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNotes.isEmpty else {
            throw ValidationError.missingDescription
        }

        guard amount > 0 else {
            throw ValidationError.invalidAmount
        }

        let expense = VariableExpense(
            descriptionText: trimmedNotes,
            amount: amount,
            transactionDate: date,
            workspace: workspace,
            card: card,
            category: category
        )

        modelContext.insert(expense)

        if let allocationAccount,
           let allocationAmount,
           allocationAmount > 0 {
            let allocation = ExpenseAllocation(
                allocatedAmount: AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: amount),
                createdAt: .now,
                updatedAt: .now,
                workspace: workspace,
                account: allocationAccount,
                expense: expense
            )
            modelContext.insert(allocation)
            expense.allocation = allocation
        }

        try modelContext.save()
        return expense
    }

    // MARK: - Income

    @discardableResult
    func addIncome(
        source: String,
        amount: Double,
        date: Date,
        isPlanned: Bool,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> Income {

        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw ValidationError.missingIncomeSource
        }

        guard amount > 0 else {
            throw ValidationError.invalidAmount
        }

        let normalizedDate = Calendar.current.startOfDay(for: date)
        let income = Income(
            source: trimmedSource,
            amount: amount,
            date: normalizedDate,
            isPlanned: isPlanned,
            isException: false,
            workspace: workspace,
            series: nil,
            card: nil
        )

        modelContext.insert(income)
        try modelContext.save()
        return income
    }
}
