//
//  WidgetHeaderView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI

struct WidgetHeaderView: View {
    enum Style {
        case singleLine
        case stacked
        case stackedWrapRange
    }

    let title: String
    let periodToken: String
    let rangeText: String
    var style: Style = .singleLine

    var body: some View {
        switch style {
        case .singleLine:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Spacer(minLength: 0)

                Text(periodRangeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)

        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(periodRangeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            .accessibilityElement(children: .combine)

        case .stackedWrapRange:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(periodRangeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Helpers

    private var periodRangeText: String {
        let token = periodToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty {
            return rangeText
        }
        return "\(token) • \(rangeText)"
    }
}
