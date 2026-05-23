//
//  MarinaCardSummaryAttachmentBuilder.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import Foundation

struct MarinaCardSummaryAttachmentBuilder {
    func attachingCardSummaryIfNeeded(
        to answer: HomeAnswer,
        cards: [Card],
        dateRange: HomeQueryDateRange,
        excludeFuturePlannedExpenses: Bool,
        excludeFutureVariableExpenses: Bool
    ) -> HomeAnswer {
        guard answer.attachment == nil,
              isSingleCardLookupAnswer(answer),
              let card = matchingCard(for: answer, cards: cards) else {
            return answer
        }

        let summary = CardSummaryPresentationModel.make(
            for: card,
            startDate: dateRange.startDate,
            endDate: dateRange.endDate,
            excludeFuturePlannedExpenses: excludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: excludeFutureVariableExpenses
        )

        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: fallbackSubtitle(for: summary),
            primaryValue: answer.primaryValue,
            rows: mergedRows(summary: summary, existingRows: answer.rows),
            attachment: .cardSummary(summary),
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func isSingleCardLookupAnswer(_ answer: HomeAnswer) -> Bool {
        if answer.kind == .message, answer.rows.contains(where: { $0.objectType == .card }) {
            return true
        }

        return answer.rows.contains { row in
            normalized(row.title) == "type" && normalized(row.value) == "card"
        }
    }

    private func matchingCard(for answer: HomeAnswer, cards: [Card]) -> Card? {
        let sourceIDs = Set(answer.rows.compactMap(\.sourceID))
        if sourceIDs.count == 1,
           let sourceID = sourceIDs.first,
           let card = cards.first(where: { $0.id == sourceID }) {
            return card
        }

        let matchedNames = answer.rows
            .filter { normalized($0.title) == "matched" }
            .flatMap { $0.value.components(separatedBy: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let searchText = ([answer.title] + matchedNames).joined(separator: " ")
        let matches = cards.filter { card in
            normalized(searchText).contains(normalized(card.name))
        }

        guard matches.count == 1 else { return nil }
        return matches.first
    }

    private func mergedRows(
        summary: CardSummaryPresentationModel,
        existingRows: [HomeAnswerRow]
    ) -> [HomeAnswerRow] {
        let summaryRows = [
            HomeAnswerRow(title: "Period", value: summary.dateRangeSubtitle),
            HomeAnswerRow(title: "Total", value: CurrencyFormatter.string(from: summary.total)),
            HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: summary.plannedTotal)),
            HomeAnswerRow(title: "Variable", value: CurrencyFormatter.string(from: summary.variableTotal))
        ]
        let summaryTitles = Set(summaryRows.map { normalized($0.title) })
        return summaryRows + existingRows.filter { summaryTitles.contains(normalized($0.title)) == false }
    }

    private func fallbackSubtitle(for summary: CardSummaryPresentationModel) -> String {
        "Here's your \(summary.title). Total spending is currently \(CurrencyFormatter.string(from: summary.total)) for \(summary.dateRangeSubtitle)."
    }

    private func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
