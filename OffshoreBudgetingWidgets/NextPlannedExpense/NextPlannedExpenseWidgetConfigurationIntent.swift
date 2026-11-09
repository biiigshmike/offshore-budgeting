//
//  NextPlannedExpenseWidgetConfigurationIntent.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit
import AppIntents

enum NextPlannedExpenseWidgetCardScope: String, AppEnum {
    case allCards
    case selectedCards

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Card Filter"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .allCards: "All Cards",
        .selectedCards: "Selected Cards",
    ]
}

struct NextPlannedExpenseWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Next Planned Expense Widget"
    static var description = IntentDescription("Show the next planned expense for all cards or selected cards.")

    // Keep this parameter so existing widgets retain their saved single-card selection.
    @Parameter(title: "Card Filter")
    var card: NextPlannedExpenseWidgetCardEntity?

    @Parameter(title: "Card Filter")
    var cardScope: NextPlannedExpenseWidgetCardScope?

    @Parameter(title: "Cards")
    var selectedCards: [NextPlannedExpenseWidgetCardEntity]?

    @Parameter(title: "Default Period")
    var period: NextPlannedExpenseWidgetPeriod?

    static var parameterSummary: some ParameterSummary {
        When(\.$cardScope, .equalTo, .selectedCards) {
            Summary {
                \.$cardScope
                \.$selectedCards
                \.$period
            }
        } otherwise: {
            Summary {
                \.$cardScope
                \.$period
            }
        }
    }

    init() {
        self.cardScope = .allCards
        self.period = .period
    }
}

extension NextPlannedExpenseWidgetConfigurationIntent {
    var resolvedPeriod: NextPlannedExpenseWidgetPeriod { period ?? .period }
    var resolvedPeriodToken: String { resolvedPeriod.rawValue }
    var requestedCardIDs: Set<String>? {
        switch cardScope {
        case .allCards:
            return nil
        case .selectedCards:
            return Set((selectedCards ?? []).filter { !$0.isAllCards }.map(\.id))
        case nil:
            guard let card, !card.isAllCards else { return nil }
            return [card.id]
        }
    }
}
