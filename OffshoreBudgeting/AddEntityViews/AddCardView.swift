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
    @State private var theme: CardThemeOption = .ruby

    private var canSave: Bool {
        CardFormView.canSave(name: name)
    }

    var body: some View {
        CardFormView(name: $name, effect: $effect, theme: $theme)
            .navigationTitle("Add Card")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }

                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { saveAndAdd() } label: {
                            Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                        }
                        .accessibilityLabel("Save & Add")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .buttonStyle(.plain)
                    }

                    ToolbarSpacer(.flexible, placement: .primaryAction)

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { save() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Save")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button { saveAndAdd() } label: {
                            Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                        }
                        .accessibilityLabel("Save & Add")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .controlSize(.large)
                            .buttonStyle(.plain)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { save() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Save")
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
        guard persistCard() else { return }
        dismiss()
    }

    private func saveAndAdd() {
        guard persistCard() else { return }
        resetForm()
    }

    @discardableResult
    private func persistCard() -> Bool {
        let trimmed = CardFormView.trimmedName(name)
        guard !trimmed.isEmpty else { return false }

        let card = Card(
            name: trimmed,
            theme: theme.rawValue,
            effect: effect.rawValue,
            workspace: workspace
        )

        modelContext.insert(card)
        return true
    }

    private func resetForm() {
        name = ""
        effect = .plastic
        theme = .ruby

        guard DebugScreenshotFormDefaults.isEnabled else { return }
        name = DebugScreenshotFormDefaults.cardName
    }
}
