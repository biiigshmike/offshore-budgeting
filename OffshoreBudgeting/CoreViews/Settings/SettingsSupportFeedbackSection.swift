import SwiftUI
import MessageUI

struct SettingsSupportFeedbackSection: View {
    @Environment(\.openURL) private var openURL
    @State private var composerDraft: SupportFeedbackDraft?
    @State private var fallbackDraft: SupportFeedbackDraft?
    @State private var isShowingSendError = false

    var body: some View {
        Section {
            Button {
                compose(.feedback)
            } label: {
                Label("Send Feedback", systemImage: "bubble.left.and.text.bubble.right")
            }

            Button {
                compose(.problem)
            } label: {
                Label("Report a Problem", systemImage: "exclamationmark.bubble")
            }

            Link(destination: SupportFeedbackConfiguration.reviewURL) {
                Label("Rate Offshore", systemImage: "star")
            }
        } header: {
            Text("Support & Feedback")
        } footer: {
            Text("Feedback drafts include the app version and operating system. Your financial records are not attached.")
        }
        .appSheet(item: $composerDraft) { draft in
            FeedbackMailComposer(draft: draft) { result, error in
                if result == .failed || error != nil {
                    // MessageUI does not expose edited message text. Keep the
                    // native composer open instead of replacing it with a template.
                    isShowingSendError = true
                } else {
                    composerDraft = nil
                }
            }
            .alert("Couldn’t Send Feedback", isPresented: $isShowingSendError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your message is still open. Try again, save the draft, or copy your text before closing it.")
            }
        }
        .appSheet(item: $fallbackDraft) { draft in
            FeedbackDraftFallbackView(draft: draft)
        }
    }

    private func compose(_ kind: SupportFeedbackDraft.Kind) {
        let draft = SupportFeedbackDraft(kind: kind)
        guard draft.recipient != nil else {
            fallbackDraft = draft
            return
        }

        if MFMailComposeViewController.canSendMail() {
            composerDraft = draft
        } else if let url = draft.mailURL {
            openURL(url) { accepted in
                if !accepted {
                    fallbackDraft = draft
                }
            }
        } else {
            fallbackDraft = draft
        }
    }
}
