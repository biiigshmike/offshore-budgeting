import SwiftUI

struct SettingsSupportFeedbackSection: View {
    @Environment(\.openURL) private var openURL
    @State private var fallbackDraft: SupportFeedbackDraft?

    var body: some View {
        Section {
            NavigationLink {
                SettingsTipJarView()
            } label: {
                Label("Tip Jar", systemImage: "heart")
            }

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
        .appSheet(item: $fallbackDraft) { draft in
            FeedbackDraftFallbackView(draft: draft)
        }
    }

    private func compose(_ kind: SupportFeedbackDraft.Kind) {
        let draft = SupportFeedbackDraft(kind: kind)
        guard let url = draft.mailURL else {
            fallbackDraft = draft
            return
        }

        openURL(url) { accepted in
            if !accepted {
                fallbackDraft = draft
            }
        }
    }
}
