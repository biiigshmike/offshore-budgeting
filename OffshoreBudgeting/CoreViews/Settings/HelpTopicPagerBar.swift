import SwiftUI

struct HelpTopicPagerBar: View {
    enum Presentation {
        case footer
        case tabAccessory
        case compactFooter
    }

    let previousTitle: String?
    let nextTitle: String?
    let onBack: () -> Void
    let onNext: () -> Void
    var presentation: Presentation = .footer

    // Match the five-tab landscape bar at standard text sizes.
    private static let landscapePillMaxWidth: CGFloat = 488
    private var usesCompactLabels: Bool { presentation != .footer }

    private var isBackEnabled: Bool {
        previousTitle != nil
    }

    private var isNextEnabled: Bool {
        nextTitle != nil
    }

    private var backTint: Color {
        isBackEnabled ? Color("OffshoreDepth") : Color("OffshoreWave")
    }

    private var nextTint: Color {
        isNextEnabled ? Color("AccentColor") : Color("OffshoreWave")
    }

    private var backActionTitle: String {
        String(localized: "common.back", defaultValue: "Back", comment: "Back action label.")
    }

    private var nextActionTitle: String {
        String(localized: "common.next", defaultValue: "Next", comment: "Next action label.")
    }

    private var previousDisplayTitle: String {
        previousTitle ?? String(localized: "help.startOfSection", defaultValue: "Start of Section", comment: "Label shown when there is no previous help topic.")
    }

    private var nextDisplayTitle: String {
        nextTitle ?? String(localized: "help.endOfSection", defaultValue: "End of Section", comment: "Label shown when there is no next help topic.")
    }

    var body: some View {
        if presentation == .compactFooter {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                buttons
                    .frame(maxWidth: Self.landscapePillMaxWidth)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            } else {
                buttons
                    .frame(maxWidth: Self.landscapePillMaxWidth)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        } else if presentation == .tabAccessory {
            buttons
        } else if #available(iOS 26.0, macCatalyst 26.0, *) {
            buttons
        } else {
            VStack(spacing: 0) {
                Divider()

                buttons
                    .background(.ultraThinMaterial)
            }
        }
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            styledPagerButton(
                action: onBack,
                isEnabled: isBackEnabled,
                tint: backTint,
                accessibilityLabel: "\(backActionTitle), \(previousDisplayTitle)"
            ) {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        if usesCompactLabels {
                            Image(systemName: "chevron.backward")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        Text(backActionTitle)
                    }
                    .font((usesCompactLabels ? Font.body : Font.footnote).weight(.semibold))
                    if !usesCompactLabels {
                        Text(previousDisplayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }

            styledPagerButton(
                action: onNext,
                isEnabled: isNextEnabled,
                tint: nextTint,
                accessibilityLabel: "\(nextActionTitle), \(nextDisplayTitle)"
            ) {
                VStack(spacing: 3) {
                    HStack(spacing: 4) {
                        Text(nextActionTitle)
                        if usesCompactLabels {
                            Image(systemName: "chevron.forward")
                                .foregroundStyle(isNextEnabled ? Color("AccentColor") : Color.secondary)
                                .accessibilityHidden(true)
                        }
                    }
                    .font((usesCompactLabels ? Font.body : Font.footnote).weight(.semibold))
                    if !usesCompactLabels {
                        Text(nextDisplayTitle)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, usesCompactLabels ? 0 : 10)
    }

    @ViewBuilder
    private func styledPagerButton<Label: View>(
        action: @escaping () -> Void,
        isEnabled: Bool,
        tint: Color,
        accessibilityLabel: String,
        @ViewBuilder label: () -> Label
    ) -> some View {
        let button = Button(action: action) {
            label()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: usesCompactLabels ? 44 : nil)
                .contentShape(Rectangle())
        }
        .tint(tint)
        .disabled(!isEnabled)

        if usesCompactLabels {
            button
                .foregroundStyle(isEnabled ? .primary : .secondary)
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: accessibilityLabel))
        } else if #available(iOS 26.0, macCatalyst 26.0, *) {
            button.glassProminentButtonStyleCompat()
        } else {
            button.buttonStyle(.borderedProminent)
        }
    }
}
