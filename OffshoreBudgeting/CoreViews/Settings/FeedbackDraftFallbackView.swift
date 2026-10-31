import SwiftUI
import UIKit

struct FeedbackDraftFallbackView: View {
    let draft: SupportFeedbackDraft

    @Environment(\.dismiss) private var dismiss
    @State private var message: String
    @State private var didCopy = false

    init(draft: SupportFeedbackDraft) {
        self.draft = draft
        _message = State(initialValue: draft.body)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let recipient = draft.recipient {
                        LabeledContent("Email", value: recipient)
                            .textSelection(.enabled)
                    }
                    Text("Copy this draft and send it using your preferred email app.")
                        .foregroundStyle(.secondary)
                }

                Section("Message") {
                    TextEditor(text: $message)
                        .frame(minHeight: 220)
                        .accessibilityLabel(String(localized: "Feedback message"))
                        .onChange(of: message) { _, _ in
                            didCopy = false
                        }
                }

                Section {
                    Button {
                        let recipientLine = draft.recipient.map { "\(String(localized: "Email")): \($0)\n" } ?? ""
                        UIPasteboard.general.string = "\(recipientLine)\(draft.subject)\n\n\(message)"
                        didCopy = true
                    } label: {
                        Label(
                            didCopy ? String(localized: "Copied") : String(localized: "Copy Draft"),
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                    }

                    Link("Developer Website", destination: SupportFeedbackConfiguration.developerWebsiteURL)
                }
            }
            .navigationTitle(draft.kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
