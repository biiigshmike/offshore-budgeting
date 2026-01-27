import SwiftUI

struct RestartRequiredView: View {
    let title: String
    let message: String
    let primaryButtonTitle: String
    let onPrimary: () -> Void

    let secondaryButtonTitle: String
    let onSecondary: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            ContentUnavailableView(
                title,
                systemImage: "arrow.clockwise.circle",
                description: Text(message)
            )
            .padding(.horizontal, 18)

            HStack(spacing: 12) {
                Button {
                    onSecondary()
                } label: {
                    Text(secondaryButtonTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.gray)

                Button {
                    onPrimary()
                } label: {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.blue)
            }
            .padding(.horizontal, 18)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
    }
}
