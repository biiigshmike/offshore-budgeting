//
//  CardSummaryPresentationView.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import SwiftUI

struct CardSummaryPresentationView: View {
    let model: CardSummaryPresentationModel
    let showsChevron: Bool

    var body: some View {
        HomeTileContainer(
            title: model.title,
            subtitle: model.dateRangeSubtitle,
            accent: .primary,
            showsChevron: showsChevron
        ) {
            CardSummaryContentView(title: model.title, themeRaw: model.themeRaw, effectRaw: model.effectRaw,
                                   total: model.total, planned: model.plannedTotal, variable: model.variableTotal)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(model.title) card summary")
        .accessibilityValue(
            "\(model.dateRangeSubtitle), total \(CurrencyFormatter.string(from: model.total)), planned \(CurrencyFormatter.string(from: model.plannedTotal)), variable \(CurrencyFormatter.string(from: model.variableTotal))"
        )
    }

}
