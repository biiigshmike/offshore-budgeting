//
//  WidgetHeaderView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI

enum WidgetRangeDisplayMode {
    case full
    case compact
}

enum WidgetSecondaryTextBehavior {
    case singleLine
    case flexible(maxLines: Int)
}

func widgetCompactDateRangeText(start: Date, end: Date, calendar: Calendar = .current) -> String {
    let startMonth = calendar.component(.month, from: start)
    let endMonth = calendar.component(.month, from: end)
    let startYear = calendar.component(.year, from: start)
    let endYear = calendar.component(.year, from: end)

    if startMonth == endMonth && startYear == endYear {
        let month = start.formatted(.dateTime.month(.abbreviated))
        let startDay = start.formatted(.dateTime.day())
        let endDay = end.formatted(.dateTime.day())
        return "\(month) \(startDay)-\(endDay)"
    }

    let startText = start.formatted(.dateTime.month(.abbreviated).day())
    let endText = end.formatted(.dateTime.month(.abbreviated).day())
    return "\(startText)-\(endText)"
}

func widgetJoinedPeriodRangeText(periodToken: String, rangeText: String) -> String {
    let token = periodToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard token.isEmpty == false else { return rangeText }
    return "\(token) • \(rangeText)"
}

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
    var compactRangeText: String? = nil
    var rangeDisplayMode: WidgetRangeDisplayMode = .full
    var secondaryBehavior: WidgetSecondaryTextBehavior = .singleLine

    var body: some View {
        switch style {
        case .singleLine:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                Spacer(minLength: 0)

                secondaryText
                    .multilineTextAlignment(.trailing)
            }
            .accessibilityElement(children: .combine)

        case .stacked:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                secondaryText
            }
            .accessibilityElement(children: .combine)

        case .stackedWrapRange:
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .layoutPriority(1)

                secondaryText
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Helpers

    private var periodRangeText: String {
        let resolvedRangeText = switch rangeDisplayMode {
        case .full:
            rangeText
        case .compact:
            compactRangeText ?? rangeText
        }
        return widgetJoinedPeriodRangeText(periodToken: periodToken, rangeText: resolvedRangeText)
    }

    private var secondaryText: some View {
        Text(periodRangeText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(lineLimit)
            .minimumScaleFactor(minimumScaleFactor)
            .fixedSize(horizontal: false, vertical: allowsWrapping)
    }

    private var lineLimit: Int {
        switch secondaryBehavior {
        case .singleLine:
            switch style {
            case .stackedWrapRange:
                return 2
            default:
                return 1
            }
        case .flexible(let maxLines):
            return maxLines
        }
    }

    private var minimumScaleFactor: CGFloat {
        switch secondaryBehavior {
        case .singleLine:
            return style == .singleLine ? 0.72 : 0.78
        case .flexible:
            return 0.75
        }
    }

    private var allowsWrapping: Bool {
        switch secondaryBehavior {
        case .singleLine:
            return style == .stackedWrapRange
        case .flexible:
            return true
        }
    }
}
