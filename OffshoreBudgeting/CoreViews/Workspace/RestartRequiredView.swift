import SwiftUI

struct RestartRequiredView: View {
    let title: String
    let message: String
    let primaryButtonTitle: String
    let onPrimary: () -> Void

    let secondaryButtonTitle: String?
    let onSecondary: (() -> Void)?

    init(
        title: String,
        message: String,
        primaryButtonTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryButtonTitle: String? = nil,
        onSecondary: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.primaryButtonTitle = primaryButtonTitle
        self.onPrimary = onPrimary
        self.secondaryButtonTitle = secondaryButtonTitle
        self.onSecondary = onSecondary
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            ContentUnavailableView(
                title,
                systemImage: "arrow.clockwise.circle",
                description: Text(message)
            )
            .padding(.horizontal, 18)

            if let secondaryButtonTitle, let onSecondary {
                HStack(spacing: 12) {
                    if #available(iOS 26.0, *) {
                        Button {
                            onSecondary()
                        } label: {
                            Text(secondaryButtonTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.gray)
                    } else {
                        Button {
                            onSecondary()
                        } label: {
                            Text(secondaryButtonTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.gray)
                    }
                    if #available(iOS 26.0, *) {
                        Button {
                            onPrimary()
                        } label: {
                            Text(primaryButtonTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.accentColor)
                    } else {
                        Button {
                            onPrimary()
                        } label: {
                            Text(primaryButtonTitle)
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                    }
                }
            } else {
                if #available(iOS 26.0, *) {
                    Button {
                        onPrimary()
                    } label: {
                        Text(primaryButtonTitle)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.accentColor)
                } else {
                    Button {
                        onPrimary()
                    } label: {
                        Text(primaryButtonTitle)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
    }
}
