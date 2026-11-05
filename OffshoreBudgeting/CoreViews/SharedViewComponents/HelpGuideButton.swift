import SwiftUI

struct HelpGuideButton: View {
    @State private var isShowingHelp = false

    var body: some View {
        Button {
            isShowingHelp = true
        } label: {
            Text("Open Help Guide")
                .underline()
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appSheet(isPresented: $isShowingHelp) {
            NavigationStack {
                SettingsHelpView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(
                                String(
                                    localized: "common.done",
                                    defaultValue: "Done",
                                    comment: "Generic action label to finish and close a sheet."
                                )
                            ) {
                                isShowingHelp = false
                            }
                        }
                    }
            }
        }
    }
}
