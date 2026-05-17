//
//  MarinaResponseGenerationService.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/16/26.
//

import Foundation

enum MarinaResponseSurfaceSource: String, Codable, Equatable {
    case foundationModelsSurface
    case deterministicSurfaceFallback
}

enum MarinaResponseGenerationFallbackReason: String, Codable, Equatable {
    case aiOptOut
    case modelUnavailable
    case modelServiceFailed
    case malformedResponse
    case invariantViolation
}

enum MarinaResponseGenerationError: Error, Equatable {
    case unavailable
    case malformedResponse
    case invariantViolation
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

enum MarinaResponsePresentationMode: String, Codable, Equatable {
    case foundationModelsPersonalized
}

struct MarinaResponseGenerationContext: Equatable {
    let userPrompt: String
    let workspaceName: String
    let routeSourceRaw: String
    let presentationMode: MarinaResponsePresentationMode
    let deterministicAnswer: HomeAnswer
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
        presentationMode: MarinaResponsePresentationMode = .foundationModelsPersonalized,
        deterministicAnswer: HomeAnswer,
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
        self.deterministicAnswer = deterministicAnswer
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
        You are Marina, a private budgeting assistant inside Offshore.
        This pass is presentation only. The app has already routed, validated, fetched, and calculated the answer.

        Voice:
        - Warm, direct, and budget-bestie without sounding canned.
        - Speak like a practical person reading the user's actual budget facts with them.
        - Mention the user's ask when it helps the answer feel specific.
        - Use light personality sparingly; never turn the response into generic hype.

        Rules:
        - Do not compute, change, or invent totals, balances, percentages, dates, rows, entities, transactions, or sources.
        - Use only the deterministic facts in the prompt.
        - Preserve the user's workspace boundary.
        - Keep the response concise, natural, and specific to the facts.
        - If rows include Status, Compared With, Main Driver, Pattern, or Watch, use them as insight context, not as new calculations.
        - If clarification choices are provided, rewrite only the clarification question; do not add or remove choices.
        - Follow-up suggestions may only reference provided candidate indexes.
        - Avoid generic stock phrases when a concrete fact is available.
        """
    }

    static func prompt(context: MarinaResponseGenerationContext) -> String {
        let answer = context.deterministicAnswer
        let rows = answer.rows.prefix(8).enumerated().map { index, row in
            "\(index + 1). \(row.title): \(row.value)"
        }.joined(separator: "\n")
        let suggestions = context.followUpCandidates.map {
            "[\($0.index)] \($0.title) -> \($0.querySummary)"
        }.joined(separator: "\n")
        let recent = context.recentResponses.prefix(3).map {
            "\($0.kindRaw): \($0.title)\($0.primaryValue.map { " \($0)" } ?? "")"
        }.joined(separator: "\n")

        return """
        User prompt: \(context.userPrompt)
        Workspace: \(context.workspaceName)
        Route/source: \(context.routeSourceRaw)
        Presentation mode: \(context.presentationMode.rawValue)
        Validation: \(context.validationOutcomeSummary ?? "none")
        Date window: \(context.dateWindow ?? "none")
        Provenance: \(context.provenance ?? "none")

        Deterministic answer:
        kind: \(answer.kind.rawValue)
        title: \(answer.title)
        subtitle: \(answer.subtitle ?? "none")
        primaryValue: \(answer.primaryValue ?? "none")
        rows:
        \(rows.isEmpty ? "none" : rows)

        Clarification choices:
        \(context.clarificationChoices.isEmpty ? "none" : context.clarificationChoices.joined(separator: ", "))

        Follow-up candidates:
        \(suggestions.isEmpty ? "none" : suggestions)

        Recent context:
        \(recent.isEmpty ? "none" : recent)

        Return presentation fields only. For normal answers, provide narrativeSubtitle. For clarifications, provide clarificationMessage. For follow-ups, provide candidate indexes and rewritten chip titles only.
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

protocol MarinaResponseGenerating {
    func generateSurfaceResponse(
        context: MarinaResponseGenerationContext
    ) async throws -> MarinaGeneratedSurfaceResponse
}

struct MarinaResponseSurfaceApplication: Equatable {
    let answer: HomeAnswer
    let followUpSuggestions: [HomeAssistantSuggestion]
}

struct MarinaResponseSurfaceRequest: Equatable {
    let context: MarinaResponseGenerationContext
    let fallbackApplication: MarinaResponseSurfaceApplication
}

enum MarinaResponseSurfaceRequestFactory {
    static func make(
        userPrompt: String,
        workspaceName: String,
        routeSourceRaw: String,
        generationBaseAnswer: HomeAnswer,
        fallbackApplication: MarinaResponseSurfaceApplication,
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
                presentationMode: .foundationModelsPersonalized,
                deterministicAnswer: generationBaseAnswer,
                dateWindow: dateWindow,
                provenance: provenance,
                validationOutcomeSummary: validationOutcomeSummary,
                clarificationChoices: clarificationChoices,
                followUpCandidates: followUpCandidates,
                recentResponses: recentResponses
            ),
            fallbackApplication: fallbackApplication
        )
    }
}

struct MarinaResponseSurfaceApplicator {
    func apply(
        generated: MarinaGeneratedSurfaceResponse,
        to deterministicAnswer: HomeAnswer,
        deterministicFollowUps: [HomeAssistantSuggestion]
    ) throws -> MarinaResponseSurfaceApplication {
        let generatedSubtitle = generated.clarificationMessage ?? generated.narrativeSubtitle
        let title = generated.titleOverride ?? deterministicAnswer.title

        guard generatedSubtitle != nil || generated.titleOverride != nil || generated.suggestionRewrites.isEmpty == false else {
            throw MarinaResponseGenerationError.invariantViolation
        }

        let answer = HomeAnswer(
            id: deterministicAnswer.id,
            queryID: deterministicAnswer.queryID,
            kind: deterministicAnswer.kind,
            userPrompt: deterministicAnswer.userPrompt,
            title: title,
            subtitle: generatedSubtitle ?? deterministicAnswer.subtitle,
            primaryValue: deterministicAnswer.primaryValue,
            rows: deterministicAnswer.rows,
            attachment: deterministicAnswer.attachment,
            explanation: deterministicAnswer.explanation,
            generatedAt: deterministicAnswer.generatedAt
        )

        return MarinaResponseSurfaceApplication(
            answer: answer,
            followUpSuggestions: rewrittenSuggestions(
                generated.suggestionRewrites,
                deterministicFollowUps: deterministicFollowUps
            )
        )
    }

    private func rewrittenSuggestions(
        _ rewrites: [MarinaGeneratedSuggestionRewrite],
        deterministicFollowUps: [HomeAssistantSuggestion]
    ) -> [HomeAssistantSuggestion] {
        guard rewrites.isEmpty == false else { return deterministicFollowUps }

        var usedIndexes = Set<Int>()
        var rewritten: [HomeAssistantSuggestion] = []

        for rewrite in rewrites {
            guard deterministicFollowUps.indices.contains(rewrite.candidateIndex),
                  usedIndexes.contains(rewrite.candidateIndex) == false else {
                continue
            }
            let original = deterministicFollowUps[rewrite.candidateIndex]
            let title = safeSuggestionTitle(rewrite.title, fallback: original.title)
            rewritten.append(
                HomeAssistantSuggestion(
                    id: original.id,
                    title: title,
                    query: original.query,
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
        context: MarinaResponseGenerationContext
    ) async throws -> MarinaGeneratedSurfaceResponse {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return try await generateWithFoundationModels(context: context)
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
}

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
private struct MarinaFoundationSurfaceFlatResponse {
    let titleOverride: String?
    let narrativeSubtitle: String?
    let clarificationMessage: String?
    let suggestionIndexes: [Int]
    let suggestionTitles: [String]
}

@available(iOS 26.0, macOS 26.0, *)
private func generateWithFoundationModels(
    context: MarinaResponseGenerationContext
) async throws -> MarinaGeneratedSurfaceResponse {
    let model = SystemLanguageModel.default
    guard model.isAvailable else {
        throw MarinaResponseGenerationError.unavailable
    }

    let session = LanguageModelSession(
        model: model,
        instructions: MarinaFoundationSurfacePromptBuilder.instructions()
    )

    let response = try await session.respond(
        to: MarinaFoundationSurfacePromptBuilder.prompt(context: context),
        schema: marinaSurfaceResponseSchema(),
        includeSchemaInPrompt: true,
        options: GenerationOptions(
            sampling: .greedy,
            maximumResponseTokens: 420
        )
    )

    let flat = try makeSurfaceFlatResponse(from: response.rawContent)
    let rewrites: [MarinaGeneratedSuggestionRewrite] = flat.suggestionIndexes.enumerated().compactMap { pair in
        let offset = pair.offset
        let index = pair.element
        guard flat.suggestionTitles.indices.contains(offset),
              let title = flat.suggestionTitles[offset].nilIfBlank else {
            return nil
        }
        return MarinaGeneratedSuggestionRewrite(candidateIndex: index, title: title)
    }

    let generated = MarinaGeneratedSurfaceResponse(
        titleOverride: flat.titleOverride,
        narrativeSubtitle: flat.narrativeSubtitle,
        clarificationMessage: flat.clarificationMessage,
        suggestionRewrites: rewrites
    )

    guard generated.titleOverride != nil ||
            generated.narrativeSubtitle != nil ||
            generated.clarificationMessage != nil ||
            generated.suggestionRewrites.isEmpty == false else {
        throw MarinaResponseGenerationError.malformedResponse
    }

    return generated
}

@available(iOS 26.0, macOS 26.0, *)
private func marinaSurfaceResponseSchema() -> GenerationSchema {
    GenerationSchema(
        type: GeneratedContent.self,
        description: "Marina presentation-only response. It must not contain computed financial facts that are absent from the prompt.",
        properties: [
            .init(name: "titleOverride", description: "Optional concise title. Leave null unless it improves clarity without changing meaning.", type: String?.self),
            .init(name: "narrativeSubtitle", description: "Natural answer text grounded only in deterministic facts.", type: String?.self),
            .init(name: "clarificationMessage", description: "Natural clarification question grounded only in the provided choices.", type: String?.self),
            .init(name: "suggestionIndexes", description: "Indexes of provided follow-up candidates, in preferred order.", type: [Int].self),
            .init(name: "suggestionTitles", description: "Rewritten chip titles aligned with suggestionIndexes.", type: [String].self)
        ]
    )
}

@available(iOS 26.0, macOS 26.0, *)
private func makeSurfaceFlatResponse(from content: GeneratedContent) throws -> MarinaFoundationSurfaceFlatResponse {
    MarinaFoundationSurfaceFlatResponse(
        titleOverride: try content.value(String?.self, forProperty: "titleOverride"),
        narrativeSubtitle: try content.value(String?.self, forProperty: "narrativeSubtitle"),
        clarificationMessage: try content.value(String?.self, forProperty: "clarificationMessage"),
        suggestionIndexes: (try? content.value([Int].self, forProperty: "suggestionIndexes")) ?? [],
        suggestionTitles: (try? content.value([String].self, forProperty: "suggestionTitles")) ?? []
    )
}
#endif
