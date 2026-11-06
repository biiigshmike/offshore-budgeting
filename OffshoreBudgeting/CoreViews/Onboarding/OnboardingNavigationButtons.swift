import SwiftUI

struct OnboardingNavigationButtons: View {
    let primaryTitle: String
    let onBack: () -> Void
    let onAdvance: () -> Void

    var body: some View {
        row { EmptyView() }
    }

    func addingButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        row {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .glassButtonStyleCompat(catalystShape: .circle)
            .buttonBorderShape(.circle)
            .tint(nil)
            .accessibilityLabel(Text(title))
        }
    }

    private func row<Center: View>(@ViewBuilder center: () -> Center) -> some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Text("Back")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassProminentButtonStyleCompat()
            .tint(.gray)

            center()

            Button(action: onAdvance) {
                Text(primaryTitle)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassProminentButtonStyleCompat()
            .tint(.accentColor)
        }
        .padding(.vertical, 14)
    }
}

extension View {
    @ViewBuilder
    func onboardingGlassFooter<Footer: View>(
        legacyMinHeight: CGFloat? = nil,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            safeAreaInset(edge: .bottom, spacing: 0) {
                footer()
                    .onboardingContentPadding()
            }
        } else {
            frame(minHeight: legacyMinHeight)
        }
    }
}
