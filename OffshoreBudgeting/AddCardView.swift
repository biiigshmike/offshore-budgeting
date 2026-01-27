//
//  AddCardView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddCardView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var effect: CardEffectOption = .plastic
    @State private var theme: CardThemeOption = .rose

    private var canSave: Bool {
        CardFormView.canSave(name: name)
    }

    var body: some View {
        CardFormView(name: $name, effect: $effect, theme: $theme)
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            }
    }

    private func save() {
        let trimmed = CardFormView.trimmedName(name)

        let card = Card(
            name: trimmed,
            theme: theme.rawValue,
            effect: effect.rawValue,
            workspace: workspace
        )

        modelContext.insert(card)
        dismiss()
    }
}
