//
//  MarinaResponseDraftTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 2/10/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaResponseDraftTests {

    // MARK: - Contract Baseline

    @Test func personaIntroductionAnswer_includesDisplayNameAndSummary() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let answer = formatter.personaIntroductionAnswer(for: .marina)
        let profile = HomeAssistantPersonaCatalog.profile(for: .marina)

        #expect(answer.kind == .message)
        #expect(answer.title == profile.displayName)
        #expect(answer.subtitle?.contains(profile.summary) == true)
    }

    @Test func styledAnswer_metric_containsPersonaLeadAndSourcesBlock() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: MarinaResponseFixtures.canonicalPrompt,
            personaID: .marina
        )
        let parts = MarinaResponseParser.splitSubtitle(styled.subtitle)

        #expect(parts.personaLine?.isEmpty == false)
        #expect(parts.sourcesBlock?.contains("February 2026") == true)
        #expect(MarinaResponseAssertions.containsSourcesBlock(styled))
    }

    @Test func styledAnswer_noDataMessage_usesNoDataTitleAndSources() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = MarinaResponseFixtures.noDataRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "largest transactions",
            personaID: .marina
        )

        #expect(styled.title == "No activity in this range yet.")
        #expect(MarinaResponseAssertions.containsSourcesBlock(styled))
    }

    @Test func styledAnswer_preservesIdentityPayloadAndRows() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: MarinaResponseFixtures.canonicalPrompt,
            personaID: .marina
        )

        #expect(MarinaResponseAssertions.preservesRawPayload(raw: raw, styled: styled))
        #expect(styled.userPrompt == MarinaResponseFixtures.canonicalPrompt)
    }

    @Test func greetingAnswer_returnsMessageWithMarinaIdentity() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let greeting = formatter.greetingAnswer(for: .marina)

        #expect(greeting.kind == .message)
        #expect(greeting.title.contains("Marina"))
    }

    @Test func followUpSuggestions_metric_returnsTopCategoriesThenComparison() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let metricAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Spend",
            subtitle: nil,
            primaryValue: "$1",
            rows: []
        )

        let followUps = formatter.followUpSuggestions(after: metricAnswer, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .topCategoriesThisMonth)
        #expect(followUps[1].query.intent == .compareThisMonthToPreviousMonth)
    }

    // MARK: - Legacy Determinism

    @Test func styledAnswer_withStablePicker_isDeterministicForSameInput() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let first = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
        let second = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)

        #expect(first.subtitle == second.subtitle)
    }

    @Test func styledAnswer_withRotatingPicker_increasesSubtitleDiversity() throws {
        var nextIndex = 0
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { upperBound, _ in
            guard upperBound > 0 else { return 0 }
            defer { nextIndex += 1 }
            return nextIndex % upperBound
        })
        let raw = MarinaResponseFixtures.metricRawAnswer()

        var uniqueSubtitles = Set<String>()
        for _ in 0..<5 {
            let styled = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
            if let subtitle = styled.subtitle {
                uniqueSubtitles.insert(subtitle)
            }
        }

        #expect(uniqueSubtitles.count == 5)
    }

    @Test func unresolvedPromptAnswer_preservesPromptAndClarifiesIntent() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let prompt = "can you find my leaks?"

        let answer = formatter.unresolvedPromptAnswer(for: prompt, personaID: .marina)

        #expect(answer.kind == .message)
        #expect(answer.userPrompt == prompt)
        #expect(answer.title.contains("clearer budgeting prompt"))
    }

    @Test func styledAnswer_containsExactlyOneSourcesMarker() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)

        #expect(MarinaResponseAssertions.hasSingleSourcesMarker(styled))
    }

    // MARK: - Marina Footer

    @Test func styledAnswer_whenMarinaRulesEnabled_appendsRulesModelFooter() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)

        #expect(styled.subtitle?.contains("Rules/Model: MarinaResponseRules v1.0 (non-LLM)") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_includesStructuredFooterFields() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let footerContext = HomeAssistantPersonaFooterContext(
            dataWindow: "2026-02-01–2026-02-10",
            sources: ["PlannedExpense", "VariableExpense", "Income"],
            queries: ["spendThisMonth#Q1"]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "spend this month",
            personaID: .marina,
            footerContext: footerContext
        )

        expectMarinaFooter(
            in: styled.subtitle,
            dataWindow: "2026-02-01–2026-02-10",
            sourcesCSV: "PlannedExpense, VariableExpense, Income",
            queriesCSV: "spendThisMonth#Q1"
        )
    }

    // MARK: - Marina Cooldown

    @Test func styledAnswer_whenMarinaRulesEnabled_avoidsImmediateRepeatWithFixedPicker() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let first = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
        let second = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)

        #expect(first.subtitle != second.subtitle)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_blocksLastTwoPhraseIndexes() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let first = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
        let second = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
        let third = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)

        let unique = Set([first.subtitle ?? "", second.subtitle ?? "", third.subtitle ?? ""])
        #expect(unique.count == 3)
    }

    // MARK: - Marina Seed

    @Test func styledAnswer_whenMarinaRulesEnabled_sameSeedContextIgnoresAnswerIDAcrossSessions() throws {
        let firstFormatter = HomeAssistantPersonaFormatter(
            sessionSeed: 42,
            responseRules: .marina
        )
        let secondFormatter = HomeAssistantPersonaFormatter(
            sessionSeed: 42,
            responseRules: .marina
        )
        let seedContext = HomeAssistantPersonaSeedContext.from(
            actorID: "workspace-123",
            intentKey: HomeQueryIntent.spendThisMonth.rawValue,
            referenceDate: Date(timeIntervalSince1970: 1_707_350_400)
        )
        let firstRaw = MarinaResponseFixtures.metricRawAnswer(
            id: UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!,
            queryID: UUID(uuidString: "CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD")!
        )
        let secondRaw = MarinaResponseFixtures.metricRawAnswer(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            queryID: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!
        )

        let first = firstFormatter.styledAnswer(
            from: firstRaw,
            userPrompt: "spend this month",
            personaID: .marina,
            seedContext: seedContext
        )
        let second = secondFormatter.styledAnswer(
            from: secondRaw,
            userPrompt: "spend this month",
            personaID: .marina,
            seedContext: seedContext
        )

        #expect(first.subtitle == second.subtitle)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_seedKeyIncludesActorIntentAndMonth() throws {
        var observedKeys: [String] = []
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, key in
                observedKeys.append(key)
                return 0
            },
            responseRules: .marina
        )
        let seedContext = HomeAssistantPersonaSeedContext.from(
            actorID: "workspace-abc",
            intentKey: HomeQueryIntent.periodOverview.rawValue,
            referenceDate: Date(timeIntervalSince1970: 1_707_350_400)
        )
        let raw = MarinaResponseFixtures.metricRawAnswer()

        _ = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina,
            seedContext: seedContext
        )

        let responseKey = observedKeys.first(where: { $0.hasPrefix("response.") })
        #expect(responseKey?.contains("workspace-abc") == true)
        #expect(responseKey?.contains(HomeQueryIntent.periodOverview.rawValue) == true)
        #expect(responseKey?.contains("202402") == true)
        #expect(responseKey?.contains(raw.id.uuidString) == false)
    }

    // MARK: - Marina Echo

    @Test func styledAnswer_whenMarinaRulesEnabled_includesPromptEchoLine() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("You asked about this month") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_blankPromptDoesNotIncludeEchoLine() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "   ",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("You asked:") == false)
        #expect(styled.subtitle?.contains("You asked about this month") == false)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_cardPromptEchoesCardName() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "show me blue card spending",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("blue card") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_incomePromptEchoesSource() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "income from salary this quarter",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("income from salary") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_intentFallbackUsesCategoryEcho() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let seedContext = HomeAssistantPersonaSeedContext.from(
            actorID: "workspace-abc",
            intentKey: HomeQueryIntent.categorySpendShare.rawValue,
            referenceDate: Date(timeIntervalSince1970: 1_707_350_400)
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "show me the breakdown",
            personaID: .marina,
            seedContext: seedContext
        )

        #expect(styled.subtitle?.contains("category-level spending") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_echoContextUsesCanonicalCardName() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let echoContext = HomeAssistantPersonaEchoContext(
            cardName: "Chase Sapphire Reserve",
            categoryName: nil,
            incomeSourceName: nil
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "blue card spend this month",
            personaID: .marina,
            echoContext: echoContext
        )

        #expect(styled.subtitle?.contains("Chase Sapphire Reserve") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_echoContextUsesCanonicalCategoryName() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let echoContext = HomeAssistantPersonaEchoContext(
            cardName: nil,
            categoryName: "Groceries",
            incomeSourceName: nil
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "food category breakdown",
            personaID: .marina,
            echoContext: echoContext
        )

        #expect(styled.subtitle?.contains("Groceries") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_echoContextUsesCanonicalIncomeSourceName() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let echoContext = HomeAssistantPersonaEchoContext(
            cardName: nil,
            categoryName: nil,
            incomeSourceName: "Salary"
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "income from job",
            personaID: .marina,
            echoContext: echoContext
        )

        #expect(styled.subtitle?.contains("income from Salary") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_includesFactsLeadLineBeforeSources() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("Here is the direct read:\nSources:") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_repeatedMonthPromptVariesEchoLine() throws {
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, _ in 0 },
            responseRules: .marina,
            cooldownSessionID: "echo-variation-session"
        )
        let raw = MarinaResponseFixtures.metricRawAnswer()

        let first = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )
        let second = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        let firstPersona = MarinaResponseParser.splitSubtitle(first.subtitle).personaLine
        let secondPersona = MarinaResponseParser.splitSubtitle(second.subtitle).personaLine
        #expect(firstPersona != secondPersona)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_metricResponsesCoverMultipleToneLanes() throws {
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, _ in 0 },
            responseRules: .marina,
            cooldownSessionID: "lane-balance-session"
        )
        let raw = MarinaResponseFixtures.metricRawAnswer()

        var personaLines: [String] = []
        for _ in 0..<6 {
            let styled = formatter.styledAnswer(
                from: raw,
                userPrompt: "how am I doing this month?",
                personaID: .marina
            )
            if let personaLine = MarinaResponseParser.splitSubtitle(styled.subtitle).personaLine?.lowercased() {
                personaLines.append(personaLine)
            }
        }

        #expect(personaLines.contains(where: { $0.contains("practical") || $0.contains("status check") || $0.contains("money reality check") }))
        #expect(personaLines.contains(where: { $0.contains("you are doing better") || $0.contains("you are keeping your footing") || $0.contains("you are showing consistency") }))
        #expect(personaLines.contains(where: { $0.contains("bestie") || $0.contains("cute progress") }))
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_snippetEchoDoesNotAlwaysUseYouAskedPrefix() throws {
        var counters: [String: Int] = [:]
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { upperBound, key in
                guard upperBound > 0 else { return 0 }
                let current = counters[key, default: 0]
                counters[key] = current + 1
                return current % upperBound
            },
            responseRules: .marina,
            cooldownSessionID: "snippet-diversity-session"
        )
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let prompt = "check this unusual phrase for me right now please"

        var personaLines: [String] = []
        for _ in 0..<4 {
            let styled = formatter.styledAnswer(
                from: raw,
                userPrompt: prompt,
                personaID: .marina
            )
            if let personaLine = MarinaResponseParser.splitSubtitle(styled.subtitle).personaLine {
                personaLines.append(personaLine)
            }
        }

        #expect(personaLines.isEmpty == false)
        #expect(personaLines.contains(where: { $0.contains("You asked:") == false }))
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_statusGood_usesGoodStatusToneLane() throws {
        let formatter = makeMarinaFormatter()
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Overview",
            subtitle: "February 2026",
            primaryValue: "$1,200.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "Good: spending improved vs previous period")
            ]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("You made progress against last period. Keep this exact energy.") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_statusOk_usesOkStatusToneLane() throws {
        let formatter = makeMarinaFormatter()
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Overview",
            subtitle: "February 2026",
            primaryValue: "$1,200.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "OK: spending is relatively stable")
            ]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("You are steady right now, which is a solid base.") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_statusWatch_usesWatchStatusToneLane() throws {
        let formatter = makeMarinaFormatter()
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Overview",
            subtitle: "February 2026",
            primaryValue: "$1,200.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "Watch: spending is above previous period")
            ]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(styled.subtitle?.contains("This month needs a tighter pass, and we can do that quickly.") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_recommendationBranch_switchesForAheadVsBehindStatus() throws {
        let formatter = makeMarinaFormatter()
        let aheadRaw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Overview",
            subtitle: "February 2026",
            primaryValue: "$1,200.00",
            rows: [HomeAnswerRow(title: "Status", value: "Good: spending improved vs previous period")]
        )
        let behindRaw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Overview",
            subtitle: "February 2026",
            primaryValue: "$1,600.00",
            rows: [HomeAnswerRow(title: "Status", value: "Watch: spending is above previous period")]
        )

        let ahead = formatter.styledAnswer(
            from: aheadRaw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )
        let behind = formatter.styledAnswer(
            from: behindRaw,
            userPrompt: "how am I doing this month?",
            personaID: .marina
        )

        #expect(ahead.subtitle?.contains("Keep this exact energy") == true)
        #expect(behind.subtitle?.contains("tighter pass") == true)
    }

    @Test func copyLibrary_marinaResponsePoolsAreExpandedForVariety() throws {
        var counters: [String: Int] = [:]
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { upperBound, key in
            guard upperBound > 0 else { return 0 }
            let current = counters[key, default: 0]
            counters[key] = current + 1
            return current % upperBound
        })
        let metricRaw = MarinaResponseFixtures.metricRawAnswer()
        let listRaw = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Top Categories",
            subtitle: "February 2026",
            primaryValue: nil,
            rows: [HomeAnswerRow(title: "Dining", value: "$420")]
        )

        var metricSubtitles = Set<String>()
        var listSubtitles = Set<String>()
        for _ in 0..<10 {
            if let subtitle = formatter.styledAnswer(from: metricRaw, userPrompt: "spend this month", personaID: .marina).subtitle {
                metricSubtitles.insert(subtitle)
            }
            if let subtitle = formatter.styledAnswer(from: listRaw, userPrompt: "top categories", personaID: .marina).subtitle {
                listSubtitles.insert(subtitle)
            }
        }

        #expect(metricSubtitles.count >= 8)
        #expect(listSubtitles.count >= 8)
    }

    // MARK: - Marina Integration

    @Test func styledAnswer_whenMarinaRulesEnabled_composesCanonicalEchoAndStructuredFooterEndToEnd() throws {
        let formatter = HomeAssistantPersonaFormatter(
            sessionSeed: 99,
            responseRules: .marina,
            cooldownSessionID: "integration-session"
        )
        let raw = MarinaResponseFixtures.metricRawAnswer(
            id: UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!,
            queryID: UUID(uuidString: "CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD")!
        )
        let seedContext = HomeAssistantPersonaSeedContext.from(
            actorID: "workspace-001",
            intentKey: HomeQueryIntent.cardSpendTotal.rawValue,
            referenceDate: Date(timeIntervalSince1970: 1_707_350_400)
        )
        let footerContext = HomeAssistantPersonaFooterContext(
            dataWindow: "2026-02-01–2026-02-10",
            sources: ["Category", "PlannedExpense", "VariableExpense"],
            queries: ["cardSpendTotal#CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD"]
        )
        let echoContext = HomeAssistantPersonaEchoContext(
            cardName: "Chase Sapphire Reserve",
            categoryName: nil,
            incomeSourceName: nil
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "blue card spending",
            personaID: .marina,
            seedContext: seedContext,
            footerContext: footerContext,
            echoContext: echoContext
        )

        #expect(styled.subtitle?.contains("Chase Sapphire Reserve") == true)
        expectMarinaFooter(
            in: styled.subtitle,
            dataWindow: "2026-02-01–2026-02-10",
            sourcesCSV: "Category, PlannedExpense, VariableExpense",
            queriesCSV: "cardSpendTotal#CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD"
        )
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_bundleFooterKeepsMultiQueryOrderAndSeparator() throws {
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, _ in 0 },
            responseRules: .marina,
            cooldownSessionID: "bundle-footer-session"
        )
        let raw = HomeAnswer(
            queryID: UUID(uuidString: "AAAAAAAA-0000-1111-2222-BBBBBBBBBBBB")!,
            kind: .list,
            title: "Budget Check-In",
            subtitle: "February 2026 snapshot",
            primaryValue: "$1,800.00",
            rows: [
                HomeAnswerRow(title: "Spend Summary", value: "$3,200.00"),
                HomeAnswerRow(title: "Savings Summary", value: "$1,800.00")
            ]
        )
        let footerContext = HomeAssistantPersonaFooterContext(
            dataWindow: "2026-02-01–2026-02-10",
            sources: ["Category", "PlannedExpense", "VariableExpense", "Income"],
            queries: [
                "periodOverview#Q1",
                "savingsStatus#Q2",
                "topCategoriesThisMonth#Q3",
                "cardVariableSpendingHabits#Q4"
            ]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month",
            personaID: .marina,
            footerContext: footerContext
        )

        #expect(styled.subtitle?.contains("\n\n---\n") == true)
        #expect(styled.subtitle?.contains("Queries: periodOverview#Q1, savingsStatus#Q2, topCategoriesThisMonth#Q3, cardVariableSpendingHabits#Q4") == true)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_provenanceReferencesOnlyExecutedQueryIDs() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let executedQueryID = "spendThisMonth#Q-ONLY"
        let unexecutedQueryID = "topCategoriesThisMonth#Q-NOT-RUN"
        let footerContext = HomeAssistantPersonaFooterContext(
            dataWindow: "2026-02-01–2026-02-10",
            sources: ["Categories", "Variable expenses"],
            queries: [executedQueryID]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "spend this month",
            personaID: .marina,
            footerContext: footerContext
        )

        #expect(styled.subtitle?.contains("Queries: \(executedQueryID)") == true)
        #expect(styled.subtitle?.contains(unexecutedQueryID) == false)
    }

    @Test func styledAnswer_whenMarinaRulesEnabled_hasNoPlaceholderLeakage() throws {
        let formatter = makeMarinaFormatter()
        let raw = MarinaResponseFixtures.metricRawAnswer()
        let footerContext = HomeAssistantPersonaFooterContext(
            dataWindow: "2026-02-01–2026-02-10",
            sources: ["Categories", "Income"],
            queries: ["periodOverview#Q1"]
        )

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "how am I doing this month?",
            personaID: .marina,
            footerContext: footerContext
        )

        #expect(styled.subtitle?.contains("{") == false)
        #expect(styled.subtitle?.contains("}") == false)
    }

    // MARK: - Helpers

    private func makeMarinaFormatter() -> HomeAssistantPersonaFormatter {
        HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, _ in 0 },
            responseRules: .marina
        )
    }

    private func expectMarinaFooter(
        in subtitle: String?,
        dataWindow: String,
        sourcesCSV: String,
        queriesCSV: String
    ) {
        #expect(subtitle?.contains("Data window: \(dataWindow)") == true)
        #expect(subtitle?.contains("Sources: \(sourcesCSV)") == true)
        #expect(subtitle?.contains("Queries: \(queriesCSV)") == true)
        #expect(subtitle?.contains("Rules/Model: MarinaResponseRules v1.0 (non-LLM)") == true)
    }
}
