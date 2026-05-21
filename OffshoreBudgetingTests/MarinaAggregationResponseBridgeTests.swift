import Foundation
import Testing
@testable import Offshore

struct MarinaAggregationResponseBridgeTests {
    private let bridge = MarinaAggregationResponseBridge()

    @Test func responseBridge_preservesScalarAnswer() {
        let answer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", primaryValue: "$42.00")
        let result = MarinaAggregationResult.scalar(
            MarinaScalarAggregationResult(
                title: answer.title,
                renderedValue: answer.primaryValue,
                amount: 42,
                rows: [],
                sourceAnswer: answer
            )
        )

        let bridged = bridge.responseCompatibleAnswer(from: result)

        #expect(bridged.kind == .metric)
        #expect(bridged.primaryValue == "$42.00")
    }

    @Test func responseBridge_preservesComparisonValues() {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .comparison,
            title: "Comparison",
            subtitle: "Up $10.00",
            primaryValue: "$30.00",
            rows: [
                HomeAnswerRow(title: "May", value: "$30.00"),
                HomeAnswerRow(title: "April", value: "$20.00")
            ]
        )
        let result = MarinaAggregationResult.comparison(
            MarinaComparisonAggregationResult(
                title: answer.title,
                primaryLabel: "May",
                primaryRenderedValue: "$30.00",
                primaryAmount: 30,
                comparisonLabel: "April",
                comparisonRenderedValue: "$20.00",
                comparisonAmount: 20,
                deltaRenderedValue: "Up $10.00",
                sourceAnswer: answer
            )
        )

        let bridged = bridge.responseCompatibleAnswer(from: result)

        #expect(bridged.kind == .comparison)
        #expect(bridged.rows.count == 2)
        #expect(bridged.rows[0].value == "$30.00")
        #expect(bridged.rows[1].value == "$20.00")
    }

    @Test func responseBridge_preservesRankedRowsAndGroupedPercentages() {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Category Spend Share",
            primaryValue: "$100.00",
            rows: [
                HomeAnswerRow(title: "Groceries", value: "$60.00 (60%)"),
                HomeAnswerRow(title: "Travel", value: "$40.00 (40%)")
            ]
        )
        let list = MarinaListAggregationResult(
            title: answer.title,
            primaryRenderedValue: answer.primaryValue,
            rows: [
                MarinaAggregationResultRow(label: "Groceries", renderedValue: "$60.00 (60%)", amount: 60, percentage: 0.6),
                MarinaAggregationResultRow(label: "Travel", renderedValue: "$40.00 (40%)", amount: 40, percentage: 0.4)
            ],
            sourceAnswer: answer
        )

        let ranked = bridge.responseCompatibleAnswer(from: .rankedList(list))
        let grouped = bridge.responseCompatibleAnswer(from: .groupedBreakdown(list))

        #expect(ranked.rows.map(\.title) == ["Groceries", "Travel"])
        #expect(grouped.rows[0].value.contains("60%"))
        #expect(grouped.rows[1].value.contains("40%"))
    }

    @Test func responseBridge_unsupportedProducesNonCrashingMessage() {
        let unsupported = MarinaTypedUnsupportedResponse(
            kind: .unsupportedOperation,
            message: "That operation is not supported for safe Marina queries yet."
        )

        let bridged = bridge.responseCompatibleAnswer(from: MarinaAggregationResult.unsupported(unsupported))
        let summary = bridge.summary(from: .unsupported(unsupported))

        #expect(bridged.kind == .message)
        #expect(bridged.subtitle == "That operation is not supported for safe Marina queries yet.")
        #expect(summary.contains("I can answer this a different way"))
    }

    @Test func responseBridge_noDataPreservesTypedMessage() {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "No data found",
            subtitle: "No data available for that range."
        )
        let result = MarinaAggregationResult.noData(
            MarinaNoDataAggregationResult(
                title: answer.title,
                message: answer.subtitle ?? "",
                sourceAnswer: answer
            )
        )

        let bridged = bridge.responseCompatibleAnswer(from: result)
        let summary = bridge.summary(from: result)

        #expect(bridged.kind == .message)
        #expect(bridged.title == "No data found")
        #expect(bridged.subtitle == "No data available for that range.")
        #expect(summary.contains("No data found"))
    }

    @Test func responseBridge_clarificationProducesNonExecutingMessage() {
        let clarification = MarinaTypedClarification(
            kind: .missingTarget,
            message: "Which target did you mean?",
            choices: [
                MarinaClarificationChoice(title: "Groceries", entityTypeHint: .category, rawValue: "Groceries"),
                MarinaClarificationChoice(title: "Grocery Card", entityTypeHint: .card, rawValue: "Grocery Card")
            ]
        )

        let bridged = bridge.responseCompatibleAnswer(from: clarification)
        let outcomeAnswer = bridge.responseCompatibleAnswer(from: MarinaPlanValidationOutcome.clarification(clarification))

        #expect(bridged.kind == .message)
        #expect(bridged.title == "I need one choice first")
        #expect(bridged.subtitle == "Which target did you mean?")
        #expect(bridged.rows.map(\.title) == ["Groceries (category)", "Grocery Card (card)"])
        #expect(outcomeAnswer?.title == bridged.title)
        #expect(outcomeAnswer?.subtitle == bridged.subtitle)
    }
}
