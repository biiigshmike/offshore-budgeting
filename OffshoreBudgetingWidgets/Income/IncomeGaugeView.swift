//
//  IncomeGaugeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import SwiftUI

struct IncomeGaugeView: View {
    enum FooterStyle {
        case none
        case progressOnly(String)
        case legend(planned: Double, actual: Double)
    }

    enum FooterAlignment {
        case leading
        case centered
    }

    let planned: Double
    let actual: Double

    var showsPercentEnds: Bool = false
    var footer: FooterStyle = .none
    var footerAlignment: FooterAlignment = .leading

    var body: some View {
        let progress = progressFraction(planned: planned, actual: actual)

        VStack(alignment: .leading, spacing: 6) {
            if showsPercentEnds {
                HStack(spacing: 8) {
                    Text("0%")
                    Spacer(minLength: 0)
                    Text("100%")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Capsule(style: .continuous)
                .fill(.secondary.opacity(0.14))
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        Capsule(style: .continuous)
                            .fill(progressColor(planned: planned, actual: actual))
                            .frame(width: max(0, geo.size.width * progress))
                    }
                }
                .clipShape(Capsule(style: .continuous))
                .accessibilityLabel("Income progress")
                .accessibilityValue("\(Int((progress * 100).rounded())) percent")

            switch footer {
            case .none:
                EmptyView()

            case .progressOnly(let text):
                Group {
                    if footerAlignment == .centered {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text(text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            case .legend(let planned, let actual):
                HStack(spacing: 6) {
                    Text("Planned")
                        .foregroundStyle(.secondary)
                    Text(planned, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Text("Actual")
                        .foregroundStyle(.secondary)
                    Text(actual, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .foregroundStyle(.primary)
                }
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
        }
    }

    // MARK: - Helpers

    private func progressFraction(planned: Double, actual: Double) -> CGFloat {
        guard planned > 0 else { return 0 }
        let frac = actual / planned
        return CGFloat(min(max(frac, 0), 1))
    }

    private func progressColor(planned: Double, actual: Double) -> Color {
        guard planned > 0 else { return .secondary.opacity(0.35) }
        return actual >= planned ? .green.opacity(0.85) : .accentColor.opacity(0.85)
    }
}
