//
//  CardSummaryPresentationModel.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import Foundation

struct CardSummaryPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let cardID: UUID
    let title: String
    let themeRaw: String
    let effectRaw: String
    let startDate: Date
    let endDate: Date
    let plannedTotal: Double
    let variableTotal: Double
    let total: Double

    var id: UUID { cardID }

    var dateRangeSubtitle: String {
        "\(AppDateFormat.abbreviatedDate(startDate)) - \(AppDateFormat.abbreviatedDate(endDate))"
    }

    init(
        cardID: UUID,
        title: String,
        themeRaw: String,
        effectRaw: String,
        startDate: Date,
        endDate: Date,
        plannedTotal: Double,
        variableTotal: Double,
        total: Double
    ) {
        self.cardID = cardID
        self.title = title
        self.themeRaw = themeRaw
        self.effectRaw = effectRaw
        self.startDate = startDate
        self.endDate = endDate
        self.plannedTotal = plannedTotal
        self.variableTotal = variableTotal
        self.total = total
    }

    static func make(
        for card: Card,
        startDate: Date,
        endDate: Date,
        excludeFuturePlannedExpenses: Bool,
        excludeFutureVariableExpenses: Bool
    ) -> CardSummaryPresentationModel {
        let metrics = HomeCardMetricsCalculator.metrics(
            for: card,
            start: startDate,
            end: endDate,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses
        )

        return CardSummaryPresentationModel(
            cardID: card.id,
            title: card.name,
            themeRaw: card.theme,
            effectRaw: card.effect,
            startDate: startDate,
            endDate: endDate,
            plannedTotal: metrics.plannedTotal,
            variableTotal: metrics.variableTotal,
            total: metrics.total
        )
    }
}
