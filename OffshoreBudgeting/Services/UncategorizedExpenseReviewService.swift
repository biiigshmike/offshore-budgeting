import Foundation
import SwiftData

@MainActor
enum UncategorizedExpenseReviewService {
    static func expenses(
        in expenses: [VariableExpense], workspaceID: UUID, hideFuture: Bool,
        now: Date = .now, calendar: Calendar = .current
    ) -> [VariableExpense] {
        VariableExpenseFuturePolicy.filteredForVisibility(
            expenses.filter { $0.workspace?.id == workspaceID && $0.category == nil && !$0.isDeleted },
            hideFuture: hideFuture, now: now, calendar: calendar
        ).sorted {
            if $0.transactionDate != $1.transactionDate { return $0.transactionDate > $1.transactionDate }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func categories(in categories: [Category], workspaceID: UUID) -> [Category] {
        CategoryArchivePolicy.activeCategories(from: categories).filter {
            $0.workspace?.id == workspaceID && !$0.isDeleted
        }
    }

    /// Re-fetch before applying staged IDs. Restore only our category edits on
    /// failure, without rolling back unrelated edits in the shared main context.
    @discardableResult
    static func save(
        selections: [UUID: UUID], workspaceID: UUID, context: ModelContext,
        persist: (() throws -> Void)? = nil
    ) throws -> Int {
        let expenses = try context.fetch(FetchDescriptor<VariableExpense>(
            predicate: #Predicate { $0.workspace?.id == workspaceID && $0.category == nil }
        ))
        let categories = try context.fetch(FetchDescriptor<Category>(
            predicate: #Predicate { $0.workspace?.id == workspaceID && !$0.isArchived }
        ))
        let available = Dictionary(uniqueKeysWithValues: self.categories(in: categories, workspaceID: workspaceID).map { ($0.id, $0) })
        var changed: [VariableExpense] = []
        for expense in expenses where !expense.isDeleted && expense.workspace?.id == workspaceID && expense.category == nil {
            guard let categoryID = selections[expense.id], let category = available[categoryID] else { continue }
            expense.category = category
            changed.append(expense)
        }
        guard !changed.isEmpty else { return 0 }
        do {
            if let persist { try persist() } else { try context.save() }
            return changed.count
        } catch {
            for expense in changed { expense.category = nil }
            throw error
        }
    }
}
