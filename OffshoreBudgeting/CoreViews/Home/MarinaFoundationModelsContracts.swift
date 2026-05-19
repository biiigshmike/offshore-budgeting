//
//  MarinaFoundationModelsContracts.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/19/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum MarinaFoundationPromptVersion: String, Codable, Equatable, Sendable {
    case interpretationV1 = "marina.foundation.interpretation.v1"
    case presentationV1 = "marina.foundation.presentation.v1"
}

enum MarinaFoundationModelBand: String, Codable, Equatable, Sendable {
    case pre26 = "pre-26"
    case v26_0To26_3 = "26.0-26.3"
    case v26_4Plus = "26.4+"

    static var current: MarinaFoundationModelBand {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion >= 26 else { return .pre26 }
        if version.majorVersion > 26 || version.minorVersion >= 4 {
            return .v26_4Plus
        }
        return .v26_0To26_3
    }
}

enum MarinaFoundationModelsErrorCategory: String, Codable, Equatable, Sendable {
    case unavailable
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
    case malformedResponse
    case cancelled
    case unknown
}

enum MarinaFoundationRouteKind: String, Codable, Equatable, Sendable {
    case readQuery
    case lookup
    case clarification
    case unsupported
    case help
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationRouteIntent: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private reason for route choice; do not answer the user.")
    #endif
    let reasoning: String
    #if canImport(FoundationModels)
    @Guide(description: "One of readQuery, lookup, clarification, unsupported, or help.")
    #endif
    let routeRaw: String
    #if canImport(FoundationModels)
    @Guide(description: "high, medium, or low.")
    #endif
    let confidenceRaw: String
    let focusText: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationEntityMentionIntent: Codable, Equatable, Sendable {
    let roleRaw: String?
    let rawText: String?
    let typeRaw: String?
    let allowedTypeRaws: [String]
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationDateRangeIntent: Codable, Equatable, Sendable {
    let startISO8601: String?
    let endISO8601: String?
    let rawText: String?
    let periodUnitRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationReadQueryIntent: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private reason for the read-query shape; do not answer the user.")
    #endif
    let reasoning: String
    #if canImport(FoundationModels)
    @Guide(description: "Dataset or subject, such as variableExpenses, plannedExpenses, income, cards, categories, budgets, presets, savingsLedger, reconciliation, or expenseAllocations.")
    #endif
    let subjectRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Operation such as sum, average, rank, group, compare, listRows, or lookupDetails.")
    #endif
    let operationRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Measure such as spend, income, transactionAmount, transactionFrequency, remainingBudget, savings, or reconciliationBalance.")
    #endif
    let measureRaw: String?
    let includeMentions: [MarinaFoundationEntityMentionIntent]
    let excludeMentions: [MarinaFoundationEntityMentionIntent]
    let primaryDateRange: MarinaFoundationDateRangeIntent?
    let comparisonDateRange: MarinaFoundationDateRangeIntent?
    let groupingRaw: String?
    let rankingRaw: String?
    let requestedDetailRaw: String?
    let limit: Int?
    let incomeStatusRaw: String?
    let insightIntentRaw: String?
    let softTimeHintRaw: String?
    let confidenceRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationLookupIntent: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private reason for lookup target and detail choice; do not answer the user.")
    #endif
    let reasoning: String
    #if canImport(FoundationModels)
    @Guide(description: "Object types to look up, such as card, category, budget, preset, incomeSource, merchant, savingsAccount, or allocationAccount.")
    #endif
    let objectTypeRaws: [String]
    #if canImport(FoundationModels)
    @Guide(description: "The user's literal name or text to resolve deterministically.")
    #endif
    let searchText: String?
    let requestedDetailRaw: String?
    let dateRange: MarinaFoundationDateRangeIntent?
    let limit: Int?
    let confidenceRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationClarificationIntent: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private reason for what is missing or ambiguous.")
    #endif
    let reasoning: String
    let kindRaw: String?
    let message: String?
    let missingFieldRaws: [String]
    let ambiguousFieldRaws: [String]
    let patchSlotRaw: String?
    let shouldRunBestEffort: Bool
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationUnsupportedIntent: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private reason this cannot be represented as a safe read-only Marina intent.")
    #endif
    let reasoning: String
    let reasonRaw: String?
    let message: String?
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationRouteIntent {
    var routeKind: MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: routeRaw)
    }
}

extension MarinaFoundationRouteKind {
    init(routeRaw: String) {
        let normalized = routeRaw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch normalized {
        case "readquery", "read_query", "query", "analytics":
            self = .readQuery
        case "lookup", "database_lookup", "databaselookup":
            self = .lookup
        case "clarification", "clarify":
            self = .clarification
        case "help", "capability", "capabilities":
            self = .help
        default:
            self = .unsupported
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationClarificationIntent {
    var structuredClarification: MarinaStructuredClarification {
        MarinaStructuredClarification(
            subtitle: message?.nilIfBlank,
            missingFields: missingFieldRaws.compactMap(Self.missingField(from:)),
            ambiguities: ambiguousFieldRaws.compactMap { rawValue in
                Self.missingField(from: rawValue).map {
                    MarinaStructuredAmbiguity(field: $0, candidates: [])
                }
            },
            shouldRunBestEffort: shouldRunBestEffort
        )
    }

    private static func missingField(from rawValue: String) -> MarinaStructuredMissingField? {
        if let field = MarinaStructuredMissingField(rawValue: rawValue) {
            return field
        }

        switch rawValue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_")) {
        case "target", "entity", "filter":
            return .targetName
        case "date", "when":
            return .date
        case "date_range", "period":
            return .dateRange
        case "comparison", "comparison_date", "comparison_date_range":
            return .comparisonDateRange
        case "amount":
            return .amount
        default:
            return nil
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
struct MarinaFoundationModelsSessionProvider {
    private let model: SystemLanguageModel
    private let locale: Locale

    init(
        model: SystemLanguageModel = .default,
        locale: Locale = .current
    ) {
        self.model = model
        self.locale = locale
    }

    func requireAvailableModel() throws -> SystemLanguageModel {
        guard model.isAvailable else {
            throw MarinaFoundationModelsServiceError.generationFailed(.unavailable)
        }
        guard model.supportsLocale(locale) else {
            throw MarinaFoundationModelsServiceError.generationFailed(.unsupportedLanguageOrLocale)
        }
        return model
    }

    func makeSession(
        instructions: String,
        tools: [any Tool] = []
    ) throws -> LanguageModelSession {
        let model = try requireAvailableModel()
        return LanguageModelSession(
            model: model,
            tools: tools,
            instructions: instructions
        )
    }

    func prewarm(
        instructions: String,
        promptPrefix: String? = nil
    ) {
        guard let session = try? makeSession(instructions: instructions) else { return }
        if let promptPrefix {
            session.prewarm(promptPrefix: Prompt { promptPrefix })
        } else {
            session.prewarm(promptPrefix: nil)
        }
    }

    func tools(
        for route: MarinaFoundationRouteKind,
        context: MarinaLanguageRouterContext
    ) -> [any Tool] {
        switch route {
        case .readQuery, .lookup, .clarification:
            return [
                MarinaFoundationEntityLookupTool(context: context),
                MarinaFoundationCapabilityGuideTool(),
                MarinaFoundationRecentConversationSummaryTool(context: context),
                MarinaFoundationSafeQueryPreviewTool()
            ]
        case .help:
            return [
                MarinaFoundationCapabilityGuideTool()
            ]
        case .unsupported:
            return []
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaFoundationEntityLookupTool: Tool {
    let name = "entityLookup"
    let description = "Look up workspace entity names by type. Returns names only, never totals or rows."

    private let lines: [String]

    init(context: MarinaLanguageRouterContext) {
        self.lines = [
            Self.line(type: "card", values: context.cardNames),
            Self.line(type: "category", values: context.categoryNames),
            Self.line(type: "incomeSource", values: context.incomeSourceNames),
            Self.line(type: "preset", values: context.presetTitles),
            Self.line(type: "budget", values: context.budgetNames)
        ]
    }

    @Generable
    struct Arguments {
        let query: String
        let typeRaw: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let query = arguments.query
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let type = arguments.typeRaw?
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = lines.filter { line in
            let lowered = line.lowercased()
            return (query.isEmpty || lowered.contains(query))
                && (type == nil || lowered.hasPrefix("\(type!):"))
        }
        return nonEmpty(candidates.prefix(8).joined(separator: "\n"))
            ?? "No matching workspace entity names."
    }

    private static func line(type: String, values: [String]) -> String {
        let values = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .prefix(20)
            .joined(separator: ", ")
        return "\(type): \(values.isEmpty ? "none" : values)"
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaFoundationCapabilityGuideTool: Tool {
    let name = "capabilityGuide"
    let description = "Summarize supported Marina read shapes. Returns capability hints only."

    @Generable
    struct Arguments {
        let requestedShape: String
    }

    func call(arguments: Arguments) async throws -> String {
        let shape = arguments.requestedShape.lowercased()
        if shape.contains("delete") || shape.contains("edit") || shape.contains("create") {
            return "CRUD commands are not handled by Foundation Models in this pass."
        }
        if shape.contains("lookup") || shape.contains("detail") {
            return "Supported: lookup details for cards, categories, budgets, presets, income, savings, reconciliation, and ledger-like rows."
        }
        if shape.contains("compare") {
            return "Supported: deterministic comparisons for spend, category, card, merchant, and income shapes after validation."
        }
        if shape.contains("list") || shape.contains("recent") || shape.contains("last") {
            return "Supported: recent or ranked row lists after deterministic validation."
        }
        return "Supported: totals, averages, counts, ranked breakdowns, comparisons, lookup details, and typed clarifications."
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaFoundationRecentConversationSummaryTool: Tool {
    let name = "recentConversationSummary"
    let description = "Return compact prior query context for follow-up interpretation."

    private let summary: String

    init(context: MarinaLanguageRouterContext) {
        let prior = context.priorQueryContext
        guard prior.hasContext else {
            self.summary = "No prior query context."
            return
        }
        self.summary = [
            prior.lastQueryPlan?.metric.rawValue ?? prior.lastMetric?.rawValue,
            prior.lastTargetName,
            prior.lastTargetType?.rawValue,
            prior.lastPeriodUnit?.rawValue
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    @Generable
    struct Arguments {
        let includeDetails: Bool
    }

    func call(arguments _: Arguments) async throws -> String {
        summary
    }
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaFoundationSafeQueryPreviewTool: Tool {
    let name = "safeQueryPreview"
    let description = "Preview validation shape only. Never returns financial totals, balances, rows, or entity IDs."

    @Generable
    struct Arguments {
        let subjectRaw: String?
        let operationRaw: String?
        let measureRaw: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let subject = nonEmpty(arguments.subjectRaw) ?? "unknown"
        let operation = nonEmpty(arguments.operationRaw) ?? "unknown"
        let measure = nonEmpty(arguments.measureRaw) ?? "unknown"
        return "Preview only: subject=\(subject), operation=\(operation), measure=\(measure). Offshore will deterministically validate and execute after model interpretation."
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationModelsErrorCategory {
    static func from(_ error: Error) -> MarinaFoundationModelsErrorCategory {
        if error is CancellationError {
            return .cancelled
        }
        if error is LanguageModelSession.ToolCallError {
            return .toolCallFailed
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .assetsUnavailable:
                return .assetsUnavailable
            case .decodingFailure:
                return .decodingFailure
            case .exceededContextWindowSize:
                return .exceededContextWindowSize
            case .guardrailViolation:
                return .guardrailViolation
            case .rateLimited:
                return .rateLimited
            case .refusal:
                return .refusal
            case .concurrentRequests:
                return .concurrentRequests
            case .unsupportedGuide:
                return .unsupportedGuide
            case .unsupportedLanguageOrLocale:
                return .unsupportedLanguageOrLocale
            @unknown default:
                return .unknown
            }
        }
        return .unknown
    }
}
#endif

nonisolated private func nonEmpty(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed?.isEmpty == false ? trimmed : nil
}
