//
//  MarinaResponseGenerationService.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/16/26.
//

import Foundation

enum MarinaResponseSurfaceSource: String, Codable, Equatable {
    case foundationModelsSurface
    case deterministicSurface
}

enum MarinaResponseGenerationRecoveryReason: String, Codable, Equatable {
    case aiOptOut
    case modelUnavailable
    case modelServiceFailed
    case malformedResponse
    case invariantViolation
    case assetsUnavailable
    case decodingFailure
    case exceededContextWindowSize
    case guardrailViolation
    case rateLimited
    case refusal
    case concurrentRequests
    case unsupportedGuide
    case unsupportedLanguageOrLocale
    case toolCallFailed
    case cancelled
    case unknown
}

enum MarinaResponseGenerationError: Error, Equatable {
    case unavailable
    case malformedResponse
    case invariantViolation
    case generationFailed(MarinaFoundationModelsErrorCategory)
}

struct MarinaResponseSuggestionCandidate: Equatable {
    let index: Int
    let title: String
    let querySummary: String
}

struct MarinaRecentResponseSummary: Equatable {
    let title: String
    let kindRaw: String
    let primaryValue: String?
}

struct MarinaAIVoiceProfile: Equatable {
    let name: String
    let allowedTone: String
    let instructionText: String

    static let marina = MarinaAIVoiceProfile(
        name: "Marina",
        allowedTone: "warm, observant, practical, lightly witty, grounded",
        instructionText: """
        You are Marina, a private budgeting assistant inside Offshore.
        Your voice is warm, observant, practical, and lightly witty. You should feel more alive than Basic Marina, but never theatrical.
        Speak like a trusted person reading the user's actual budget evidence with them: notice the useful pattern, name the practical implication, and keep it concise.
        Never invent, calculate, rename, or change totals, balances, percentages, dates, rows, entities, transactions, sources, query IDs, follow-up chips, or UI structure.
        """
    )
}

enum MarinaPresentationMode: String, Codable, Equatable {
    case foundationModelsStreaming
    case basicDeterministic
    case plainDeterministic
}

enum MarinaPresentationSurfaceKind: String, Codable, Equatable {
    case answer
    case clarification
    case help
    case noData
    case recovery
    case simulation
}

struct MarinaPresentationGrounding: Equatable {
    let userAskSummary: String
    let answerHighlights: [String]
    let insightRows: [String]
    let dateProvenanceSummary: String?
    let validationSummary: String?
    let sourceSummary: String?
    let clarificationChoices: [String]

    var promptText: String {
        let highlightsText = answerHighlights.isEmpty ? "none" : answerHighlights.joined(separator: "\n")
        let insightText = insightRows.isEmpty ? "none" : insightRows.joined(separator: "\n")
        let choicesText = clarificationChoices.isEmpty ? "none" : clarificationChoices.joined(separator: ", ")

        return """
        User ask summary: \(userAskSummary)
        Answer highlights:
        \(highlightsText)
        Insight rows:
        \(insightText)
        Date/provenance: \(dateProvenanceSummary ?? "none")
        Validation: \(validationSummary ?? "none")
        Source summary: \(sourceSummary ?? "none")
        Clarification choices: \(choicesText)
        """
    }
}

struct MarinaPresentationGroundingBuilder {
    func build(
        userPrompt: String,
        answer: HomeAnswer,
        surfaceKind: MarinaPresentationSurfaceKind,
        dateWindow: String?,
        provenance: String?,
        validationOutcomeSummary: String?,
        sourceSummary: String?,
        clarificationChoices: [String]
    ) -> MarinaPresentationGrounding {
        MarinaPresentationGrounding(
            userAskSummary: userAskSummary(userPrompt, surfaceKind: surfaceKind),
            answerHighlights: answerHighlights(answer, surfaceKind: surfaceKind),
            insightRows: insightRows(answer.rows),
            dateProvenanceSummary: dateProvenanceSummary(dateWindow: dateWindow, provenance: provenance),
            validationSummary: validationOutcomeSummary?.nilIfBlankForMarinaPresentation,
            sourceSummary: sourceSummary?.nilIfBlankForMarinaPresentation,
            clarificationChoices: clarificationChoices.prefix(6).map {
                trimmedOneLine($0, limit: 80)
            }
        )
    }

    private func userAskSummary(
        _ userPrompt: String,
        surfaceKind: MarinaPresentationSurfaceKind
    ) -> String {
        let trimmed = trimmedOneLine(userPrompt, limit: 120)
        if trimmed.isEmpty == false {
            return trimmed
        }

        switch surfaceKind {
        case .answer:
            return "Answer the current budget question."
        case .clarification:
            return "Ask for the missing detail needed to answer safely."
        case .help:
            return "Explain what Marina can help with."
        case .noData:
            return "Explain that no matching budget data was found."
        case .recovery:
            return "Offer the safest next step."
        case .simulation:
            return "Explain the deterministic what-if result."
        }
    }

    private func answerHighlights(
        _ answer: HomeAnswer,
        surfaceKind: MarinaPresentationSurfaceKind
    ) -> [String] {
        var highlights: [String] = [
            "Surface: \(surfaceKind.rawValue)",
            "Title: \(trimmedOneLine(answer.title, limit: 90))"
        ]

        if let primaryValue = answer.primaryValue?.nilIfBlankForMarinaPresentation {
            highlights.append("Primary value: \(trimmedOneLine(primaryValue, limit: 80))")
        }

        if let subtitle = answer.subtitle?.nilIfBlankForMarinaPresentation {
            highlights.append("Deterministic subtitle: \(trimmedOneLine(subtitle, limit: 140))")
        }

        switch answer.attachment {
        case let .cardSummary(summary)?:
            highlights.append(
                "Card summary: \(trimmedOneLine(summary.title, limit: 60)); period \(summary.dateRangeSubtitle); total \(CurrencyFormatter.string(from: summary.total)); planned \(CurrencyFormatter.string(from: summary.plannedTotal)); variable \(CurrencyFormatter.string(from: summary.variableTotal))"
            )
        case let .entitySummary(summary)?:
            let rows = summary.rows.prefix(4).map {
                "\(trimmedOneLine($0.title, limit: 28)) \(trimmedOneLine($0.value, limit: 46))"
            }.joined(separator: "; ")
            let value = summary.primaryValue.map { "; value \(trimmedOneLine($0, limit: 50))" } ?? ""
            highlights.append(
                "Entity summary: \(summary.objectType.rawValue); \(trimmedOneLine(summary.title, limit: 60)); \(trimmedOneLine(summary.subtitle, limit: 50))\(value)\(rows.isEmpty ? "" : "; rows \(rows)")"
            )
        case let .rowList(rowList)?:
            let rows = rowList.rows.prefix(5).map {
                "\(trimmedOneLine($0.title, limit: 34)): \(trimmedOneLine($0.value, limit: 50))"
            }.joined(separator: " | ")
            highlights.append(
                "Row list attachment: \(rowList.family.rawValue); \(rowList.rows.count) rows\(rows.isEmpty ? "" : "; \(rows)")"
            )
        case let .metricSummary(summary)?:
            highlights.append(polishedAttachmentHighlight("Metric summary", title: summary.title, primaryValue: summary.primaryValue, rows: summary.rows))
        case let .comparisonSummary(summary)?:
            let delta = summary.deltaValue.map { "; delta \(trimmedOneLine($0, limit: 40))" } ?? ""
            highlights.append(
                "Comparison attachment: \(trimmedOneLine(summary.title, limit: 60)); \(trimmedOneLine(summary.primaryLabel, limit: 30)) \(trimmedOneLine(summary.primaryValue, limit: 40)); \(trimmedOneLine(summary.comparisonLabel, limit: 30)) \(trimmedOneLine(summary.comparisonValue, limit: 40))\(delta)"
            )
        case let .breakdownList(list)?:
            highlights.append(polishedAttachmentHighlight("Breakdown attachment", title: list.title, primaryValue: list.primaryValue, rows: list.rows))
        case let .trendChart(chart)?:
            let points = chart.points.prefix(5).map {
                "\(trimmedOneLine($0.label, limit: 32)): \(trimmedOneLine($0.renderedValue, limit: 40))"
            }.joined(separator: " | ")
            highlights.append("Trend attachment: \(trimmedOneLine(chart.title, limit: 60)); \(chart.points.count) points\(points.isEmpty ? "" : "; \(points)")")
        case let .formulaContract(contract)?:
            highlights.append(polishedAttachmentHighlight("Formula contract attachment", title: contract.title, primaryValue: contract.status, rows: contract.rows))
        case let .clarification(clarification)?:
            highlights.append(polishedAttachmentHighlight("Clarification attachment", title: clarification.title, primaryValue: nil, rows: clarification.rows))
        case let .deadEnd(deadEnd)?:
            highlights.append(polishedAttachmentHighlight("Dead-end attachment", title: deadEnd.title, primaryValue: nil, rows: deadEnd.rows))
        case let .genericSummary(summary)?:
            highlights.append(polishedAttachmentHighlight("Generic summary attachment", title: summary.title, primaryValue: summary.primaryValue, rows: summary.rows))
        case .inlineCreateForm?, nil:
            break
        }

        let visibleRows = answer.rows.filter { $0.role != .trace && $0.role != .contract }.prefix(5).map {
            "\(trimmedOneLine($0.title, limit: 40)): \(trimmedOneLine($0.value, limit: 90))"
        }
        if visibleRows.isEmpty == false {
            highlights.append("Visible rows: \(visibleRows.joined(separator: " | "))")
        }

        return Array(highlights.prefix(8))
    }

    private func polishedAttachmentHighlight(
        _ prefix: String,
        title: String,
        primaryValue: String?,
        rows: [MarinaDisplayRow]
    ) -> String {
        let primary = primaryValue.map { "; primary \(trimmedOneLine($0, limit: 60))" } ?? ""
        let rowText = rows.prefix(5).map {
            "\(trimmedOneLine($0.title, limit: 34)): \(trimmedOneLine($0.value, limit: 50))"
        }.joined(separator: " | ")
        return "\(prefix): \(trimmedOneLine(title, limit: 60))\(primary)\(rowText.isEmpty ? "" : "; \(rowText)")"
    }

    private func insightRows(_ rows: [HomeAnswerRow]) -> [String] {
        let insightTitles = [
            "status",
            "compared with",
            "main driver",
            "pattern",
            "watch",
            "top spend driver",
            "category change",
            "card change",
            "merchant"
        ]

        return rows.compactMap { row in
            let normalizedTitle = row.title.lowercased()
            guard insightTitles.contains(where: normalizedTitle.contains) else { return nil }
            return "\(trimmedOneLine(row.title, limit: 40)): \(trimmedOneLine(row.value, limit: 120))"
        }.prefix(6).map { $0 }
    }

    private func dateProvenanceSummary(
        dateWindow: String?,
        provenance: String?
    ) -> String? {
        let parts = [
            dateWindow?.nilIfBlankForMarinaPresentation.map { "date=\($0)" },
            provenance?.nilIfBlankForMarinaPresentation.map { "provenance=\($0)" }
        ].compactMap { $0 }

        guard parts.isEmpty == false else { return nil }
        return parts.joined(separator: "; ")
    }

    private func trimmedOneLine(_ value: String, limit: Int) -> String {
        let normalized = value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        let cutoff = normalized.index(normalized.startIndex, offsetBy: max(0, limit - 1))
        return String(normalized[..<cutoff]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}

struct MarinaResponseGenerationContext: Equatable {
    let userPrompt: String
    let workspaceName: String
    let routeSourceRaw: String
    let presentationMode: MarinaPresentationMode
    let surfaceKind: MarinaPresentationSurfaceKind
    let deterministicAnswer: HomeAnswer
    let voiceProfile: MarinaAIVoiceProfile
    let presentationGrounding: MarinaPresentationGrounding?
    let groundingSummary: String?
    let allowedTone: String?
    let dateWindow: String?
    let provenance: String?
    let validationOutcomeSummary: String?
    let clarificationChoices: [String]
    let followUpCandidates: [MarinaResponseSuggestionCandidate]
    let recentResponses: [MarinaRecentResponseSummary]

    init(
        userPrompt: String,
        workspaceName: String,
        routeSourceRaw: String,
        presentationMode: MarinaPresentationMode = .foundationModelsStreaming,
        surfaceKind: MarinaPresentationSurfaceKind = .answer,
        deterministicAnswer: HomeAnswer,
        voiceProfile: MarinaAIVoiceProfile = .marina,
        presentationGrounding: MarinaPresentationGrounding? = nil,
        groundingSummary: String? = nil,
        allowedTone: String? = nil,
        dateWindow: String? = nil,
        provenance: String? = nil,
        validationOutcomeSummary: String? = nil,
        clarificationChoices: [String] = [],
        followUpCandidates: [MarinaResponseSuggestionCandidate] = [],
        recentResponses: [MarinaRecentResponseSummary] = []
    ) {
        self.userPrompt = userPrompt
        self.workspaceName = workspaceName
        self.routeSourceRaw = routeSourceRaw
        self.presentationMode = presentationMode
        self.surfaceKind = surfaceKind
        self.deterministicAnswer = deterministicAnswer
        self.voiceProfile = voiceProfile
        self.presentationGrounding = presentationGrounding
        self.groundingSummary = groundingSummary
        self.allowedTone = allowedTone
        self.dateWindow = dateWindow
        self.provenance = provenance
        self.validationOutcomeSummary = validationOutcomeSummary
        self.clarificationChoices = clarificationChoices
        self.followUpCandidates = followUpCandidates
        self.recentResponses = recentResponses
    }
}

enum MarinaFoundationSurfacePromptBuilder {
    static func instructions() -> String {
        """
        Prompt version: \(MarinaFoundationPromptVersion.presentation.rawValue)
        OS/model band: \(MarinaFoundationModelBand.current.rawValue)
        Locale: \(Locale.current.identifier)

        \(MarinaAIVoiceProfile.marina.instructionText)

        Rules:
        - This pass is presentation only. The app has already routed, validated, fetched, and calculated the answer.
        - Do not compute, change, or invent totals, balances, percentages, dates, rows, entities, transactions, or sources.
        - Do not change attachments or native UI cards; only write the narrative subtitle around the supplied facts.
        - Use only the deterministic facts in the prompt.
        - Preserve the user's workspace boundary.
        - Keep the response to one or two natural sentences unless asking a clarification.
        - Surface kind controls the job: answer explains a result, clarification asks one question, help explains capabilities, noData names the empty result plainly, recovery gives the safest next step, and simulation explains a deterministic what-if.
        - If rows include Status, Compared With, Main Driver, Pattern, or Watch, use them as insight context, not as new calculations.
        - If clarification choices are provided, rewrite only the clarification question; do not add or remove choices.
        - Do not rewrite follow-up suggestions or mention chip indexes.
        - Avoid generic stock phrases when a concrete fact is available.
        - Return plain text only: no JSON, markdown tables, labels, debug metadata, or internal rules.
        """
    }

    static func prompt(context: MarinaResponseGenerationContext) -> String {
        let answer = context.deterministicAnswer
        let rows = answer.rows.prefix(8).enumerated().map { index, row in
            "\(index + 1). \(row.title): \(row.value)"
        }.joined(separator: "\n")
        let recent = context.recentResponses.prefix(3).map {
            "\($0.kindRaw): \($0.title)\($0.primaryValue.map { " \($0)" } ?? "")"
        }.joined(separator: "\n")
        let grounding = context.presentationGrounding?.promptText ?? """
        User ask summary: \(context.userPrompt)
        Answer highlights:
        \(context.groundingSummary ?? "none")
        Insight rows:
        none
        Date/provenance: \(context.dateWindow ?? "none")
        Validation: \(context.validationOutcomeSummary ?? "none")
        Source summary: \(context.groundingSummary ?? "none")
        Clarification choices: \(context.clarificationChoices.isEmpty ? "none" : context.clarificationChoices.joined(separator: ", "))
        """

        return """
        User prompt: \(context.userPrompt)
        Workspace: \(context.workspaceName)
        Route/source: \(context.routeSourceRaw)
        Presentation mode: \(context.presentationMode.rawValue)
        Surface kind: \(context.surfaceKind.rawValue)
        Voice: \(context.voiceProfile.name)
        Allowed tone: \(context.allowedTone ?? context.voiceProfile.allowedTone)

        Deterministic grounding:
        \(grounding)

        Deterministic answer:
        kind: \(answer.kind.rawValue)
        title: \(answer.title)
        subtitle: \(answer.subtitle ?? "none")
        primaryValue: \(answer.primaryValue ?? "none")
        rows:
        \(rows.isEmpty ? "none" : rows)

        Clarification choices:
        \(context.clarificationChoices.isEmpty ? "none" : context.clarificationChoices.joined(separator: ", "))

        Recent context:
        \(recent.isEmpty ? "none" : recent)

        Return only the text that should become the narrative subtitle. For clarifications, return only the clarification question text. Do not return JSON, markdown tables, labels, chip indexes, title text, or follow-up suggestions.
        """
    }
}

struct MarinaGeneratedSuggestionRewrite: Equatable {
    let candidateIndex: Int
    let title: String
}

struct MarinaGeneratedSurfaceResponse: Equatable {
    let titleOverride: String?
    let narrativeSubtitle: String?
    let clarificationMessage: String?
    let suggestionRewrites: [MarinaGeneratedSuggestionRewrite]

    init(
        titleOverride: String? = nil,
        narrativeSubtitle: String? = nil,
        clarificationMessage: String? = nil,
        suggestionRewrites: [MarinaGeneratedSuggestionRewrite] = []
    ) {
        self.titleOverride = titleOverride?.nilIfBlank
        self.narrativeSubtitle = narrativeSubtitle?.nilIfBlank
        self.clarificationMessage = clarificationMessage?.nilIfBlank
        self.suggestionRewrites = suggestionRewrites
    }
}

typealias MarinaResponsePartialTextHandler = @MainActor @Sendable (String) -> Void

protocol MarinaResponseGenerating {
    func generateSurfaceResponse(
        context: MarinaResponseGenerationContext,
        onPartialText: MarinaResponsePartialTextHandler?
    ) async throws -> MarinaGeneratedSurfaceResponse
}

extension MarinaResponseGenerating {
    func generateSurfaceResponse(
        context: MarinaResponseGenerationContext
    ) async throws -> MarinaGeneratedSurfaceResponse {
        try await generateSurfaceResponse(context: context, onPartialText: nil)
    }
}

struct MarinaResponseSurfaceApplication: Equatable {
    let answer: HomeAnswer
    let followUpSuggestions: [MarinaSuggestion]
}

struct MarinaResponseSurfaceRequest: Equatable {
    let context: MarinaResponseGenerationContext
    let deterministicApplication: MarinaResponseSurfaceApplication
}

enum MarinaResponseSurfaceRequestFactory {
    static func make(
        userPrompt: String,
        workspaceName: String,
        routeSourceRaw: String,
        generationBaseAnswer: HomeAnswer,
        deterministicApplication: MarinaResponseSurfaceApplication,
        presentationMode: MarinaPresentationMode = .foundationModelsStreaming,
        surfaceKind: MarinaPresentationSurfaceKind = .answer,
        voiceProfile: MarinaAIVoiceProfile = .marina,
        presentationGrounding: MarinaPresentationGrounding? = nil,
        groundingSummary: String? = nil,
        allowedTone: String? = nil,
        dateWindow: String? = nil,
        provenance: String? = nil,
        validationOutcomeSummary: String? = nil,
        clarificationChoices: [String] = [],
        followUpCandidates: [MarinaResponseSuggestionCandidate] = [],
        recentResponses: [MarinaRecentResponseSummary] = []
    ) -> MarinaResponseSurfaceRequest {
        MarinaResponseSurfaceRequest(
            context: MarinaResponseGenerationContext(
                userPrompt: userPrompt,
                workspaceName: workspaceName,
                routeSourceRaw: routeSourceRaw,
                presentationMode: presentationMode,
                surfaceKind: surfaceKind,
                deterministicAnswer: generationBaseAnswer,
                voiceProfile: voiceProfile,
                presentationGrounding: presentationGrounding,
                groundingSummary: groundingSummary,
                allowedTone: allowedTone,
                dateWindow: dateWindow,
                provenance: provenance,
                validationOutcomeSummary: validationOutcomeSummary,
                clarificationChoices: clarificationChoices,
                followUpCandidates: followUpCandidates,
                recentResponses: recentResponses
            ),
            deterministicApplication: deterministicApplication
        )
    }
}

struct MarinaResponseSurfaceApplicator {
    func apply(
        generated: MarinaGeneratedSurfaceResponse,
        to deterministicAnswer: HomeAnswer,
        deterministicFollowUps: [MarinaSuggestion]
    ) throws -> MarinaResponseSurfaceApplication {
        let generatedSubtitle = generated.clarificationMessage ?? generated.narrativeSubtitle

        guard let safeSubtitle = safeGeneratedSubtitle(generatedSubtitle) else {
            throw MarinaResponseGenerationError.invariantViolation
        }

        let answer = HomeAnswer(
            id: deterministicAnswer.id,
            queryID: deterministicAnswer.queryID,
            kind: deterministicAnswer.kind,
            userPrompt: deterministicAnswer.userPrompt,
            title: deterministicAnswer.title,
            subtitle: safeSubtitle,
            primaryValue: deterministicAnswer.primaryValue,
            rows: deterministicAnswer.rows,
            attachment: deterministicAnswer.attachment,
            explanation: deterministicAnswer.explanation,
            generatedAt: deterministicAnswer.generatedAt
        )

        return MarinaResponseSurfaceApplication(
            answer: answer,
            followUpSuggestions: deterministicFollowUps
        )
    }

    private func safeGeneratedSubtitle(_ subtitle: String?) -> String? {
        guard let subtitle = subtitle?.nilIfBlank else { return nil }
        let lowercased = subtitle.lowercased()
        let blockedFragments = [
            "marinaresponserules",
            "rules/model:",
            "```",
            "\"narrativesubtitle\"",
            "\"clarificationmessage\"",
            "\"titleoverride\"",
            "{",
            "}"
        ]
        guard blockedFragments.contains(where: lowercased.contains) == false else {
            return nil
        }
        return subtitle
    }

    private func rewrittenSuggestions(
        _ rewrites: [MarinaGeneratedSuggestionRewrite],
        deterministicFollowUps: [MarinaSuggestion]
    ) -> [MarinaSuggestion] {
        guard rewrites.isEmpty == false else { return deterministicFollowUps }

        var usedIndexes = Set<Int>()
        var rewritten: [MarinaSuggestion] = []

        for rewrite in rewrites {
            guard deterministicFollowUps.indices.contains(rewrite.candidateIndex),
                  usedIndexes.contains(rewrite.candidateIndex) == false else {
                continue
            }
            let original = deterministicFollowUps[rewrite.candidateIndex]
            let title = safeSuggestionTitle(rewrite.title, fallback: original.title)
            rewritten.append(
                MarinaSuggestion(
                    id: original.id,
                    title: title,
                    query: original.query,
                    promptText: original.promptText,
                    confidenceScore: original.confidenceScore,
                    reasoning: original.reasoning
                )
            )
            usedIndexes.insert(rewrite.candidateIndex)
        }

        for index in deterministicFollowUps.indices where usedIndexes.contains(index) == false {
            rewritten.append(deterministicFollowUps[index])
        }

        return rewritten
    }

    private func safeSuggestionTitle(_ generatedTitle: String, fallback: String) -> String {
        guard let title = generatedTitle.nilIfBlank else { return fallback }
        let lowercased = title.lowercased()
        if lowercased.contains("intent=")
            || lowercased.contains("target=")
            || lowercased.contains("date=")
            || title.contains("->") {
            return fallback
        }
        return title
    }
}

struct MarinaResponseGenerationService: MarinaResponseGenerating {
    func generateSurfaceResponse(
        context: MarinaResponseGenerationContext,
        onPartialText: MarinaResponsePartialTextHandler? = nil
    ) async throws -> MarinaGeneratedSurfaceResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateWithFoundationModels(
                context: context,
                onPartialText: onPartialText
            )
        }
        throw MarinaResponseGenerationError.unavailable
        #else
        throw MarinaResponseGenerationError.unavailable
        #endif
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfBlankForMarinaPresentation: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private func generateWithFoundationModels(
    context: MarinaResponseGenerationContext,
    onPartialText: MarinaResponsePartialTextHandler?
) async throws -> MarinaGeneratedSurfaceResponse {
    do {
        let session = try MarinaFoundationModelsSessionProvider().makeSession(
            instructions: MarinaFoundationSurfacePromptBuilder.instructions()
        )
        let stream = session.streamResponse(
            to: MarinaFoundationSurfacePromptBuilder.prompt(context: context),
            options: marinaPresentationOptions(seed: marinaPresentationSeed(context: context))
        )

        var latestText = ""
        for try await partial in stream {
            latestText = partial.content
            if let text = latestText.nilIfBlank {
                await MainActor.run {
                    onPartialText?(text)
                }
            }
        }

        guard let text = latestText.nilIfBlank else {
            throw MarinaResponseGenerationError.malformedResponse
        }
        if context.clarificationChoices.isEmpty == false {
            return MarinaGeneratedSurfaceResponse(clarificationMessage: text)
        }
        return MarinaGeneratedSurfaceResponse(narrativeSubtitle: text)
    } catch let error as MarinaResponseGenerationError {
        throw error
    } catch let error as MarinaFoundationModelsServiceError {
        switch error {
        case .unavailable:
            throw MarinaResponseGenerationError.unavailable
        case .malformedResponse:
            throw MarinaResponseGenerationError.malformedResponse
        case .generationFailed(let category):
            throw MarinaResponseGenerationError.generationFailed(category)
        case .diagnosedGenerationFailure(let diagnostic):
            throw MarinaResponseGenerationError.generationFailed(diagnostic.category)
        }
    } catch {
        throw MarinaResponseGenerationError.generationFailed(.from(error))
    }
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaPresentationOptions(seed: UInt64) -> GenerationOptions {
    GenerationOptions(
        sampling: .random(probabilityThreshold: 0.9, seed: seed),
        temperature: 0.35,
        maximumResponseTokens: 360
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaPresentationSeed(context: MarinaResponseGenerationContext) -> UInt64 {
    let seedMaterial = [
        context.userPrompt,
        context.workspaceName,
        context.deterministicAnswer.id.uuidString,
        context.deterministicAnswer.primaryValue ?? ""
    ].joined(separator: "|")
    return seedMaterial.utf8.reduce(1_469_598_103_934_665_603) { partial, byte in
        (partial ^ UInt64(byte)) &* 1_099_511_628_211
    }
}
#endif
