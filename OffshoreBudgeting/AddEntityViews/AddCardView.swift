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
    @State private var saveErrorMessage = ""
    @State private var showingSaveError = false

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
                
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .offshoreAccentTint()
                            .glassProminentButtonStyleCompat()
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .offshoreAccentTint()
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
            .blocksAutomaticExpenseReview(while: showingSaveError)
            .alert("Couldn’t Save Card", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
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
        do {
            try WorkspaceProgressService.saveCompleting([.card], in: workspace) {
                try modelContext.save()
            }
        } catch {
            modelContext.delete(card)
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
            return
        }
        dismiss()
    }
}
