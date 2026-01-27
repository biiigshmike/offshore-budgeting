//
//  WidgetHeaderView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI

struct WidgetHeaderView: View {
    let title: String
    let periodToken: String
    let rangeText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text("\(periodToken) • \(rangeText)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}
