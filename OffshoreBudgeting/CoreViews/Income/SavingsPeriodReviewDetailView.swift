import SwiftData
import SwiftUI

struct SavingsPeriodReviewDetailView: View {
    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @Query private var workspacePresets: [Preset]
    @State private var editingPreset: Preset?
    @State private var pendingDeletion: ((ModelContext) throws -> Void)?
    @State private var showingDeleteConfirm = false
    @State private var showingPlannedExpenseRecordingError = false
    @State private var summary: SavingsPeriodReviewSummary
    @State private var acknowledged = false
    @State private var usesCorrectedAmount: Bool
    @State private var correctedAmount: Double
    @State private var explanation: String
    @State private var editingIncome: Income?
    @State private var editingPlannedExpense: PlannedExpense?
    @State private var editingVariableExpense: VariableExpense?
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var previewAvailable = true

    init(workspace: Workspace, summary: SavingsPeriodReviewSummary) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _workspacePresets = Query(filter: #Predicate<Preset> { $0.workspace?.id == workspaceID })
        _summary = State(initialValue: summary)
        _usesCorrectedAmount = State(initialValue: summary.existingEntry?.correctedCloseAmount != nil)
        _correctedAmount = State(initialValue: summary.existingEntry?.correctedCloseAmount ?? summary.calculatedAmount)
        _explanation = State(initialValue: summary.existingEntry?.correctionExplanation ?? "")
    }

    private var proposedAmount: Double {
        usesCorrectedAmount ? correctedAmount : summary.calculatedAmount
    }

    private var changeToSavings: Double { proposedAmount - summary.postedAmount }

    private var canConfirm: Bool {
        previewAvailable && acknowledged && !summary.hasOverlapConflict && proposedAmount.isFinite
    }

    var body: some View {
        List {
            overviewSection
            budgetsSection
            incomeSection
            plannedExpensesSection
            variableExpensesSection
            correctionSection
            confirmationSection
        }
        .navigationTitle("Review Period")
        .accessibilityIdentifier("savings.periodReview.detail")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(action: confirm) {
                    if summary.isPending {
                        Text("Save")
                    } else {
                        Text("Update")
                    }
                }
                .tint(.accentColor)
                .glassProminentButtonStyleCompat()
                .disabled(!canConfirm)
                .accessibilityIdentifier("savings.periodReview.confirm")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: usesCorrectedAmount) { _, _ in acknowledged = false }
        .onChange(of: correctedAmount) { _, _ in acknowledged = false }
        .onChange(of: explanation) { _, _ in acknowledged = false }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in reload() }
        .appSheet(item: $editingIncome, onDismiss: reload) { income in
            NavigationStack { EditIncomeView(workspace: workspace, income: income) }
        }
        .appSheet(item: $editingPlannedExpense, onDismiss: reload) { expense in
            NavigationStack { EditPlannedExpenseView(workspace: workspace, plannedExpense: expense) }
        }
        .appSheet(item: $editingVariableExpense, onDismiss: reload) { expense in
            NavigationStack { EditExpenseView(workspace: workspace, expense: expense) }
        }
        .appSheet(item: $editingPreset, onDismiss: reload) { preset in
            NavigationStack { EditPresetView(workspace: workspace, preset: preset) }
        }
        .plannedExpenseRecordingAlert(isPresented: $showingPlannedExpenseRecordingError)
        .blocksAutomaticExpenseReview(while: showingError || showingDeleteConfirm)
        .alert("Delete Entry?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { deleteEntry(using: pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the entry from this workspace.")
        }
        .alert("Couldn’t Save Changes", isPresented: $showingError) { } message: {
            Text(errorMessage)
        }
    }

    private var overviewSection: some View {
        Section {
            moneyRow("Received Income", amount: summary.receivedIncome)
            moneyRow("Planned Expense Impact", amount: -summary.plannedImpact)
            moneyRow("Variable Expense Impact", amount: -summary.variableImpact)
            moneyRow("Calculated Savings", amount: summary.calculatedAmount)
                .fontWeight(.semibold)
            if let entry = summary.existingEntry {
                moneyRow("Already Posted", amount: summary.postedAmount)
                if let reviewedAt = entry.reviewedAt {
                    LabeledContent("Last Confirmed") {
                        Text(reviewedAt, format: .dateTime.month().day().year())
                    }
                }
                if summary.needsReview {
                    Label("Some details changed since your last review. Take another look before updating Savings.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }
            if summary.hasOverlapConflict {
                Label("Some of these dates are already included in Savings. Check the other period first so nothing gets counted twice.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("\(AppDateFormat.abbreviatedDate(summary.start)) – \(AppDateFormat.abbreviatedDate(summary.end))")
                .textCase(nil)
        } footer: {
            Text("These totals include this workspace’s income and expenses for these dates. Budgets are here to help you check the details.")
        }
    }

    private var budgetsSection: some View {
        Section("Budgets to Check") {
            if summary.budgets.isEmpty {
                Text("No budgets overlap this period.").foregroundStyle(.secondary)
            } else {
                ForEach(summary.budgets) { budget in
                    NavigationLink {
                        BudgetDetailView(workspace: workspace, budget: budget)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(budget.name)
                            Text("\(AppDateFormat.abbreviatedDate(budget.startDate)) – \(AppDateFormat.abbreviatedDate(budget.endDate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var incomeSection: some View {
        Section {
            if summary.incomes.isEmpty {
                Text("No income in this period.").foregroundStyle(.secondary)
            } else {
                ForEach(summary.incomes) { income in
                    Button { editingIncome = income } label: {
                        LabeledContent {
                            Text(income.amount, format: CurrencyFormatter.currencyStyle())
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(income.source)
                                Text(income.isPlanned ? "Still Planned · Not Counted" : "Received")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(income.date, format: .dateTime.month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .rowActions {
                        Button {
                            editingIncome = income
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                            .tint(Color("AccentColor"))
                    } trailing: {
                        Button(role: .destructive) {
                            requestDeleteIncome(income)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Color("OffshoreDepth"))
                    }
                }
            }
        } header: {
            Text("Income")
        } footer: {
            Text("Tap to edit. Press and hold for all row actions, or swipe to reveal them.")
        }
    }

    private var plannedExpensesSection: some View {
        Section {
            if summary.plannedExpenses.isEmpty {
                Text("No planned expenses in this period.").foregroundStyle(.secondary)
            } else {
                if summary.plannedExpenses.contains(where: { $0.actualAmount <= 0 }) {
                    Label("Some expenses are still using their planned amounts. You can update them below.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.plannedExpenses) { expense in
                    Button { editingPlannedExpense = expense } label: {
                        SharedPlannedExpenseRow(expense: expense, showsCardName: true)
                    }
                    .buttonStyle(.plain)
                    .rowActions(allowsFullLeadingSwipe: false) {
                        if PlannedExpenseRecordingService.canRecord(expense) {
                            RecordPlannedExpenseButton(
                                expense: expense,
                                showingSaveError: $showingPlannedExpenseRecordingError,
                                onRecorded: reload
                            )
                        }
                        Button {
                            editingPlannedExpense = expense
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                            .tint(Color("AccentColor"))
                        if let presetID = expense.sourcePresetID,
                           let preset = workspacePresets.first(where: { $0.id == presetID }) {
                            Button {
                                editingPreset = preset
                            } label: {
                                Label("Edit Preset", systemImage: "list.bullet.rectangle")
                            }
                                .tint(Color("OffshoreSand"))
                        }
                    } trailing: {
                        Button(role: .destructive) {
                            requestDeletePlannedExpense(expense)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Color("OffshoreDepth"))
                    }
                }
            }
        } header: {
            Text("Planned Expenses")
        } footer: {
            Text("Tap to edit. Press and hold for all row actions, or swipe to reveal them. Splits and payments from Savings are already included in the totals above.")
        }
    }

    private var variableExpensesSection: some View {
        Section {
            if summary.variableExpenses.isEmpty {
                Text("No variable expenses in this period.").foregroundStyle(.secondary)
            } else {
                ForEach(summary.variableExpenses) { expense in
                    Button { editingVariableExpense = expense } label: {
                        SharedVariableExpenseRow(expense: expense, showsCardName: true)
                    }
                    .buttonStyle(.plain)
                    .rowActions {
                        Button {
                            editingVariableExpense = expense
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                            .tint(Color("AccentColor"))
                    } trailing: {
                        Button(role: .destructive) {
                            requestDeleteVariableExpense(expense)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(Color("OffshoreDepth"))
                    }
                }
            }
        } header: {
            Text("Variable Expenses")
        } footer: {
            Text("Tap to edit. Press and hold for all row actions, or swipe to reveal them.")
        }
    }

    private var correctionSection: some View {
        Section {
            Toggle("Use a Different Amount", isOn: $usesCorrectedAmount)
                .tint(Color("AccentColor"))
                .accessibilityIdentifier("savings.periodReview.useCorrection")
            if usesCorrectedAmount {
                TextField("Amount", value: $correctedAmount, format: CurrencyFormatter.currencyStyle())
                    .keyboardType(.numbersAndPunctuation)
                    .accessibilityIdentifier("savings.periodReview.correctedAmount")
                TextField("Note (optional)", text: $explanation, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("savings.periodReview.correctionReason")
            }
        } header: {
            Text("Closing Amount")
        } footer: {
            Text("If the records don’t tell the whole story, use the amount you want to add to Savings. Zero and negative amounts are fine. Leave the note blank to use the usual period-close text.")
        }
    }

    private var confirmationSection: some View {
        Section {
            moneyRow("Proposed Closing Amount", amount: proposedAmount)
            moneyRow("Already Posted", amount: summary.postedAmount)
            moneyRow("Change to Savings", amount: changeToSavings)
            moneyRow("Savings After Confirmation", amount: summary.currentTotal + changeToSavings)
                .fontWeight(.semibold)
            Toggle("Update Savings", isOn: $acknowledged)
                .tint(Color("AccentColor"))
                .accessibilityIdentifier("savings.periodReview.acknowledged")
            if !previewAvailable {
                Button("Reload Period", systemImage: "arrow.clockwise", action: reload)
            }
        } header: {
            Text("Confirm Period")
        } footer: {
            Text("Ready? Turn on Update Savings, then save with the button at the top.")
        }
    }

    private func moneyRow(_ title: LocalizedStringKey, amount: Double) -> some View {
        LabeledContent {
            Text(amount == 0 ? 0 : amount, format: CurrencyFormatter.currencyStyle())
        } label: {
            Text(title)
        }
    }

    private func requestDeleteIncome(_ income: Income) {
        let id = income.id
        let workspaceID = workspace.id
        requestDelete { context in
            let descriptor = FetchDescriptor<Income>(predicate: #Predicate { $0.id == id && $0.workspace?.id == workspaceID })
            if let entry = try context.fetch(descriptor).first { context.delete(entry) }
        }
    }

    private func requestDeletePlannedExpense(_ expense: PlannedExpense) {
        let id = expense.id
        let workspaceID = workspace.id
        requestDelete { context in
            let descriptor = FetchDescriptor<PlannedExpense>(predicate: #Predicate { $0.id == id && $0.workspace?.id == workspaceID })
            if let entry = try context.fetch(descriptor).first {
                PlannedExpenseDeletionService.delete(entry, modelContext: context)
            }
        }
    }

    private func requestDeleteVariableExpense(_ expense: VariableExpense) {
        let id = expense.id
        let workspaceID = workspace.id
        requestDelete { context in
            let descriptor = FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.id == id && $0.workspace?.id == workspaceID })
            if let entry = try context.fetch(descriptor).first {
                VariableExpenseDeletionService.delete(entry, modelContext: context)
            }
        }
    }

    private func requestDelete(_ action: @escaping (ModelContext) throws -> Void) {
        if confirmBeforeDeleting {
            pendingDeletion = action
            showingDeleteConfirm = true
        } else {
            deleteEntry(using: action)
        }
    }

    private func deleteEntry(using action: (ModelContext) throws -> Void) {
        acknowledged = false
        do {
            // A failed save must not leave a pending deletion in the shared editing context.
            let writeContext = ModelContext(modelContext.container)
            writeContext.autosaveEnabled = false
            try action(writeContext)
            let workspaceID = workspace.id
            let accounts = try writeContext.fetch(FetchDescriptor<SavingsAccount>(
                predicate: #Predicate { $0.workspace?.id == workspaceID }
            ))
            for account in accounts { SavingsAccountService.recalculateAccountTotal(account) }
            try writeContext.save()
            reload()
        } catch {
            errorMessage = error.localizedDescription
            showingError = true
        }
    }

    private func confirm() {
        do {
            try SavingsPeriodReviewService.confirm(
                summary,
                workspaceID: workspace.id,
                defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
                correctedAmount: usesCorrectedAmount ? correctedAmount : nil,
                explanation: explanation,
                acknowledged: acknowledged,
                modelContext: modelContext
            )
            dismiss()
        } catch {
            let confirmationError = error.localizedDescription
            reload()
            errorMessage = confirmationError
            showingError = true
        }
    }

    private func reload() {
        acknowledged = false
        do {
            let periods = try SavingsPeriodReviewService.summaries(
                workspaceID: workspace.id,
                defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
                modelContext: modelContext
            )
            guard let refreshed = periods.first(where: { $0.id == summary.id }) else {
                previewAvailable = false
                errorMessage = String(localized: "This period is no longer here. Head back to Period Review to see the latest list.")
                showingError = true
                return
            }
            summary = refreshed
            previewAvailable = true
        } catch {
            previewAvailable = false
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
