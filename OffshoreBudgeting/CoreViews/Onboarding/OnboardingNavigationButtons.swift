import SwiftUI

struct OnboardingNavigationButtons: View {
    let isFinalStep: Bool
    let onBack: () -> Void
    let onAdvance: () -> Void

    private var primaryTitle: LocalizedStringKey { isFinalStep ? "Done" : "Next" }
    private var primarySymbol: String { isFinalStep ? "checkmark" : "chevron.forward" }

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

    @available(iOS 27.1, *)
    @ToolbarContentBuilder
    fileprivate func toolbarItems(addTitle: LocalizedStringKey?, onAdd: (() -> Void)?) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Back", systemImage: "chevron.backward", action: onBack)
        }
        ToolbarItem(placement: .topBarPinnedTrailing) {
            Button(primaryTitle, systemImage: primarySymbol, action: onAdvance)
        }
        if let addTitle, let onAdd {
            ToolbarItem(placement: .bottomBar) {
                Button(addTitle, systemImage: "plus", action: onAdd)
            }
        }
    }

    @available(iOS 27.1, *)
    fileprivate func sideStack(
        addTitle: LocalizedStringKey?,
        onAdd: (() -> Void)?,
        addSpacing: CGFloat
    ) -> some View {
        VStack(spacing: OnboardingSideControls.buttonSpacing) {
            sideButton("Back", symbol: "chevron.backward", action: onBack)
            sideButton(primaryTitle, symbol: primarySymbol, action: onAdvance)
            if let addTitle, let onAdd {
                sideButton(addTitle, symbol: "plus", action: onAdd)
                    .padding(.top, addSpacing)
            }
        }
    }

    @available(iOS 27.1, *)
    private func sideButton(
        _ title: LocalizedStringKey,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(.primary)
                .frame(width: OnboardingSideControls.buttonSize, height: OnboardingSideControls.buttonSize)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

@available(iOS 27.1, *)
private struct OnboardingSideControls: ViewModifier {
    static let buttonSize: CGFloat = 44
    static let buttonSpacing: CGFloat = 8
    private static let edgePadding: CGFloat = 12

    let buttons: OnboardingNavigationButtons
    let addTitle: LocalizedStringKey?
    let onAdd: (() -> Void)?

    @Environment(\.toolbarVerticalEdge) private var verticalEdge
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var sidePlacement: SidePlacement?

    nonisolated private struct SidePlacement: Equatable, Sendable {
        let top: CGFloat
        let addSpacing: CGFloat
    }

    private var rightEdge: HorizontalEdge {
        layoutDirection == .leftToRight ? .trailing : .leading
    }

    func body(content: Content) -> some View {
        let hasAdd = addTitle != nil && onAdd != nil

        content
            .toolbar {
                if verticalEdge != nil {
                    buttons.toolbarItems(addTitle: addTitle, onAdd: onAdd)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if verticalEdge == nil, sidePlacement == nil {
                    content.onboardingFooter(buttons, addTitle: addTitle, onAdd: onAdd)
                }
            }
            .safeAreaInset(edge: rightEdge, alignment: .top, spacing: 0) {
                if verticalEdge == nil, let sidePlacement {
                    buttons.sideStack(addTitle: addTitle, onAdd: onAdd, addSpacing: sidePlacement.addSpacing)
                        .padding(.horizontal, Self.edgePadding)
                        .padding(.top, sidePlacement.top)
                }
            }
            .onGeometryChange(for: SidePlacement?.self) { proxy in
                Self.placement(in: proxy, hasAdd: hasAdd)
            } action: { placement in
                sidePlacement = placement
            }
    }

    nonisolated private static func placement(in proxy: GeometryProxy, hasAdd: Bool) -> SidePlacement? {
        let divisions = proxy.reservedRegions(kind: .division, options: .includeInactive, layoutDirectionBehavior: .fixed)
        guard !divisions.isEmpty else { return nil }

        let railWidth = buttonSize + 2 * edgePadding
        guard proxy.size.width >= railWidth else { return nil }
        let rail = CGRect(x: proxy.size.width - railWidth, y: 0, width: railWidth, height: proxy.size.height)
        let occlusions = proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed)
        let obstructions = (divisions + occlusions)
            .filter(\.isActive)
            .map { $0.frame.insetBy(dx: -edgePadding, dy: -edgePadding) }
            .filter { $0.intersects(rail) }
            .sorted { $0.minY < $1.minY }

        let navigationHeight = 2 * buttonSize + buttonSpacing
        let bottom = rail.maxY - edgePadding
        var top = edgePadding
        for obstruction in obstructions {
            if top + navigationHeight <= obstruction.minY {
                break
            }
            top = max(top, obstruction.maxY)
        }
        guard top + navigationHeight <= bottom else { return nil }
        guard hasAdd else { return SidePlacement(top: top, addSpacing: 0) }

        // Match the native toolbar: navigation at the top and Add at the bottom.
        var addTop = bottom - buttonSize
        for obstruction in obstructions.reversed() {
            if addTop < obstruction.maxY, addTop + buttonSize > obstruction.minY {
                addTop = obstruction.minY - buttonSize
            }
        }
        let addSpacing = addTop - (top + navigationHeight + buttonSpacing)
        guard addSpacing >= 0 else { return nil }
        return SidePlacement(top: top, addSpacing: addSpacing)
    }
}

extension View {
    @ViewBuilder
    func onboardingControls(
        _ buttons: OnboardingNavigationButtons,
        legacyMinHeight: CGFloat? = nil,
        addTitle: LocalizedStringKey? = nil,
        onAdd: (() -> Void)? = nil
    ) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            #if os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 27.1, *) {
                modifier(OnboardingSideControls(buttons: buttons, addTitle: addTitle, onAdd: onAdd))
            } else {
                safeAreaInset(edge: .bottom, spacing: 0) {
                    onboardingFooter(buttons, addTitle: addTitle, onAdd: onAdd)
                }
            }
            #else
            safeAreaInset(edge: .bottom, spacing: 0) {
                onboardingFooter(buttons, addTitle: addTitle, onAdd: onAdd)
            }
            #endif
        } else {
            frame(minHeight: legacyMinHeight)
        }
    }

    @ViewBuilder
    fileprivate func onboardingFooter(
        _ buttons: OnboardingNavigationButtons,
        addTitle: LocalizedStringKey?,
        onAdd: (() -> Void)?
    ) -> some View {
        Group {
            if let addTitle, let onAdd {
                buttons.addingButton(addTitle, action: onAdd)
            } else {
                buttons
            }
        }
        .onboardingContentPadding()
    }
}
