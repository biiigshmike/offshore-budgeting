import SwiftUI
import SwiftData

struct UncategorizedExpenseReviewView: View {
    let workspace: Workspace
    let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("general_hideFutureVariableExpenses") private var hideFuture = false
    @Query private var expenses: [VariableExpense]
    @Query private var categories: [Category]
    @State private var selections: [UUID: UUID] = [:]
    @State private var showingSaveError = false

    init(workspace: Workspace, onSave: @escaping () -> Void) {
        self.workspace = workspace
        self.onSave = onSave
        let workspaceID = workspace.id
        _expenses = Query(filter: #Predicate<VariableExpense> {
            $0.workspace?.id == workspaceID && $0.category == nil
        }, sort: [SortDescriptor(\VariableExpense.transactionDate, order: .reverse)])
        _categories = Query(filter: #Predicate<Category> {
            $0.workspace?.id == workspaceID && !$0.isArchived
        }, sort: [SortDescriptor(\Category.name)])
    }

    private var reviewExpenses: [VariableExpense] {
        UncategorizedExpenseReviewService.expenses(in: expenses, workspaceID: workspace.id, hideFuture: hideFuture)
    }

    private var availableCategories: [Category] {
        UncategorizedExpenseReviewService.categories(in: categories, workspaceID: workspace.id)
    }

    private var validSelections: [UUID: UUID] {
        let expenseIDs = Set(reviewExpenses.map(\.id))
        let categoryIDs = Set(availableCategories.map(\.id))
        return selections.filter { expenseIDs.contains($0.key) && categoryIDs.contains($0.value) }
    }

    var body: some View {
        List {
            Section {
                Text("Categorize expenses in \(workspace.name), or leave them for later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if reviewExpenses.isEmpty {
                ContentUnavailableView("No Uncategorized Expenses", systemImage: "checkmark.circle")
            } else if availableCategories.isEmpty {
                ContentUnavailableView("No Available Categories", systemImage: "tag",
                    description: Text("Create a category in Settings to categorize these expenses."))
            } else {
                ForEach(reviewExpenses) { expense in
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(expense.descriptionText).font(.headline)
                            Text(expense.ledgerSignedAmount(), format: CurrencyFormatter.currencyStyle())
                            Text(expense.kind.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(expense.transactionDate, format: .dateTime.month().day().year())
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(expense.card?.name ?? "No Card")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        Picker("Category", selection: categorySelection(for: expense.id)) {
                            Text("Uncategorized").tag(UUID?.none)
                            ForEach(availableCategories) { category in
                                Text(category.name).tag(Optional(category.id))
                            }
                        }
                        .accessibilityLabel("Category for \(expense.descriptionText)")
                        .accessibilityIdentifier("expenseReview.category")
                    }
                }
            }
        }
        .navigationTitle("Review Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Skip", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save).disabled(validSelections.isEmpty)
            }
        }
        .alert("Couldn’t Save Categories", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your selections are still here. Please try saving again.")
        }
    }

    private func categorySelection(for expenseID: UUID) -> Binding<UUID?> {
        Binding(
            get: {
                guard let id = selections[expenseID], availableCategories.contains(where: { $0.id == id }) else { return nil }
                return id
            },
            set: { selections[expenseID] = $0 }
        )
    }

    private func save() {
        do {
            let changed = try UncategorizedExpenseReviewService.save(
                selections: validSelections, workspaceID: workspace.id, context: modelContext
            )
            if changed > 0 { onSave() }
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}
