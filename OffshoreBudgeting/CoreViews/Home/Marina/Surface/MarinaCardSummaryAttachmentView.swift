//
//  MarinaCardSummaryAttachmentView.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI

struct MarinaCardSummaryAttachmentView: View {
    let workspace: Workspace
    let summary: CardSummaryPresentationModel
    let card: Card?

    var body: some View {
        if let card {
            NavigationLink {
                CardDetailView(workspace: workspace, card: card)
            } label: {
                CardSummaryPresentationView(model: summary, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(summary.title) card summary")
            .accessibilityValue(accessibilitySummary)
            .accessibilityHint("Opens card details")
            .accessibilityIdentifier("marina.cardSummary")
        } else {
            CardSummaryPresentationView(model: summary, showsChevron: false)
                .accessibilityLabel("\(summary.title) card summary")
                .accessibilityValue(accessibilitySummary)
                .accessibilityIdentifier("marina.cardSummary")
        }
    }

    private var accessibilitySummary: String {
        [
            summary.dateRangeSubtitle,
            "Total \(CurrencyFormatter.string(from: summary.total))",
            "Planned \(CurrencyFormatter.string(from: summary.plannedTotal))",
            "Variable \(CurrencyFormatter.string(from: summary.variableTotal))"
        ].joined(separator: ", ")
    }
}
