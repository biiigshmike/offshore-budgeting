//
//  HomeCardSummaryTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeCardSummaryTile: View {

    let workspace: Workspace
    let card: Card
    let startDate: Date
    let endDate: Date
    let excludeFuturePlannedExpensesFromCalculationsInView: Bool
    let excludeFutureVariableExpensesFromCalculationsInView: Bool

    private var presentationModel: CardSummaryPresentationModel {
        CardSummaryPresentationModel.make(
            for: card,
            startDate: startDate,
            endDate: endDate,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpensesFromCalculationsInView,
            excludeFutureVariableExpenses: excludeFutureVariableExpensesFromCalculationsInView
        )
    }

    var body: some View {
        NavigationLink {
            CardDetailView(workspace: workspace, card: card)
        } label: {
            CardSummaryPresentationView(model: presentationModel, showsChevron: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(
                format: String(
                    localized: "homeWidget.cardSummary.accessibilityLabelFormat",
                    defaultValue: "%1$@ summary",
                    comment: "Accessibility label format for card summary widget."
                ),
                locale: .current,
                card.name
            )
        )
        .accessibilityHint(String(localized: "homeWidget.cardSummary.accessibilityHint", defaultValue: "Opens card details", comment: "Accessibility hint for opening card details from Home card widget."))
    }
}
