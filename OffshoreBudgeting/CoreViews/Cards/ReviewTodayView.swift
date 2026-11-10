import SwiftData
import SwiftUI

struct ReviewTodayView: View {
    let workspace: Workspace

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var result: Result<ReviewTodayActivity, any Error>?
    @State private var editingEntry: ReviewTodayActivity.Entry?

    @State private var breakdown: Breakdown = .category
    @State private var expandedCardID: ReviewTodayActivity.CardTotal.ID?

    private enum Breakdown: Hashable {
        case category
        case card
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
            TotalSpentStatementRow(total: review.spent, heatMapStops: [
                .init(color: color, location: 0), .init(color: color, location: 1)
            ])
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("reviewToday.spent")
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Label(workspace.name, systemImage: "person.fill")
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
