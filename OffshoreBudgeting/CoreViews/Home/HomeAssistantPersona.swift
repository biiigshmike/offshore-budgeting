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

struct HomeAssistantPersonaResponseRules: Equatable {
    let isMarinaEnabled: Bool
    let rulesFooterLine: String

    static let legacy = HomeAssistantPersonaResponseRules(
        isMarinaEnabled: false,
        rulesFooterLine: ""
    )

    static let marina = HomeAssistantPersonaResponseRules(
        isMarinaEnabled: true,
        rulesFooterLine: "Rules/Model: MarinaResponseRules v1.0 (non-LLM)"
    )
}

struct HomeAssistantPersonaSeedContext: Equatable {
    let actorID: String
    let intentKey: String
    let monthKey: String

    static func from(
        actorID: String,
        intentKey: String,
        referenceDate: Date,
        calendar: Calendar = .current
    ) -> HomeAssistantPersonaSeedContext {
        let components = calendar.dateComponents([.year, .month], from: referenceDate)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let monthKey = String(format: "%04d%02d", year, month)

        return HomeAssistantPersonaSeedContext(
            actorID: actorID,
            intentKey: intentKey,
            monthKey: monthKey
        )
    }
}

struct HomeAssistantPersonaFooterContext: Equatable {
    let dataWindow: String
    let sources: [String]
    let queries: [String]
}

struct HomeAssistantPersonaEchoContext: Equatable {
    let cardName: String?
    let categoryName: String?
    let incomeSourceName: String?
}

struct HomeAssistantPersonaFormatter {
    typealias VariantIndexPicker = (_ upperBound: Int, _ key: String) -> Int

    private let variantIndexPicker: VariantIndexPicker
    private let copyLibrary: HomeAssistantPersonaCopyLibrary
    private let responseRules: HomeAssistantPersonaResponseRules
    private let cooldownSessionID: String

    init(
        sessionSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
        responseRules: HomeAssistantPersonaResponseRules = .legacy,
        cooldownSessionID: String = UUID().uuidString
    ) {
        self.variantIndexPicker = { upperBound, key in
            HomeAssistantPersonaFormatter.stableIndex(
                upperBound: upperBound,
                key: key,
                sessionSeed: sessionSeed
            )
        }
        self.copyLibrary = .defaultLibrary
        self.responseRules = responseRules
        self.cooldownSessionID = cooldownSessionID
    }

    init(
        variantIndexPicker: @escaping VariantIndexPicker,
        responseRules: HomeAssistantPersonaResponseRules = .legacy,
        cooldownSessionID: String = UUID().uuidString
    ) {
        self.variantIndexPicker = variantIndexPicker
        self.copyLibrary = .defaultLibrary
        self.responseRules = responseRules
        self.cooldownSessionID = cooldownSessionID
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
        let profile = HomeAssistantPersonaCatalog.profile(for: personaID)
        let greetingLine = randomLine(
            from: greetingLines(for: personaID),
            key: "greeting.reply.\(personaID.rawValue)"
        )

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: nil,
            title: profile.greetingTitle,
            subtitle: mergedSentencePair(greetingLine, profile.greetingSubtitle),
            primaryValue: nil,
            rows: []
        )
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
        personaID: HomeAssistantPersonaID,
        seedContext: HomeAssistantPersonaSeedContext? = nil,
        footerContext: HomeAssistantPersonaFooterContext? = nil,
        echoContext: HomeAssistantPersonaEchoContext? = nil
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
        let personaLine = personaResponseLine(
            from: rawAnswer,
            personaID: personaID,
            seedContext: seedContext
        )
        let subtitle = composedSubtitle(
            personaLine: personaLine,
            factualSubtitle: factualSubtitle,
            factualLeadLine: responseRules.isMarinaEnabled
                ? factsLeadLine(for: rawAnswer.kind, personaID: personaID, seedContext: seedContext, answerID: rawAnswer.id)
                : nil,
            rulesFooterLine: responseRules.isMarinaEnabled ? responseRules.rulesFooterLine : nil,
            footerContext: responseRules.isMarinaEnabled ? footerContext : nil,
            userEchoLine: responseRules.isMarinaEnabled
                ? userEchoLine(from: userPrompt, seedContext: seedContext, echoContext: echoContext)
                : nil
        )

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
                title: followUpTitle(action: action),
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

    private func personaResponseLine(
        from answer: HomeAnswer,
        personaID: HomeAssistantPersonaID,
        seedContext: HomeAssistantPersonaSeedContext?
    ) -> String? {
        if responseRules.isMarinaEnabled, let statusBand = statusBand(from: answer) {
            let statusLine = randomLine(
                from: statusResponseLines(for: statusBand),
                key: statusResponseLineKey(
                    personaID: personaID,
                    statusBand: statusBand,
                    answerID: answer.id,
                    seedContext: seedContext
                )
            )
            if let statusLine {
                return statusLine
            }
        }

        return randomLine(
            from: responseLines(for: answer.kind, personaID: personaID),
            key: responseLineKey(
                personaID: personaID,
                answerKind: answer.kind,
                answerID: answer.id,
                seedContext: seedContext
            )
        )
    }

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

    // MARK: - Helpers

    private func followUpTitle(action: String) -> String {
        return action
    }

    private func randomLine(from lines: [String], key: String) -> String? {
        guard lines.isEmpty == false else { return nil }
        let preferredIndex = min(max(0, variantIndexPicker(lines.count, key)), lines.count - 1)

        guard responseRules.isMarinaEnabled, shouldApplyCooldown(for: key) else {
            return lines[preferredIndex]
        }

        let resolvedIndex = HomeAssistantPersonaCooldownStore.shared.resolveIndex(
            preferredIndex: preferredIndex,
            upperBound: lines.count,
            sessionID: cooldownSessionID,
            key: cooldownKey(for: key)
        )
        return lines[resolvedIndex]
    }

    private func shouldApplyCooldown(for key: String) -> Bool {
        key.hasPrefix("response.") || key.hasPrefix("echo.") || key.hasPrefix("factslead.")
    }

    private func cooldownKey(for key: String) -> String {
        let components = key.split(separator: ".")
        let trimmed = components.filter { token in
            UUID(uuidString: String(token)) == nil
        }
        return trimmed.joined(separator: ".")
    }

    private func responseLineKey(
        personaID: HomeAssistantPersonaID,
        answerKind: HomeAnswerKind,
        answerID: UUID,
        seedContext: HomeAssistantPersonaSeedContext?
    ) -> String {
        guard responseRules.isMarinaEnabled, let seedContext else {
            return "response.\(personaID.rawValue).\(answerKind.rawValue).\(answerID.uuidString)"
        }

        return "response.\(personaID.rawValue).\(answerKind.rawValue).\(seedContext.intentKey).\(seedContext.monthKey).\(seedContext.actorID)"
    }

    private func statusResponseLineKey(
        personaID: HomeAssistantPersonaID,
        statusBand: PersonaStatusBand,
        answerID: UUID,
        seedContext: HomeAssistantPersonaSeedContext?
    ) -> String {
        guard responseRules.isMarinaEnabled, let seedContext else {
            return "response.\(personaID.rawValue).status.\(statusBand.rawValue).\(answerID.uuidString)"
        }

        return "response.\(personaID.rawValue).status.\(statusBand.rawValue).\(seedContext.intentKey).\(seedContext.monthKey).\(seedContext.actorID)"
    }

    private func statusBand(from answer: HomeAnswer) -> PersonaStatusBand? {
        guard responseRules.isMarinaEnabled else { return nil }
        guard let statusRow = answer.rows.first(where: { $0.title.caseInsensitiveCompare("Status") == .orderedSame }) else {
            return nil
        }

        let value = statusRow.value.lowercased()
        if value.contains("good") {
            return .good
        }
        if value.contains("ok") || value.contains("stable") {
            return .ok
        }
        if value.contains("watch") || value.contains("bad") {
            return .watch
        }
        if value.contains("baseline") || value.contains("no activity") {
            return .baseline
        }

        return nil
    }

    private func statusResponseLines(for band: PersonaStatusBand) -> [String] {
        switch band {
        case .good:
            return [
                "You made progress against last period. Keep this exact energy.",
                "This is a strong month-over-month move, and you earned it.",
                "Great signal here. You are steering this month well.",
                "You are trending in the right direction. Protect this rhythm."
            ]
        case .ok:
            return [
                "You are steady right now, which is a solid base.",
                "This is stable and manageable. Small tweaks will go far.",
                "You are in an okay zone this month, with room to optimize.",
                "This is controlled spending, not chaos. Nice checkpoint."
            ]
        case .watch:
            return [
                "This month needs a tighter pass, and we can do that quickly.",
                "You are above last period, so this is a good time to intervene.",
                "Watch zone, bestie. Let us trim the biggest driver first.",
                "This is recoverable, but we should act before next cycle."
            ]
        case .baseline:
            return [
                "Baseline month so far. As data lands, this gets sharper.",
                "Early read only right now, but your structure is in place.",
                "This is a starter snapshot. We will firm it up with more activity.",
                "Not enough prior signal yet, so I am keeping this read conservative."
            ]
        }
    }

    private func composedSubtitle(
        personaLine: String?,
        factualSubtitle: String?,
        factualLeadLine: String?,
        rulesFooterLine: String?,
        footerContext: HomeAssistantPersonaFooterContext?,
        userEchoLine: String?
    ) -> String? {
        let expressivePersonaLine = mergedSentencePair(userEchoLine, personaLine)
        let subtitleBody: String?

        switch (expressivePersonaLine, factualSubtitle) {
        case let (.some(persona), .some(facts)):
            if let factualLeadLine, factualLeadLine.isEmpty == false {
                subtitleBody = "\(persona)\n\n\(factualLeadLine)\nSources: \(facts)"
            } else {
                subtitleBody = "\(persona)\n\nSources: \(facts)"
            }
        case let (.some(persona), .none):
            subtitleBody = persona
        case let (.none, .some(facts)):
            if let factualLeadLine, factualLeadLine.isEmpty == false {
                subtitleBody = "\(factualLeadLine)\nSources: \(facts)"
            } else {
                subtitleBody = "Sources: \(facts)"
            }
        case (.none, .none):
            subtitleBody = nil
        }

        guard
            let rulesFooter = rulesFooterText(footerContext: footerContext, rulesFooterLine: rulesFooterLine),
            rulesFooter.isEmpty == false
        else {
            return subtitleBody
        }

        if let subtitleBody {
            return "\(subtitleBody)\n\n---\n\(rulesFooter)"
        }

        return rulesFooter
    }

    private func userEchoLine(
        from prompt: String?,
        seedContext: HomeAssistantPersonaSeedContext?,
        echoContext: HomeAssistantPersonaEchoContext?
    ) -> String? {
        guard let prompt else { return nil }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let echoSeedKey = echoSeedContext(
            prompt: trimmed,
            seedContext: seedContext
        )

        if let cardName = echoContext?.cardName, cardName.isEmpty == false {
            return randomEchoLine(
                key: "echo.card.canonical.\(echoSeedKey).\(cardName.lowercased())",
                lines: [
                    "You asked about your \(cardName) card, so I focused there.",
                    "I kept this centered on your \(cardName) card.",
                    "Locked in on \(cardName) card activity since that was your ask.",
                    "I heard \(cardName) card, so that is the lane I used."
                ]
            )
        }

        if let categoryName = echoContext?.categoryName, categoryName.isEmpty == false {
            return randomEchoLine(
                key: "echo.category.canonical.\(echoSeedKey).\(categoryName.lowercased())",
                lines: [
                    "You asked about \(categoryName), so I centered the response on that.",
                    "I kept this focused on \(categoryName).",
                    "I heard \(categoryName), so this read stays in that category.",
                    "This is anchored on \(categoryName), just like you asked."
                ]
            )
        }

        if let incomeSourceName = echoContext?.incomeSourceName, incomeSourceName.isEmpty == false {
            return randomEchoLine(
                key: "echo.income.canonical.\(echoSeedKey).\(incomeSourceName.lowercased())",
                lines: [
                    "You asked about income from \(incomeSourceName), so I focused on that source.",
                    "I centered this on income from \(incomeSourceName).",
                    "Your ask was \(incomeSourceName) income, so that is what I pulled.",
                    "I kept this read on \(incomeSourceName) so it stays relevant."
                ]
            )
        }

        let lowered = trimmed.lowercased()
        if lowered.contains("this month") {
            return randomEchoLine(
                key: "echo.month.\(echoSeedKey)",
                lines: [
                    "You asked about this month, so I pulled your latest read.",
                    "You wanted a month check-in, so I stayed on current-month activity.",
                    "I kept this to your this-month picture so it stays grounded.",
                    "Month snapshot mode: this is based on your latest entries."
                ]
            )
        }

        if let cardName = extractedCardName(from: trimmed) {
            return randomEchoLine(
                key: "echo.card.prompt.\(echoSeedKey).\(cardName.lowercased())",
                lines: [
                    "You asked about your \(cardName) card, so I focused there.",
                    "I kept this centered on your \(cardName) card.",
                    "This answer stays on \(cardName) card activity.",
                    "I heard \(cardName) card, so I focused on that lane."
                ]
            )
        }

        if let categoryName = extractedCategoryName(from: trimmed) {
            return randomEchoLine(
                key: "echo.category.prompt.\(echoSeedKey).\(categoryName.lowercased())",
                lines: [
                    "You asked about \(categoryName), so I centered the response on that.",
                    "I kept this focused on \(categoryName).",
                    "This read is anchored on \(categoryName).",
                    "I heard \(categoryName), so that is what I centered."
                ]
            )
        }

        if let incomeSource = extractedIncomeSource(from: trimmed) {
            return randomEchoLine(
                key: "echo.income.prompt.\(echoSeedKey).\(incomeSource.lowercased())",
                lines: [
                    "You asked about income from \(incomeSource), so I focused on that source.",
                    "I centered this on income from \(incomeSource).",
                    "This answer stays focused on \(incomeSource) income.",
                    "I heard \(incomeSource) for income, so I kept it there."
                ]
            )
        }

        if let seedContext {
            switch seedContext.intentKey {
            case HomeQueryIntent.cardSpendTotal.rawValue, HomeQueryIntent.cardVariableSpendingHabits.rawValue:
                return randomEchoLine(
                    key: "echo.intent.card.\(echoSeedKey)",
                    lines: [
                        "You asked about card activity, so I focused on card-level details.",
                        "I kept this card-focused so you can act on it quickly.",
                        "This is centered on card-level activity like you asked.",
                        "I stayed in card detail mode for this one."
                    ]
                )
            case HomeQueryIntent.incomeAverageActual.rawValue, HomeQueryIntent.incomeSourceShare.rawValue, HomeQueryIntent.incomeSourceShareTrend.rawValue:
                return randomEchoLine(
                    key: "echo.intent.income.\(echoSeedKey)",
                    lines: [
                        "You asked about income performance, so I centered this on your income data.",
                        "I kept this focused on income performance and source quality.",
                        "This response stays in income mode, grounded in your entries.",
                        "I centered this on income results so it is actionable."
                    ]
                )
            case HomeQueryIntent.categorySpendShare.rawValue, HomeQueryIntent.categorySpendShareTrend.rawValue, HomeQueryIntent.categoryPotentialSavings.rawValue, HomeQueryIntent.categoryReallocationGuidance.rawValue:
                return randomEchoLine(
                    key: "echo.intent.category.\(echoSeedKey)",
                    lines: [
                        "You asked about category-level spending, so I focused on category data.",
                        "I kept this centered on category behavior so it is easier to tune.",
                        "This is category-first so the next moves are clearer.",
                        "I focused on category-level patterns for this read."
                    ]
                )
            default:
                break
            }
        }

        let tokens = trimmed
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.isEmpty == false }

        guard tokens.isEmpty == false else { return nil }
        let snippet = tokens.prefix(8).joined(separator: " ")
        return randomEchoLine(
            key: "echo.prompt.snippet.\(echoSeedKey)",
            lines: [
                "You asked: \"\(snippet)\".",
                "I used your prompt \"\(snippet)\" as the focus.",
                "\"\(snippet)\" is what I keyed off for this response.",
                "Keeping this grounded around your ask: \"\(snippet)\"."
            ]
        )
    }

    private func randomEchoLine(key: String, lines: [String]) -> String? {
        randomLine(from: lines, key: key)
    }

    private func echoSeedContext(
        prompt: String,
        seedContext: HomeAssistantPersonaSeedContext?
    ) -> String {
        if let seedContext {
            return "\(seedContext.intentKey).\(seedContext.monthKey).\(seedContext.actorID)"
        }
        return prompt.lowercased()
    }

    private func extractedCardName(from prompt: String) -> String? {
        let lowered = prompt.lowercased()
        guard let range = lowered.range(of: " card") else { return nil }
        let prefix = prompt[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        guard prefix.isEmpty == false else { return nil }

        let fillerWords: Set<String> = ["show", "me", "my", "the", "about", "for"]
        let cleanedTokens = prefix
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { fillerWords.contains($0.lowercased()) == false }
        let tokens = Array(cleanedTokens.suffix(3))
        guard tokens.isEmpty == false else { return nil }
        return tokens.joined(separator: " ")
    }

    private func extractedCategoryName(from prompt: String) -> String? {
        let lowered = prompt.lowercased()
        let markers = ["category ", "on ", "for "]

        for marker in markers {
            guard let markerRange = lowered.range(of: marker) else { continue }
            let start = markerRange.upperBound
            let suffix = prompt[start...]
            let cleaned = suffix
                .split(whereSeparator: { $0 == "," || $0 == "." || $0 == "?" || $0 == "!" })
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let cleaned, cleaned.isEmpty == false {
                let tokens = cleaned.split(whereSeparator: \.isWhitespace).prefix(3).map(String.init)
                if tokens.isEmpty == false {
                    return tokens.joined(separator: " ")
                }
            }
        }

        return nil
    }

    private func extractedIncomeSource(from prompt: String) -> String? {
        let lowered = prompt.lowercased()
        guard lowered.contains("income") || lowered.contains("source") else { return nil }
        guard let range = lowered.range(of: "from ") else { return nil }

        let suffix = prompt[range.upperBound...]
        let cleaned = suffix
            .split(whereSeparator: { $0 == "," || $0 == "." || $0 == "?" || $0 == "!" })
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, cleaned.isEmpty == false else { return nil }
        let tokens = cleaned.split(whereSeparator: \.isWhitespace).prefix(3).map(String.init)
        guard tokens.isEmpty == false else { return nil }
        return tokens.joined(separator: " ")
    }

    private func factsLeadLine(
        for kind: HomeAnswerKind,
        personaID: HomeAssistantPersonaID,
        seedContext: HomeAssistantPersonaSeedContext?,
        answerID: UUID
    ) -> String? {
        let keySeed: String
        if let seedContext {
            keySeed = "\(seedContext.intentKey).\(seedContext.monthKey).\(seedContext.actorID)"
        } else {
            keySeed = answerID.uuidString
        }
        let key = "factslead.\(personaID.rawValue).\(kind.rawValue).\(keySeed)"

        let lines: [String]
        switch kind {
        case .metric:
            lines = [
                "Here is the direct read:",
                "Numbers check:",
                "This is where you stand right now:",
                "Snapshot from your data:",
                "Grounded summary:"
            ]
        case .list:
            lines = [
                "Here is what surfaced:",
                "Priority list from your data:",
                "Main items to watch:",
                "Current ranking from your entries:",
                "This is the clean list:"
            ]
        case .comparison:
            lines = [
                "Month-over-month signal:",
                "Change summary:",
                "Here is the trend read:",
                "Comparison snapshot:",
                "Direction check:"
            ]
        case .message:
            lines = [
                "Current system status:",
                "What I can confirm now:",
                "Here is the quick status:",
                "Direct update:",
                "Current read:"
            ]
        }

        return randomLine(from: lines, key: key)
    }

    private func rulesFooterText(
        footerContext: HomeAssistantPersonaFooterContext?,
        rulesFooterLine: String?
    ) -> String? {
        guard let rulesFooterLine, rulesFooterLine.isEmpty == false else {
            return nil
        }

        guard let footerContext else {
            return rulesFooterLine
        }

        let sourcesText = footerContext.sources.joined(separator: ", ")
        let queriesText = footerContext.queries.joined(separator: ", ")
        return """
        Data window: \(footerContext.dataWindow)
        Sources: \(sourcesText)
        Queries: \(queriesText)
        \(rulesFooterLine)
        """
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

private enum PersonaStatusBand: String {
    case good
    case ok
    case watch
    case baseline
}

private final class HomeAssistantPersonaCooldownStore {
    static let shared = HomeAssistantPersonaCooldownStore()

    private let lock = NSLock()
    private var recentIndexesByKey: [String: [Int]] = [:]

    private init() {}

    func resolveIndex(
        preferredIndex: Int,
        upperBound: Int,
        sessionID: String,
        key: String
    ) -> Int {
        guard upperBound > 0 else { return 0 }

        let scopedKey = "\(sessionID)|\(key)"
        lock.lock()
        defer { lock.unlock() }

        let history = recentIndexesByKey[scopedKey] ?? []
        let blocked = Set(history.suffix(2))

        let resolvedIndex: Int
        if blocked.contains(preferredIndex) == false {
            resolvedIndex = preferredIndex
        } else {
            resolvedIndex = firstUnblockedIndex(
                upperBound: upperBound,
                blocked: blocked,
                fallback: preferredIndex
            )
        }

        var updated = history
        updated.append(resolvedIndex)
        if updated.count > 10 {
            updated.removeFirst(updated.count - 10)
        }
        recentIndexesByKey[scopedKey] = updated
        return resolvedIndex
    }

    private func firstUnblockedIndex(
        upperBound: Int,
        blocked: Set<Int>,
        fallback: Int
    ) -> Int {
        guard blocked.count < upperBound else { return fallback }
        for candidate in 0..<upperBound where blocked.contains(candidate) == false {
            return candidate
        }
        return fallback
    }
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
        let resourceNames = [
            "AssistantPersonaCopy",
            "MarinaResponses"
        ]
        let candidates = [
            Bundle.main,
            Bundle(for: HomeAssistantPersonaBundleMarker.self)
        ]

        for bundle in candidates {
            for resourceName in resourceNames {
                if let url = bundle.url(forResource: resourceName, withExtension: "json", subdirectory: "CoreViews/Home"),
                   let data = try? Data(contentsOf: url) {
                    return data
                }

                if let url = bundle.url(forResource: resourceName, withExtension: "json"),
                   let data = try? Data(contentsOf: url) {
                    return data
                }
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
