import SwiftUI

struct RestartRequiredView: View {
    let title: LocalizedStringResource
    let message: String
    let primaryButtonTitle: String
    let onPrimary: () -> Void

    let secondaryButtonTitle: LocalizedStringResource?
    let onSecondary: (() -> Void)?

    init(
        title: LocalizedStringResource,
        message: String,
        primaryButtonTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryButtonTitle: LocalizedStringResource? = nil,
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
                String(localized: title),
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
                        .glassProminentButtonStyleCompat()
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
                        .glassProminentButtonStyleCompat()
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
                    .glassProminentButtonStyleCompat()
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
