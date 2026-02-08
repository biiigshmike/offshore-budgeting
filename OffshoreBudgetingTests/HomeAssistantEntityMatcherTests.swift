//
//  HomeAssistantEntityMatcherTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Testing
@testable import Offshore

struct HomeAssistantEntityMatcherTests {

    @Test func bestMatch_exactPhrase_returnsCandidate() throws {
        let matcher = HomeAssistantEntityMatcher()

        let match = matcher.bestMatch(
            in: "How much did I spend on Apple Card this month?",
            candidateNames: ["Chase Freedom", "Apple Card", "Amex Gold"]
        )

        #expect(match == "Apple Card")
    }

    @Test func bestMatch_typoInPrompt_stillMatchesCandidate() throws {
        let matcher = HomeAssistantEntityMatcher()

        let match = matcher.bestMatch(
            in: "How much did I spend on appl card this month?",
            candidateNames: ["Apple Card", "Chase Freedom"]
        )

        #expect(match == "Apple Card")
    }

    @Test func bestMatch_multiWordCategoryByTokens_returnsBestCandidate() throws {
        let matcher = HomeAssistantEntityMatcher()

        let match = matcher.bestMatch(
            in: "Show spending share for bills utilities",
            candidateNames: ["Groceries", "Bills & Utilities", "Dining Out"]
        )

        #expect(match == "Bills & Utilities")
    }

    @Test func bestMatch_unrelatedPrompt_returnsNil() throws {
        let matcher = HomeAssistantEntityMatcher()

        let match = matcher.bestMatch(
            in: "How am I doing overall this month?",
            candidateNames: ["Apple Card", "Bills & Utilities", "Primary Salary"]
        )

        #expect(match == nil)
    }

    @Test func rankedMatches_ambiguousEntity_returnsTopCandidates() throws {
        let matcher = HomeAssistantEntityMatcher()

        let matches = matcher.rankedMatches(
            in: "What did I spend on chase this month?",
            candidateNames: ["Chase Freedom", "Chase Sapphire", "Apple Card"],
            limit: 3
        )

        #expect(matches.contains("Chase Freedom"))
        #expect(matches.contains("Chase Sapphire"))
    }

    @Test func rankedMatches_ignoresGenericTokens_preventsFalseMatch() throws {
        let matcher = HomeAssistantEntityMatcher()

        let matches = matcher.rankedMatches(
            in: "Show card spending",
            candidateNames: ["Apple Card", "Chase Freedom"],
            limit: 3
        )

        #expect(matches.isEmpty)
    }
}
