//
//  MarinaResponseTestHelpers.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 2/10/26.
//

import Foundation
@testable import Offshore

// MARK: - Fixtures

enum MarinaResponseFixtures {
    static let canonicalPrompt = "how am I doing this month?"

    static func metricRawAnswer(
        id: UUID = UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!,
        queryID: UUID = UUID(uuidString: "CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD")!
    ) -> HomeAnswer {
        HomeAnswer(
            id: id,
            queryID: queryID,
            kind: .metric,
            title: "Spend This Month",
            subtitle: "February 2026",
            primaryValue: "$1,350.00",
            rows: [
                HomeAnswerRow(title: "Planned", value: "$1,100.00"),
                HomeAnswerRow(title: "Variable", value: "$250.00")
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func noDataRawAnswer() -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Largest Recent Transactions",
            subtitle: "No transactions found in this range.",
            primaryValue: nil,
            rows: []
        )
    }
}

// MARK: - Parsing

struct MarinaSubtitleParts: Equatable {
    let personaLine: String?
    let sourcesBlock: String?
}

enum MarinaResponseParser {
    static func splitSubtitle(_ subtitle: String?) -> MarinaSubtitleParts {
        guard let subtitle else {
            return MarinaSubtitleParts(personaLine: nil, sourcesBlock: nil)
        }

        let marker = "\n\nSources: "
        guard let range = subtitle.range(of: marker) else {
            return MarinaSubtitleParts(personaLine: subtitle, sourcesBlock: nil)
        }

        let persona = String(subtitle[..<range.lowerBound])
        let facts = String(subtitle[range.upperBound...])
        return MarinaSubtitleParts(personaLine: persona, sourcesBlock: facts)
    }

    static func sourcesMarkerCount(in subtitle: String?) -> Int {
        guard let subtitle else { return 0 }
        return subtitle.components(separatedBy: "Sources:").count - 1
    }
}

// MARK: - Assertions

enum MarinaResponseAssertions {
    static func containsSourcesBlock(_ answer: HomeAnswer) -> Bool {
        MarinaResponseParser.splitSubtitle(answer.subtitle).sourcesBlock?.isEmpty == false
    }

    @MainActor
    static func preservesRawPayload(raw: HomeAnswer, styled: HomeAnswer) -> Bool {
        styled.id == raw.id &&
        styled.queryID == raw.queryID &&
        styled.kind == raw.kind &&
        styled.primaryValue == raw.primaryValue &&
        styled.rows == raw.rows &&
        styled.generatedAt == raw.generatedAt
    }

    static func hasSingleSourcesMarker(_ answer: HomeAnswer) -> Bool {
        MarinaResponseParser.sourcesMarkerCount(in: answer.subtitle) == 1
    }
}
