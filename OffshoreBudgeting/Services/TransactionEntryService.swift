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
        case invalidIncomePlan
        case receiptAlreadyRecorded
        case receivedIncomeUnavailable

        var errorDescription: String? {
            switch self {
            case .missingDescription:
                return "Please provide notes or a description for the expense."
            case .invalidAmount:
                return "Amount must be greater than 0."
            case .missingIncomeSource:
                return "Please provide an income source."
            case .invalidIncomePlan:
                return String(localized: "This planned income is no longer available.")
            case .receiptAlreadyRecorded:
                return String(localized: "This planned income already has a recorded receipt.")
            case .receivedIncomeUnavailable:
                return String(localized: "This Actual income is no longer available to link.")
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
        kind: VariableExpenseKind = .debit,
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

        let selectedCategory = category?.isArchived == false ? category : nil

        let expense = VariableExpense(
            descriptionText: trimmedNotes,
            amount: abs(amount),
            kindRaw: kind.rawValue,
            transactionDate: date,
            workspace: workspace,
            card: card,
            category: selectedCategory
        )

        modelContext.insert(expense)

        if let allocationAccount,
           let allocationAmount,
           allocationAmount > 0 {
            let allocation = ExpenseAllocation(
                allocatedAmount: AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: amount),
                preservesGrossAmount: true,
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

    func possibleReceivedIncomeDuplicates(
        source: String,
        amount: Double,
        date: Date,
        workspaceID: UUID,
        modelContext: ModelContext
    ) throws -> [Income] {
        guard let day = Calendar.current.dateInterval(of: .day, for: date) else { return [] }
        let start = day.start
        let end = day.end
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> {
                $0.workspace?.id == workspaceID && !$0.isPlanned && $0.date >= start && $0.date < end
            },
            sortBy: [SortDescriptor(\Income.date, order: .reverse)]
        )
        let normalizedSource = MerchantNormalizer.normalizeKey(source)
        return try modelContext.fetch(descriptor).filter {
            abs($0.amount - amount) < 0.0001 || MerchantNormalizer.normalizeKey($0.source) == normalizedSource
        }
    }

    @discardableResult
    func addIncome(
        source: String,
        amount: Double,
        date: Date,
        isPlanned: Bool,
        workspace: Workspace,
        plannedIncome: Income? = nil,
        modelContext: ModelContext
    ) throws -> Income {

        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty else {
            throw ValidationError.missingIncomeSource
        }

        guard amount > 0 else {
            throw ValidationError.invalidAmount
        }

        if let plannedIncome {
            guard !isPlanned else { throw ValidationError.invalidIncomePlan }
            try validateReceiptPlan(plannedIncome, workspaceID: workspace.id, modelContext: modelContext)
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
            card: nil,
            sourcePlannedIncomeID: plannedIncome?.id
        )

        modelContext.insert(income)
        do {
            try WorkspaceProgressService.saveCompleting([.income], in: workspace) {
                try modelContext.save()
            }
        } catch {
            modelContext.delete(income)
            throw error
        }
        return income
    }

    func linkReceivedIncome(
        _ receipt: Income,
        to plannedIncome: Income,
        workspaceID: UUID,
        modelContext: ModelContext
    ) throws {
        try validateReceiptPlan(plannedIncome, workspaceID: workspaceID, modelContext: modelContext)
        guard !receipt.isPlanned, !receipt.isDeleted, receipt.workspace?.id == workspaceID,
              receipt.sourcePlannedIncomeID == nil else {
            throw ValidationError.receivedIncomeUnavailable
        }
        receipt.sourcePlannedIncomeID = plannedIncome.id
        do {
            try modelContext.save()
        } catch {
            receipt.sourcePlannedIncomeID = nil
            throw error
        }
    }

    private func validateReceiptPlan(_ plan: Income, workspaceID: UUID, modelContext: ModelContext) throws {
        guard plan.isPlanned, !plan.isDeleted, plan.workspace?.id == workspaceID else {
            throw ValidationError.invalidIncomePlan
        }
        let planID = plan.id
        var existing = FetchDescriptor<Income>(predicate: #Predicate {
            $0.workspace?.id == workspaceID && !$0.isPlanned && $0.sourcePlannedIncomeID == planID
        })
        existing.fetchLimit = 1
        guard try modelContext.fetch(existing).isEmpty else {
            throw ValidationError.receiptAlreadyRecorded
        }
    }
}
