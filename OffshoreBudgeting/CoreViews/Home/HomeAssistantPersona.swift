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
    case coral
    case captainCash
    case finn
    case harper

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
                summary: "Encouraging, honest, and practical.",
                greetingTitle: "Hi, I’m Marina.",
                greetingSubtitle: "Ask me for quick answers from your budget data.",
                noDataTitle: "No activity in this range yet.",
                noDataSubtitle: "Try a different date range or add more transactions.",
                unresolvedPromptTitle: "I can help with that once I have a clearer budgeting prompt.",
                unresolvedPromptSubtitle: "Try asking about spend totals, top categories, month-over-month change, or largest transactions.",
                previewLines: [
                    "You spent $1,350 this month. Nice momentum.",
                    "Top category is Dining at $420. Want to drill into transactions?"
                ]
            )
        case .coral:
            return HomeAssistantPersonaProfile(
                id: .coral,
                displayName: "Coral",
                summary: "Calm and supportive with clear guidance.",
                greetingTitle: "Hi, I’m Coral.",
                greetingSubtitle: "I can summarize your spending and trends quickly.",
                noDataTitle: "I couldn’t find spending for that range.",
                noDataSubtitle: "Try another time window to compare activity.",
                unresolvedPromptTitle: "I can answer that with a more specific budgeting request.",
                unresolvedPromptSubtitle: "Try a prompt like \"Top 3 categories this month\" or \"Compare this month to last month.\"",
                previewLines: [
                    "This month is tracking 8% lower than last month.",
                    "Groceries and Transport are your two largest categories."
                ]
            )
        case .captainCash:
            return HomeAssistantPersonaProfile(
                id: .captainCash,
                displayName: "Captain Cash",
                summary: "Direct and no-nonsense accountability.",
                greetingTitle: "Captain Cash reporting.",
                greetingSubtitle: "Issue a budget command and I’ll return the numbers.",
                noDataTitle: "No entries found in this range.",
                noDataSubtitle: "Adjust the range and run it again.",
                unresolvedPromptTitle: "Command not recognized for budget analysis.",
                unresolvedPromptSubtitle: "Issue a concrete request: spend total, category ranking, month comparison, or largest transactions.",
                previewLines: [
                    "Total spend is $1,350. Stay on course.",
                    "Dining is running hot. Set a cap before it drifts higher."
                ]
            )
        case .finn:
            return HomeAssistantPersonaProfile(
                id: .finn,
                displayName: "Finn",
                summary: "Straightforward and friendly, with quick answers.",
                greetingTitle: "Hey, I’m Finn.",
                greetingSubtitle: "I’ll keep budget answers simple and fast.",
                noDataTitle: "Nothing showed up for that range.",
                noDataSubtitle: "Try another date range and I’ll rerun it.",
                unresolvedPromptTitle: "I didn’t catch that one yet.",
                unresolvedPromptSubtitle: "Try a short prompt like \"Spend this month\" or \"Largest 5 transactions.\"",
                previewLines: [
                    "You spent $1,350 this month.",
                    "Top 3 categories are Dining, Groceries, and Transport."
                ]
            )
        case .harper:
            return HomeAssistantPersonaProfile(
                id: .harper,
                displayName: "Harper",
                summary: "Analytical, disciplined, and detail-oriented.",
                greetingTitle: "Hello, I’m Harper.",
                greetingSubtitle: "I’ll provide concise, data-driven budget snapshots.",
                noDataTitle: "The selected range has no matching records.",
                noDataSubtitle: "Expand or shift the date range to continue analysis.",
                unresolvedPromptTitle: "That request needs tighter budgeting scope.",
                unresolvedPromptSubtitle: "Ask for a measurable result, date range, and optional limit to continue.",
                previewLines: [
                    "Spending is up 4.2% month over month.",
                    "Largest transaction is $285.40 on Utilities."
                ]
            )
        }
    }

    nonisolated static var allProfiles: [HomeAssistantPersonaProfile] {
        HomeAssistantPersonaID.allCases.map(profile(for:))
    }
}

// MARK: - Persona Store

final class HomeAssistantPersonaStore {
    nonisolated static let defaultStorageKey = "assistant.persona.id"

    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = HomeAssistantPersonaStore.defaultStorageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    func loadSelectedPersona() -> HomeAssistantPersonaID {
        guard
            let rawValue = userDefaults.string(forKey: storageKey),
            let persona = HomeAssistantPersonaID(rawValue: rawValue)
        else {
            return HomeAssistantPersonaCatalog.defaultPersona
        }

        return persona
    }

    func saveSelectedPersona(_ persona: HomeAssistantPersonaID) {
        userDefaults.set(persona.rawValue, forKey: storageKey)
    }
}

// MARK: - Persona Formatter

struct HomeAssistantPersonaFormatter {
    func greetingAnswer(for personaID: HomeAssistantPersonaID) -> HomeAnswer {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: nil,
            title: profile.greetingTitle,
            subtitle: profile.greetingSubtitle,
            primaryValue: nil,
            rows: []
        )
    }

    func personaDidChangeAnswer(
        from previousPersonaID: HomeAssistantPersonaID,
        to newPersonaID: HomeAssistantPersonaID
    ) -> HomeAnswer {
        let previous = HomeAssistantPersonaCatalog.profile(for: previousPersonaID)
        let current = HomeAssistantPersonaCatalog.profile(for: newPersonaID)

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: nil,
            title: "Assistant switched to \(current.displayName).",
            subtitle: "Changed from \(previous.displayName). \(current.summary)",
            primaryValue: nil,
            rows: []
        )
    }

    func unresolvedPromptAnswer(
        for prompt: String,
        personaID: HomeAssistantPersonaID
    ) -> HomeAnswer {
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: profile.unresolvedPromptTitle,
            subtitle: profile.unresolvedPromptSubtitle,
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
        let subtitleBase = isNoDataMessage ? profile.noDataSubtitle : rawAnswer.subtitle
        let personaLine = responseLine(for: rawAnswer.kind, personaID: personaID)
        let subtitle = mergedSubtitle(subtitleBase, with: personaLine)

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
        let prefix = followUpPrefix(for: personaID)

        switch answer.kind {
        case .metric:
            return [
                HomeAssistantSuggestion(
                    title: "\(prefix) Top 3 categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3)
                ),
                HomeAssistantSuggestion(
                    title: "Compare with last month",
                    query: HomeQuery(intent: .compareThisMonthToPreviousMonth)
                )
            ]
        case .list:
            return [
                HomeAssistantSuggestion(
                    title: "\(prefix) Spend this month",
                    query: HomeQuery(intent: .spendThisMonth)
                ),
                HomeAssistantSuggestion(
                    title: "Largest 5 transactions",
                    query: HomeQuery(intent: .largestRecentTransactions, resultLimit: 5)
                )
            ]
        case .comparison:
            return [
                HomeAssistantSuggestion(
                    title: "\(prefix) Top 5 categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5)
                ),
                HomeAssistantSuggestion(
                    title: "Largest transactions this month",
                    query: HomeQuery(intent: .largestRecentTransactions)
                )
            ]
        case .message:
            return [
                HomeAssistantSuggestion(
                    title: "\(prefix) Spend this month",
                    query: HomeQuery(intent: .spendThisMonth)
                ),
                HomeAssistantSuggestion(
                    title: "Top categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth)
                )
            ]
        }
    }

    private func followUpPrefix(for personaID: HomeAssistantPersonaID) -> String {
        switch personaID {
        case .marina:
            return "Next"
        case .coral:
            return "Try"
        case .captainCash:
            return "Run"
        case .finn:
            return "Quick"
        case .harper:
            return "Analyze"
        }
    }

    // MARK: - Helpers

    private func mergedSubtitle(_ subtitle: String?, with personaLine: String?) -> String? {
        switch (subtitle, personaLine) {
        case let (.some(base), .some(line)):
            return "\(base) • \(line)"
        case let (.some(base), .none):
            return base
        case let (.none, .some(line)):
            return line
        case (.none, .none):
            return nil
        }
    }

    private func responseLine(
        for kind: HomeAnswerKind,
        personaID: HomeAssistantPersonaID
    ) -> String? {
        switch (personaID, kind) {
        case (.marina, .metric):
            return "Clear snapshot. Keep your momentum."
        case (.marina, .list):
            return "These are the key areas to watch."
        case (.marina, .comparison):
            return "This trend is useful for next month planning."
        case (.marina, .message):
            return "I can break this down once activity lands."

        case (.coral, .metric):
            return "You have a clean read on where things stand."
        case (.coral, .list):
            return "These categories are carrying most of your spend."
        case (.coral, .comparison):
            return "A steady trend view helps with planning."
        case (.coral, .message):
            return "When new transactions appear, I can summarize them."

        case (.captainCash, .metric):
            return "Current total confirmed. Hold the line."
        case (.captainCash, .list):
            return "Biggest spend drivers identified."
        case (.captainCash, .comparison):
            return "Trend confirmed. Adjust course if needed."
        case (.captainCash, .message):
            return "No data in range. Re-run after new activity."

        case (.finn, .metric):
            return "Quick read complete."
        case (.finn, .list):
            return "Here are your top movers."
        case (.finn, .comparison):
            return "Month-to-month picture is ready."
        case (.finn, .message):
            return "Nothing in range yet, but I’m ready when it lands."

        case (.harper, .metric):
            return "Baseline established for this period."
        case (.harper, .list):
            return "Ranked output is ready for review."
        case (.harper, .comparison):
            return "Variance captured for decision-making."
        case (.harper, .message):
            return "Dataset is empty for this range."
        }
    }
}
