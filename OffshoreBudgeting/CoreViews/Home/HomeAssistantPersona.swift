//
//  HomeAssistantPersona.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Persona Identifier

enum HomeAssistantPersonaID: String, CaseIterable, Codable, Identifiable {
    case marina

    var id: String { rawValue }
}

// MARK: - Persona Profile

struct HomeAssistantPersonaProfile: Equatable {
    let id: HomeAssistantPersonaID
    let displayName: String
    let summary: String
    let greetingTitle: String
    let greetingSubtitle: String
    let noDataTitle: String
    let noDataSubtitle: String
    let unresolvedPromptTitle: String
    let unresolvedPromptSubtitle: String
    let previewLines: [String]
}

// MARK: - Persona Catalog

enum HomeAssistantPersonaCatalog {
    nonisolated static let defaultPersona: HomeAssistantPersonaID = .marina

    nonisolated static func profile(for id: HomeAssistantPersonaID) -> HomeAssistantPersonaProfile {
        switch id {
        case .marina:
            return HomeAssistantPersonaProfile(
                id: .marina,
                displayName: "Marina",
                summary: "Grounded, quick, practical, and bestie energy.",
                greetingTitle: "Hi, I’m Marina.",
                greetingSubtitle: "Ask me for quick answers from your budget data.",
                noDataTitle: "No activity in this range yet.",
                noDataSubtitle: "Try a different date range or add more transactions.",
                unresolvedPromptTitle: "I can help with that once I have a clearer budgeting prompt.",
                unresolvedPromptSubtitle: "Try asking about spend totals, top categories, month-over-month change, or largest transactions.",
                previewLines: [
                    "Bestie check: You spent $1,350 this month. We can work with that.",
                    "Top category is Dining at $420. Let's keep it cute and grounded."
                ]
            )
        }
    }

    nonisolated static var allProfiles: [HomeAssistantPersonaProfile] {
        HomeAssistantPersonaID.allCases.map(profile(for:))
    }
}

// MARK: - Persona Formatter

struct HomeAssistantPersonaFormatter {
    typealias VariantIndexPicker = (_ upperBound: Int, _ key: String) -> Int

    private let variantIndexPicker: VariantIndexPicker
    private let copyLibrary: HomeAssistantPersonaCopyLibrary

    init(
        sessionSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    ) {
        self.variantIndexPicker = { upperBound, key in
            HomeAssistantPersonaFormatter.stableIndex(
                upperBound: upperBound,
                key: key,
                sessionSeed: sessionSeed
            )
        }
        self.copyLibrary = .defaultLibrary
    }

    init(variantIndexPicker: @escaping VariantIndexPicker) {
        self.variantIndexPicker = variantIndexPicker
        self.copyLibrary = .defaultLibrary
    }

    func personaIntroductionAnswer(for personaID: HomeAssistantPersonaID) -> HomeAnswer {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)
        let greetingLine = randomLine(
            from: greetingLines(for: personaID),
            key: "greeting.\(personaID.rawValue)"
        )

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: nil,
            title: profile.displayName,
            subtitle: mergedSentencePair(profile.summary, greetingLine ?? profile.greetingSubtitle),
            primaryValue: nil,
            rows: []
        )
    }

    func greetingAnswer(for personaID: HomeAssistantPersonaID) -> HomeAnswer {
        personaIntroductionAnswer(for: personaID)
    }

    func unresolvedPromptAnswer(
        for prompt: String,
        personaID: HomeAssistantPersonaID
    ) -> HomeAnswer {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let unresolvedLine = randomLine(
            from: unresolvedPromptLines(for: personaID),
            key: "unresolved.\(personaID.rawValue).\(normalizedPrompt)"
        )

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: profile.unresolvedPromptTitle,
            subtitle: unresolvedLine ?? profile.unresolvedPromptSubtitle,
            primaryValue: nil,
            rows: []
        )
    }

    func styledAnswer(
        from rawAnswer: HomeAnswer,
        userPrompt: String?,
        personaID: HomeAssistantPersonaID
    ) -> HomeAnswer {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)
        let isNoDataMessage = rawAnswer.kind == .message && rawAnswer.primaryValue == nil && rawAnswer.rows.isEmpty

        let title = isNoDataMessage ? profile.noDataTitle : rawAnswer.title
        let factualSubtitle = isNoDataMessage
            ? randomLine(
                from: noDataLines(for: personaID),
                key: "nodata.\(personaID.rawValue).\(rawAnswer.id.uuidString)"
            ) ?? profile.noDataSubtitle
            : rawAnswer.subtitle
        let personaLine = randomLine(
            from: responseLines(for: rawAnswer.kind, personaID: personaID),
            key: "response.\(personaID.rawValue).\(rawAnswer.kind.rawValue).\(rawAnswer.id.uuidString)"
        )
        let subtitle = composedSubtitle(personaLine: personaLine, factualSubtitle: factualSubtitle)

        return HomeAnswer(
            id: rawAnswer.id,
            queryID: rawAnswer.queryID,
            kind: rawAnswer.kind,
            userPrompt: userPrompt,
            title: title,
            subtitle: subtitle,
            primaryValue: rawAnswer.primaryValue,
            rows: rawAnswer.rows,
            generatedAt: rawAnswer.generatedAt
        )
    }

    func followUpSuggestions(
        after answer: HomeAnswer,
        personaID: HomeAssistantPersonaID
    ) -> [HomeAssistantSuggestion] {
        let confidenceCue = confidenceCue(for: answer)
        var slot = 0

        func makeSuggestion(_ action: String, query: HomeQuery) -> HomeAssistantSuggestion {
            defer { slot += 1 }
            return HomeAssistantSuggestion(
                title: followUpTitle(
                    action: action,
                    personaID: personaID,
                    answerID: answer.id,
                    slot: slot
                ),
                query: query
            )
        }

        switch confidenceCue {
        case .low:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3))
            ]
        case .medium:
            return [
                makeSuggestion("Top 3 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3)),
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
            ]
        case .high:
            break
        }

        if answer.title.localizedCaseInsensitiveContains("Savings") {
            return [
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth)),
                makeSuggestion("Average savings for last 6 months", query: HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 6))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Income Share") {
            return [
                makeSuggestion("Income share this month", query: HomeQuery(intent: .incomeSourceShare)),
                makeSuggestion("Average actual income this year", query: HomeQuery(intent: .incomeAverageActual))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Category Spend Share") {
            return [
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5)),
                makeSuggestion("Largest transactions this month", query: HomeQuery(intent: .largestRecentTransactions, resultLimit: 5))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Budget Overview") {
            return [
                makeSuggestion("Variable spending habits by card", query: HomeQuery(intent: .cardVariableSpendingHabits)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5))
            ]
        }

        switch answer.kind {
        case .metric:
            return [
                makeSuggestion("Top 3 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3)),
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
            ]
        case .list:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Largest 5 transactions", query: HomeQuery(intent: .largestRecentTransactions, resultLimit: 5))
            ]
        case .comparison:
            return [
                makeSuggestion("Top 5 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5)),
                makeSuggestion("Largest transactions this month", query: HomeQuery(intent: .largestRecentTransactions))
            ]
        case .message:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth))
            ]
        }
    }

    // MARK: - Copy Lines

    private func responseLines(
        for kind: HomeAnswerKind,
        personaID: HomeAssistantPersonaID
    ) -> [String] {
        copyLibrary.lines(for: personaID).response.lines(for: kind)
    }

    private func noDataLines(for personaID: HomeAssistantPersonaID) -> [String] {
        copyLibrary.lines(for: personaID).noData
    }

    private func unresolvedPromptLines(for personaID: HomeAssistantPersonaID) -> [String] {
        copyLibrary.lines(for: personaID).unresolvedPrompt
    }

    private func greetingLines(for personaID: HomeAssistantPersonaID) -> [String] {
        copyLibrary.lines(for: personaID).greeting
    }

    private func followUpLeads(for personaID: HomeAssistantPersonaID) -> [String] {
        copyLibrary.lines(for: personaID).followUpLeads
    }

    // MARK: - Helpers

    private func followUpTitle(
        action: String,
        personaID: HomeAssistantPersonaID,
        answerID: UUID,
        slot: Int
    ) -> String {
        let lead = randomLine(
            from: followUpLeads(for: personaID),
            key: "followup.\(personaID.rawValue).\(answerID.uuidString).\(slot).\(action)"
        ) ?? ""
        guard lead.isEmpty == false else { return action }
        return "\(lead) \(action)"
    }

    private func randomLine(from lines: [String], key: String) -> String? {
        guard lines.isEmpty == false else { return nil }
        let rawIndex = variantIndexPicker(lines.count, key)
        let safeIndex = min(max(0, rawIndex), lines.count - 1)
        return lines[safeIndex]
    }

    private func composedSubtitle(personaLine: String?, factualSubtitle: String?) -> String? {
        switch (personaLine, factualSubtitle) {
        case let (.some(persona), .some(facts)):
            return "\(persona)\n\nSources: \(facts)"
        case let (.some(persona), .none):
            return persona
        case let (.none, .some(facts)):
            return "Sources: \(facts)"
        case (.none, .none):
            return nil
        }
    }

    private func mergedSentencePair(_ first: String?, _ second: String?) -> String? {
        switch (first, second) {
        case let (.some(a), .some(b)):
            return "\(a) \(b)"
        case let (.some(a), .none):
            return a
        case let (.none, .some(b)):
            return b
        case (.none, .none):
            return nil
        }
    }

    private func confidenceCue(for answer: HomeAnswer) -> ConfidenceCue {
        let subtitle = answer.subtitle ?? ""

        if subtitle.localizedCaseInsensitiveContains("best-effort") {
            return .low
        }

        if subtitle.localizedCaseInsensitiveContains("likely match") {
            return .medium
        }

        return .high
    }

    private static func stableIndex(
        upperBound: Int,
        key: String,
        sessionSeed: UInt64
    ) -> Int {
        guard upperBound > 0 else { return 0 }

        let hash = fnv1a64("\(sessionSeed)|\(key)")
        let positive = Int(hash % UInt64(upperBound))
        return min(max(0, positive), upperBound - 1)
    }

    private static func fnv1a64(_ input: String) -> UInt64 {
        let offset: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3

        var hash = offset
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }

        return hash
    }
}

private enum ConfidenceCue {
    case high
    case medium
    case low
}

// MARK: - Persona Copy Library

private struct HomeAssistantPersonaCopyLibrary: Decodable {
    let personas: [HomeAssistantPersonaID: HomeAssistantPersonaLines]

    static let defaultLibrary: HomeAssistantPersonaCopyLibrary = loadDefault()

    init(personas: [HomeAssistantPersonaID: HomeAssistantPersonaLines]) {
        self.personas = personas
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawPersonas = try container.decode([String: HomeAssistantPersonaLines].self, forKey: .personas)

        var mapped: [HomeAssistantPersonaID: HomeAssistantPersonaLines] = [:]
        for (rawID, lines) in rawPersonas {
            guard let personaID = HomeAssistantPersonaID(rawValue: rawID) else { continue }
            mapped[personaID] = lines
        }

        self.personas = mapped
    }

    func lines(for personaID: HomeAssistantPersonaID) -> HomeAssistantPersonaLines {
        personas[personaID] ?? HomeAssistantPersonaLines.fallback(for: personaID)
    }

    private static func loadDefault() -> HomeAssistantPersonaCopyLibrary {
        guard
            let data = loadJSONData(),
            let decoded = try? JSONDecoder().decode(HomeAssistantPersonaCopyLibrary.self, from: data)
        else {
            return HomeAssistantPersonaCopyLibrary(personas: [:])
        }

        return decoded
    }

    private static func loadJSONData() -> Data? {
        let candidates = [
            Bundle.main,
            Bundle(for: HomeAssistantPersonaBundleMarker.self)
        ]

        for bundle in candidates {
            if let url = bundle.url(forResource: "AssistantPersonaCopy", withExtension: "json", subdirectory: "CoreViews/Home"),
               let data = try? Data(contentsOf: url) {
                return data
            }

            if let url = bundle.url(forResource: "AssistantPersonaCopy", withExtension: "json"),
               let data = try? Data(contentsOf: url) {
                return data
            }
        }

        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case personas
    }
}

private struct HomeAssistantPersonaLines: Decodable {
    let response: HomeAssistantPersonaResponseLines
    let noData: [String]
    let unresolvedPrompt: [String]
    let greeting: [String]
    let followUpLeads: [String]

    static func fallback(for personaID: HomeAssistantPersonaID) -> HomeAssistantPersonaLines {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)

        return HomeAssistantPersonaLines(
            response: HomeAssistantPersonaResponseLines(
                metric: [profile.summary],
                list: [profile.summary],
                comparison: [profile.summary],
                message: [profile.summary]
            ),
            noData: [profile.noDataSubtitle],
            unresolvedPrompt: [profile.unresolvedPromptSubtitle],
            greeting: [profile.greetingSubtitle],
            followUpLeads: ["Next:"]
        )
    }
}

private struct HomeAssistantPersonaResponseLines: Decodable {
    let metric: [String]
    let list: [String]
    let comparison: [String]
    let message: [String]

    func lines(for kind: HomeAnswerKind) -> [String] {
        switch kind {
        case .metric:
            return metric
        case .list:
            return list
        case .comparison:
            return comparison
        case .message:
            return message
        }
    }
}

private final class HomeAssistantPersonaBundleMarker {}
