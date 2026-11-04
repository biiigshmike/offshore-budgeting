import SwiftUI

struct SettingsThemePreview: View {
    @Environment(\.appearanceTheme) private var theme

    var body: some View {
        Group {
            HStack {
                Text("Toggles")
                Spacer()
                Toggle("On", isOn: .constant(true))
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Links")
                Spacer()
                Label("Learn More", systemImage: "arrow.up.right")
                    .foregroundStyle(theme.accent)
                    .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Text("Icons")
                Spacer()
                HStack(spacing: 12) {
                    Image(systemName: "creditcard.fill")
                    Image(systemName: "calendar")
                }
                .foregroundStyle(theme.accent)
                .accessibilityHidden(true)
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 12) {
                Text("Home Background & Buttons")
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 24)

                ViewThatFits(in: .horizontal) {
                    HStack {
                        primaryButton
                        secondaryButton
                    }
                    VStack(alignment: .leading) {
                        primaryButton
                        secondaryButton
                    }
                }
                .accessibilityHidden(true)
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background {
                HomeBackgroundView(extendsIntoSafeArea: false)
            }
            .listRowInsets(EdgeInsets())
        }
        .tint(theme.accent)
        .allowsHitTesting(false)
    }

    private var primaryButton: some View {
        Button("Primary") {}
            .glassProminentButtonStyleCompat()
    }

    @ViewBuilder
    private var secondaryButton: some View {
        #if targetEnvironment(macCatalyst)
        if #available(macCatalyst 26.0, *) {
            Text("Secondary")
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
        } else {
            Button("Secondary") {}
                .buttonStyle(.bordered)
        }
        #else
        Button("Secondary") {}
            .glassButtonStyleCompat()
        #endif
    }
}
