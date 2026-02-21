//
//  EditCardView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct EditCardView: View {

    let workspace: Workspace
    let card: Card

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var effect: CardEffectOption
    @State private var theme: CardThemeOption

    init(workspace: Workspace, card: Card) {
        self.workspace = workspace
        self.card = card

        _name = State(initialValue: card.name)
        _effect = State(initialValue: CardEffectOption(rawValue: card.effect) ?? .plastic)
        _theme = State(initialValue: CardThemeOption(rawValue: card.theme) ?? .ruby)
    }

    private var canSave: Bool {
        CardFormView.canSave(name: name)
    }

    var body: some View {
        CardFormView(name: $name, effect: $effect, theme: $theme)
            .navigationTitle("Edit Card")
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
            .onAppear {
                guard DebugScreenshotFormDefaults.isEnabled else { return }
                if CardFormView.trimmedName(name).isEmpty {
                    name = DebugScreenshotFormDefaults.cardName
                }
            }
    }

    private func save() {
        card.name = CardFormView.trimmedName(name)
        card.effect = effect.rawValue
        card.theme = theme.rawValue
        dismiss()
    }
}
