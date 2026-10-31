import SwiftUI

/// Opens the existing help book without losing the form or screen underneath it.
struct HelpTopicLink: View {
    let topicID: String
    var title: LocalizedStringKey = "Learn More"
    // Supporting links use footnote; standalone help rows opt into body.
    var font: Font = .footnote

    @State private var isShowingHelp = false

    var body: some View {
        if let topic = GeneratedHelpContent.visibleLeafTopic(for: topicID) {
            Button {
                isShowingHelp = true
            } label: {
                Label(title, systemImage: "questionmark.circle")
                    .frame(minHeight: 44, alignment: .leading)
            }
            .font(font)
            .buttonStyle(.borderless)
            .blocksAutomaticExpenseReview(while: isShowingHelp)
            .appSheet(isPresented: $isShowingHelp) {
                NavigationStack {
                    HelpTopicDetailView(topic: topic)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Close") { isShowingHelp = false }
                            }
                        }
                }
            }
        }
    }
}
