import SwiftData
import SwiftUI

struct ReviewTodayView: View {
    let workspace: Workspace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @Query private var workspacePresets: [Preset]
    @State private var result: Result<ReviewTodayActivity, any Error>?
    @State private var editingEntry: ReviewTodayActivity.Entry?
    @State private var editingPreset: Preset?
    @State private var pendingDelete: ReviewTodayActivity.Entry?
    @State private var showingDeleteConfirm = false

    @State private var breakdown: Breakdown = .category
    @State private var expandedCardID: ReviewTodayActivity.CardTotal.ID?

    private enum Breakdown: Hashable {
        case category
        case card
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _workspacePresets = Query(filter: #Predicate<Preset> { $0.workspace?.id == workspaceID })
    }

    var body: some View {
        NavigationStack {
            summaryContent
                .navigationTitle("Review Today")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .blocksAutomaticExpenseReview(while: showingDeleteConfirm)
                .alert("Delete Expense?", isPresented: $showingDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        if let pendingDelete {
                            delete(pendingDelete)
                        }
                        pendingDelete = nil
                    }
                    Button("Cancel", role: .cancel) {
                        pendingDelete = nil
                    }
                }
                .appSheet(item: $editingEntry, onDismiss: reload) { entry in
                    NavigationStack {
                        switch entry {
                        case .variable(let expense):
                            EditExpenseView(workspace: workspace, expense: expense)
                        case .planned(let expense):
                            EditPlannedExpenseView(workspace: workspace, plannedExpense: expense)
                        }
                    }
                }
                .appSheet(item: $editingPreset, onDismiss: reload) { preset in
                    NavigationStack {
                        EditPresetView(workspace: workspace, preset: preset)
                    }
                }
        }
        .task(id: workspace.id) { reload() }
    }

    @ViewBuilder
    private var summaryContent: some View {
        switch result {
        case .none:
            ProgressView()
        case .failure:
            ContentUnavailableView {
                Label("Couldn’t Load Today’s Spending", systemImage: "exclamationmark.circle")
            } actions: {
                Button("Try Again", action: reload)
            }
        case .success(let review):
            reviewList(review)
        }
    }

    private func reviewList(_ review: ReviewTodayActivity) -> some View {
        List {
            statement(review)
            if review.isEmpty {
                ContentUnavailableView(
                    "No Expenses Today",
                    systemImage: "list.bullet.clipboard",
                    description: Text("There are no transactions or planned expenses for today in this workspace.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            }
            if !review.entries.isEmpty {
                Section("Today’s Activity") {
                    ForEach(review.entries, content: expenseRow)
                }
            }
            if !review.stillPlanned.isEmpty {
                Section("Still Planned") {
                    ForEach(review.stillPlanned) { expense in
                        expenseRow(.planned(expense))
                    }
                }
            }
            if !review.categories.isEmpty {
                Section("Spending Breakdown") {
                    Picker("Spending Breakdown", selection: $breakdown) {
                        Text("By Category").tag(Breakdown.category)
                        Text("By Card").tag(Breakdown.card)
                    }
                    .pickerStyle(.segmented)

                    switch breakdown {
                    case .category:
                        ForEach(review.categories, content: categoryRow)
                    case .card:
                        ForEach(review.cards, content: cardRow)
                    }
                }
            }
        }
    }

    private func categoryRow(_ category: ReviewTodayActivity.CategoryTotal) -> some View {
        CategoryMetricRowView(
            name: category.name,
            color: category.colorHex.flatMap { Color(hex: $0) } ?? .secondary,
            amountText: CurrencyFormatter.string(from: category.amount),
            percentValue: 0,
            showsProgressBar: false,
            showsPercentage: false
        )
    }

    private func cardRow(_ card: ReviewTodayActivity.CardTotal) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedCardID == card.id },
            set: { expanded in
                if expanded {
                    expandedCardID = card.id
                } else if expandedCardID == card.id {
                    expandedCardID = nil
                }
            }
        )) {
            ForEach(card.categories, content: categoryRow)
        } label: {
            LabeledContent {
                Text(card.amount, format: CurrencyFormatter.currencyStyle())
            } label: {
                Text(card.name)
            }
        }
    }

    private func statement(_ review: ReviewTodayActivity) -> some View {
        let color = Color(hex: workspace.hexColor) ?? .secondary
        return Section {
            TotalSpentStatementRow(total: review.spent, heatMapStops: gradientStops(for: review))
                .listRowInsets(EdgeInsets())
                .accessibilityIdentifier("reviewToday.spent")
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(workspace.name)
                } icon: {
                    Image(systemName: "person.fill")
                        .foregroundStyle(color)
                }
                .accessibilityLabel("Workspace: \(workspace.name)")
                Text(review.day, format: .dateTime.weekday(.wide).month(.wide).day())
                Text("Spent Today")
                    .fontWeight(.semibold)
                    .accessibilityAddTraits(.isHeader)
            }
            .textCase(nil)
        } footer: {
            if review.refunded > 0 {
                Text("Refunded today: \(CurrencyFormatter.string(from: review.refunded))")
            }
        }
    }

    private func expenseRow(_ entry: ReviewTodayActivity.Entry) -> some View {
        Button {
            editingEntry = entry
        } label: {
            switch entry {
            case .variable(let expense):
                SharedVariableExpenseRow(expense: expense, showsCardName: true)
            case .planned(let expense):
                SharedPlannedExpenseRow(expense: expense, showsCardName: true)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: allowsFullSwipeEdit(entry)) {
            if case .planned(let expense) = entry {
                RecordPlannedExpenseButton(expense: expense, onRecorded: reload)
            }

            Button {
                editingEntry = entry
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color("AccentColor"))

            if case .planned(let expense) = entry,
               let presetID = expense.sourcePresetID,
               let preset = workspacePresets.first(where: { $0.id == presetID }) {
                Button {
                    editingPreset = preset
                } label: {
                    Label("Edit Preset", systemImage: "list.bullet.rectangle")
                }
                .tint(Color("OffshoreSand"))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                if confirmBeforeDeleting {
                    pendingDelete = entry
                    showingDeleteConfirm = true
                } else {
                    delete(entry)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color("OffshoreDepth"))
        }
    }

    private func allowsFullSwipeEdit(_ entry: ReviewTodayActivity.Entry) -> Bool {
        if case .variable = entry { return true }
        return false
    }

    private func gradientStops(for review: ReviewTodayActivity) -> [Gradient.Stop] {
        let categories = review.categories.filter { $0.id != nil && $0.amount > 0 }.prefix(10)
        let total = categories.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        var cursor = 0.0
        var stops: [Gradient.Stop] = []
        for (index, category) in categories.enumerated() {
            let color = category.colorHex.flatMap { Color(hex: $0) } ?? Color.secondary.opacity(0.35)
            let end = index == categories.count - 1 ? 1.0 : min(1.0, cursor + category.amount / total)
            stops.append(.init(color: color, location: cursor))
            stops.append(.init(color: color, location: end))
            cursor = end
        }
        return stops
    }

    private func delete(_ entry: ReviewTodayActivity.Entry) {
        switch entry {
        case .variable(let expense):
            VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
        case .planned(let expense):
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }
        reload()
    }

    private func reload() {
        result = Result {
            let expenses = try ReviewTodayExpenses.load(workspaceID: workspace.id, in: modelContext)
            let review = ReviewTodayActivity(expenses: expenses)
            if let expandedCardID, !review.cards.contains(where: { $0.id == expandedCardID }) {
                self.expandedCardID = nil
            }
            return review
        }
    }
}
