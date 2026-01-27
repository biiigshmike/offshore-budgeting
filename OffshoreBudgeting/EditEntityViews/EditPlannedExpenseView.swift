//
//  EditPlannedExpenseView.swift
//  OffshoreBudgeting
//
//  Created by Codex on 1/27/26.
//

import SwiftUI
import SwiftData

struct EditPlannedExpenseView: View {

    let workspace: Workspace
    let plannedExpense: PlannedExpense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var title: String = ""
    @State private var plannedAmountText: String = ""
    @State private var actualAmountText: String = ""
    @State private var expenseDate: Date = .now
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(workspace: Workspace, plannedExpense: PlannedExpense) {
        self.workspace = workspace
        self.plannedExpense = plannedExpense

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var canSave: Bool {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return false }

        guard let plannedAmount = PresetFormView.parsePlannedAmount(plannedAmountText),
              plannedAmount > 0
        else { return false }

        if !actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let actual = PresetFormView.parsePlannedAmount(actualAmountText),
                  actual >= 0
            else { return false }
        }

        guard selectedCardID != nil else { return false }
        return true
    }

    var body: some View {
        List {
            Section("Details") {
                TextField("Title", text: $title)

                TextField("Planned Amount", text: $plannedAmountText)
                    .keyboardType(.decimalPad)

                TextField("Actual Amount (optional)", text: $actualAmountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $expenseDate)
                }
            }

            Section("Card") {
                Picker("Card", selection: $selectedCardID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(cards) { card in
                        Text(card.name).tag(UUID?.some(card.id))
                    }
                }
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            }
        }
        .navigationTitle("Edit Planned Expense")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a planned amount greater than 0, and an actual amount that is 0 or greater.")
        }
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a card for this planned expense.")
        }
        .onAppear {
            title = plannedExpense.title
            plannedAmountText = CurrencyFormatter.editingString(from: plannedExpense.plannedAmount)
            actualAmountText = plannedExpense.actualAmount > 0 ? CurrencyFormatter.editingString(from: plannedExpense.actualAmount) : ""
            expenseDate = plannedExpense.expenseDate
            selectedCardID = plannedExpense.card?.id
            selectedCategoryID = plannedExpense.category?.id
        }
    }

    private func save() {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return }

        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let actual: Double
        let actualTrimmed = actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if actualTrimmed.isEmpty {
            actual = 0
        } else {
            guard let parsed = PresetFormView.parsePlannedAmount(actualAmountText), parsed >= 0 else {
                showingInvalidAmountAlert = true
                return
            }
            actual = parsed
        }

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })

        plannedExpense.title = trimmedTitle
        plannedExpense.plannedAmount = planned
        plannedExpense.actualAmount = actual
        plannedExpense.expenseDate = expenseDate
        plannedExpense.workspace = workspace
        plannedExpense.card = selectedCard
        plannedExpense.category = selectedCategory

        try? modelContext.save()
        dismiss()
    }
}

