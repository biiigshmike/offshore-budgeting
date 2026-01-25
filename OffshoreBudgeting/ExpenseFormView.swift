//
//  ExpenseFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

/// Shared form UI for adding and editing a VariableExpense ("Transaction").
///
/// Design goals:
/// - One place for fields + validation UI
/// - Add/Edit views own navigation + save behavior
struct ExpenseFormView: View {

    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]

    @Binding var descriptionText: String
    @Binding var amountText: String
    @Binding var transactionDate: Date
    @Binding var selectedCardID: UUID?
    @Binding var selectedCategoryID: UUID?

    // MARK: - Validation (shared by Add + Edit)

    static func trimmedDescription(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseAmount(_ text: String) -> Double? {
        CurrencyFormatter.parseAmount(text)
    }

    static func canSave(
        descriptionText: String,
        amountText: String,
        selectedCardID: UUID?,
        hasAtLeastOneCard: Bool
    ) -> Bool {
        let d = trimmedDescription(descriptionText)
        guard !d.isEmpty else { return false }
        guard let amt = parseAmount(amountText), amt > 0 else { return false }
        guard hasAtLeastOneCard else { return false }
        guard selectedCardID != nil else { return false }
        return true
    }

    var body: some View {
        let canSave = ExpenseFormView.canSave(
            descriptionText: descriptionText,
            amountText: amountText,
            selectedCardID: selectedCardID,
            hasAtLeastOneCard: !cards.isEmpty
        )

        Form {
            Section("Card") {
                if cards.isEmpty {
                    Text("No cards yet. Create a card first to add transactions.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(cards) { card in
                                CardTile(
                                    title: card.name,
                                    themeRaw: card.theme,
                                    effectRaw: card.effect,
                                    isSelected: selectedCardID == card.id
                                ) {
                                    selectedCardID = card.id
                                }
                                .accessibilityLabel(selectedCardID == card.id ? "\(card.name), selected" : "\(card.name)")
                                .accessibilityHint("Double tap to set as the transaction card.")
                            }
                        }
                        .padding(6)
                    }

                    if selectedCardID == nil {
                        Text("Select a card to continue.")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Transaction") {
                TextField("Description", text: $descriptionText)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $transactionDate)
                }
            }

            Section {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(UUID?.none)

                    ForEach(categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
            } header: {
                Text("Optional")
            } footer: {
                Text("Categories are workspace-scoped. Transactions are owned by the card.")
            }

            if !canSave {
//                Section {
//                    VStack(alignment: .leading, spacing: 6) {
//                        if ExpenseFormView.trimmedDescription(descriptionText).isEmpty {
//                            Text("Enter a description.")
//                        }
//
//                        let amt = ExpenseFormView.parseAmount(amountText) ?? 0
//                        if amt <= 0 {
//                            Text("Enter an amount greater than 0.")
//                        }
//
//                        if cards.isEmpty {
//                            Text("Create a card first.")
//                        } else if selectedCardID == nil {
//                            Text("Select a card.")
//                        }
//                    }
//                    .foregroundStyle(.secondary)
//                }
            }

//            Section {
//                Text("This transaction will be saved inside “\(workspace.name)”.")
//                    .foregroundStyle(.secondary)
//            }
        }
    }
}

// MARK: - Card tile (now uses CardVisualView)

private struct CardTile: View {
    let title: String
    let themeRaw: String
    let effectRaw: String
    let isSelected: Bool
    let onTap: () -> Void

    // Matches your existing layout
    private let tileWidth: CGFloat = 160

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {

                CardVisualView(
                    title: title,
                    theme: themeOption(from: themeRaw),
                    effect: effectOption(from: effectRaw),
                    minHeight: nil,
                    showsShadow: false,
                    titleFont: .headline,
                    titlePadding: 12,
                    titleOpacity: 0.82
                )
                .frame(width: tileWidth)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func themeOption(from raw: String) -> CardThemeOption {
        CardThemeOption(rawValue: raw) ?? .graphite
    }

    private func effectOption(from raw: String) -> CardEffectOption {
        CardEffectOption(rawValue: raw) ?? .plastic
    }
}
