import SwiftUI

struct OnboardingStepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            descriptionText
        }
    }

    var descriptionText: some View {
        Text(subtitle)
            .foregroundStyle(.secondary)
    }

    var subtitleRow: some View {
        descriptionText
            .fixedSize(horizontal: false, vertical: true)
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 10, trailing: 8))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

extension EnvironmentValues {
    @Entry var onboardingHorizontalContentInset: CGFloat? = nil
}

extension View {
    func onboardingContentPadding() -> some View {
        modifier(OnboardingContentPadding())
    }

    @ViewBuilder
    func onboardingNavigationTitle(_ title: String) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            modifier(OnboardingNavigationTitle(title: title))
        } else {
            self
        }
    }
}

private struct OnboardingContentPadding: ViewModifier {
    @Environment(\.onboardingHorizontalContentInset) private var inset

    func body(content: Content) -> some View {
        content.padding(.horizontal, inset ?? 0)
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
private struct OnboardingNavigationTitle: ViewModifier {
    let title: String
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.onboardingHorizontalContentInset) private var horizontalContentInset

    private var usesCompactTitle: Bool {
        verticalSizeClass == .compact
    }

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(.inline)
        #else
        content
            .contentMargins(.horizontal, horizontalContentInset, for: .scrollContent)
            .contentMargins(.top, 0, for: .scrollContent)
            .navigationTitle(title)
            .toolbarTitleDisplayMode(usesCompactTitle ? .inline : .inlineLarge)
        #endif
    }
}
