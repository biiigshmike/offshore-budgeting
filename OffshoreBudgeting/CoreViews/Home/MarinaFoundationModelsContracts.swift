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
    case interpretationV2 = "marina.foundation.interpretation.v2"
    case interpretationV3 = "marina.foundation.interpretation.v3"
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

enum MarinaFoundationModelsGenerationStep: String, Codable, Equatable, Sendable {
    case availability
    case typedEnvelope
    case presentation
    case prewarm
    case toolCall
    case unknown
}

struct MarinaFoundationModelsFailureDiagnostic: Codable, Equatable, Sendable {
    let category: MarinaFoundationModelsErrorCategory
    let step: MarinaFoundationModelsGenerationStep
    let availabilityReason: String?
    let debugSummary: String?

    init(
        category: MarinaFoundationModelsErrorCategory,
        step: MarinaFoundationModelsGenerationStep,
        availabilityReason: String? = nil,
        debugSummary: String? = nil
    ) {
        self.category = category
        self.step = step
        self.availabilityReason = availabilityReason
        self.debugSummary = debugSummary
    }

    var traceSummary: String {
        [
            "foundationStep=\(step.rawValue)",
            "foundationCategory=\(category.rawValue)",
            availabilityReason.map { "availability=\($0)" },
            debugSummary.map { "debug=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
    }

    var userTitle: String {
        switch category {
        case .unavailable, .assetsUnavailable:
            return "Apple Intelligence is not ready"
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence locale unsupported"
        case .decodingFailure, .malformedResponse, .unsupportedGuide:
            return "Marina could not read the typed response"
        case .guardrailViolation, .refusal:
            return "Apple Intelligence declined that request"
        case .rateLimited, .concurrentRequests:
            return "Apple Intelligence is busy"
        case .exceededContextWindowSize:
            return "That request had too much context"
        case .toolCallFailed:
            return "A Marina tool call failed"
        case .cancelled:
            return "Marina stopped reading that request"
        case .unknown:
            return "Marina could not read that yet"
        }
    }

    var userMessage: String {
        switch category {
        case .unavailable:
            return "Apple Intelligence was available enough to try, but Foundation Models reported unavailable during interpretation."
        case .assetsUnavailable:
            return "The on-device model assets are not ready yet. Try again after Apple Intelligence finishes preparing."
        case .unsupportedLanguageOrLocale:
            return "Apple Intelligence does not support the current language or locale for this request."
        case .decodingFailure, .malformedResponse:
            return "Apple Intelligence returned a shape that did not match Marina's typed contract, so Offshore did not query your financial data."
        case .unsupportedGuide:
            return "The typed guidance for this request is not supported by the local Foundation Models runtime."
        case .guardrailViolation:
            return "Apple Intelligence blocked the interpretation step before Offshore could safely query your data."
        case .refusal:
            return "Apple Intelligence refused to interpret that prompt, so Offshore did not query your data."
        case .rateLimited:
            return "Apple Intelligence is temporarily rate-limited. Try again in a moment."
        case .concurrentRequests:
            return "Apple Intelligence is already handling another request. Try again after this turn finishes."
        case .exceededContextWindowSize:
            return "The prompt plus Marina context was too large for the on-device model."
        case .toolCallFailed:
            return "A Foundation Models tool call failed. The live V2 path should avoid tools until smoke tests pass."
        case .cancelled:
            return "The interpretation task was cancelled before Offshore queried your data."
        case .unknown:
            return "The Apple Intelligence interpretation step failed before Offshore could safely query your data."
        }
    }
}

enum MarinaFoundationRouteKind: String, Codable, Equatable, Sendable {
    case readQuery
    case lookup
    case clarification
    case unsupported
    case scenario
    case help
}

protocol MarinaAIInterpreter {
    func interpretAI(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaAIIntentV2
}

enum MarinaAIIntentKindV2: String, Codable, Equatable, Sendable {
    case readQuery
    case lookup
    case clarification
    case unsupported
    case scenario
}

enum MarinaAIIntentV2: Codable, Equatable, Sendable {
    case readQuery(MarinaAIReadQueryIntentV2)
    case lookup(MarinaAILookupIntentV2)
    case clarification(MarinaAIClarificationIntentV2)
    case unsupported(MarinaAIUnsupportedIntentV2)
    case scenario(MarinaAIScenarioIntentV2)

    var kind: MarinaAIIntentKindV2 {
        switch self {
        case .readQuery:
            return .readQuery
        case .lookup:
            return .lookup
        case .clarification:
            return .clarification
        case .unsupported:
            return .unsupported
        case .scenario:
            return .scenario
        }
    }
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
    @Guide(description: "One of readQuery, lookup, clarification, unsupported, scenario, or help.")
    #endif
    let routeRaw: String
    #if canImport(FoundationModels)
    @Guide(description: "high, medium, or low.")
    #endif
    let confidenceRaw: String
    let focusText: String?
}

struct MarinaAIEntityMentionV2: Codable, Equatable, Sendable {
    let roleRaw: String?
    let rawText: String?
    let typeRaw: String?
    let allowedTypeRaws: [String]
}

struct MarinaAIDateRangeV2: Codable, Equatable, Sendable {
    let startISO8601: String?
    let endISO8601: String?
    let rawText: String?
    let periodUnitRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationIntentEnvelope: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Short private interpretation reason; never answer the user.")
    #endif
    let reasoning: String
    #if canImport(FoundationModels)
    @Guide(description: "One route: readQuery, lookup, clarification, unsupported, scenario, or help.")
    #endif
    let routeRaw: String
    #if canImport(FoundationModels)
    @Guide(description: "Primary dataset or subject, such as variableExpenses, plannedExpenses, income, cards, categories, presets, budgets, savingsLedger, reconciliation, expenseAllocations, importMerchantRules, or assistantAliasRules.")
    #endif
    let subjectRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Operation: sum, average, count, rank, compare, listRows, lookupDetails, or simulate.")
    #endif
    let operationRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Measure: spend, income, transactionAmount, transactionFrequency, presetAmount, remainingBudget, savingsMovement, reconciliationBalance, categoryShare, or count.")
    #endif
    let measureRaw: String?
    let primaryEntityName: String?
    let primaryEntityTypeRaw: String?
    let secondaryEntityName: String?
    let secondaryEntityTypeRaw: String?
    let excludeEntityName: String?
    let excludeEntityTypeRaw: String?
    let startISO8601: String?
    let endISO8601: String?
    let comparisonStartISO8601: String?
    let comparisonEndISO8601: String?
    let dateRawText: String?
    let periodUnitRaw: String?
    let groupingRaw: String?
    let rankingRaw: String?
    let requestedDetailRaw: String?
    let limit: Int?
    let incomeStatusRaw: String?
    let insightIntentRaw: String?
    let softTimeHintRaw: String?
    let scenarioRaw: String?
    let scenarioAmount: Double?
    let scenarioPercent: Double?
    let scenarioValueModeRaw: String?
    let clarificationKindRaw: String?
    let clarificationMessage: String?
    let clarificationMissingFieldRaw: String?
    let clarificationAmbiguousFieldRaw: String?
    let clarificationPatchSlotRaw: String?
    let shouldRunBestEffort: Bool
    let unsupportedReasonRaw: String?
    let unsupportedMessage: String?
    let confidenceRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationIntentEnvelopeV2: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Required route only: readQuery, lookup, clarification, unsupported, scenario, or help.")
    #endif
    let routeRaw: String
    #if canImport(FoundationModels)
    @Guide(description: "Primary dataset or subject: variableExpenses, plannedExpenses, income, incomeSeries, cards, categories, presets, budgets, savingsLedger, reconciliation, expenseAllocations, importMerchantRules, or assistantAliasRules.")
    #endif
    let subjectRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Operation: sum, average, count, rank, compare, listRows, lookupDetails, or simulate.")
    #endif
    let operationRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Measure: spend, income, transactionAmount, transactionFrequency, presetAmount, remainingBudget, savingsMovement, reconciliationBalance, categoryShare, or count.")
    #endif
    let measureRaw: String?
    let targetText: String?
    let targetTypeRaw: String?
    let secondaryTargetText: String?
    let secondaryTargetTypeRaw: String?
    let excludeTargetText: String?
    let excludeTargetTypeRaw: String?
    let startISO8601: String?
    let endISO8601: String?
    let comparisonStartISO8601: String?
    let comparisonEndISO8601: String?
    let dateRawText: String?
    let periodUnitRaw: String?
    let groupingRaw: String?
    let rankingRaw: String?
    let requestedDetailRaw: String?
    let limitRaw: String?
    let incomeStatusRaw: String?
    let insightIntentRaw: String?
    let softTimeHintRaw: String?
    let scenarioRaw: String?
    let scenarioAmountRaw: String?
    let scenarioPercentRaw: String?
    let scenarioValueModeRaw: String?
    let clarificationKindRaw: String?
    let clarificationMessage: String?
    let clarificationFieldRaw: String?
    let clarificationPatchSlotRaw: String?
    let unsupportedReasonRaw: String?
    let unsupportedMessage: String?
    let confidenceRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
#endif
struct MarinaFoundationIntentEnvelopeV3: Codable, Equatable, Sendable {
    #if canImport(FoundationModels)
    @Guide(description: "Required coarse route only: readQuery, lookup, clarification, unsupported, scenario, or help.")
    #endif
    let routeRaw: String
    #if canImport(FoundationModels)
    @Guide(description: "Short intent hint such as spendTotal, activeBudget, linkedCards, incomeActual, allocationRows, settlementRows, reconciliationBalance, savingsStatus, savingsActivity, whatIf, lookup, or unsupported.")
    #endif
    let intentRaw: String?
    #if canImport(FoundationModels)
    @Guide(description: "Exact user phrase for the main named object or filter. Leave null for generic subjects such as spending, income, budget, or savings.")
    #endif
    let targetText: String?
    let secondaryTargetText: String?
    let relationshipText: String?
    let dateText: String?
    let comparisonDateText: String?
    let amountText: String?
    let valueDirectionRaw: String?
    let confidenceRaw: String?
    let unsupportedReasonRaw: String?

    var payload: MarinaFoundationIntentEnvelopeV3Payload {
        MarinaFoundationIntentEnvelopeV3Payload(
            routeRaw: routeRaw,
            intentRaw: intentRaw,
            targetText: targetText,
            secondaryTargetText: secondaryTargetText,
            relationshipText: relationshipText,
            dateText: dateText,
            comparisonDateText: comparisonDateText,
            amountText: amountText,
            valueDirectionRaw: valueDirectionRaw,
            confidenceRaw: confidenceRaw,
            unsupportedReasonRaw: unsupportedReasonRaw
        )
    }
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

struct MarinaAIReadQueryIntentV2: Codable, Equatable, Sendable {
    let reasoning: String
    let subjectRaw: String?
    let operationRaw: String?
    let measureRaw: String?
    let includeMentions: [MarinaAIEntityMentionV2]
    let excludeMentions: [MarinaAIEntityMentionV2]
    let primaryDateRange: MarinaAIDateRangeV2?
    let comparisonDateRange: MarinaAIDateRangeV2?
    let groupingRaw: String?
    let rankingRaw: String?
    let requestedDetailRaw: String?
    let limit: Int?
    let incomeStatusRaw: String?
    let insightIntentRaw: String?
    let softTimeHintRaw: String?
    let confidenceRaw: String?
}

struct MarinaAILookupIntentV2: Codable, Equatable, Sendable {
    let reasoning: String
    let objectTypeRaws: [String]
    let searchText: String?
    let requestedDetailRaw: String?
    let dateRange: MarinaAIDateRangeV2?
    let limit: Int?
    let confidenceRaw: String?
}

struct MarinaAIClarificationIntentV2: Codable, Equatable, Sendable {
    let reasoning: String
    let kindRaw: String?
    let message: String?
    let missingFieldRaws: [String]
    let ambiguousFieldRaws: [String]
    let patchSlotRaw: String?
    let shouldRunBestEffort: Bool
}

struct MarinaAIUnsupportedIntentV2: Codable, Equatable, Sendable {
    let reasoning: String
    let reasonRaw: String?
    let message: String?
}

struct MarinaAIScenarioIntentV2: Codable, Equatable, Sendable {
    let reasoning: String
    let scenarioRaw: String?
    let targetTypeRaw: String?
    let targetName: String?
    let valueModeRaw: String?
    let amount: Double?
    let percent: Double?
    let dateRange: MarinaAIDateRangeV2?
    let confidenceRaw: String?
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaFoundationReadQueryIntent: Codable, Equatable, Sendable {
    @Guide(description: "Short private reason for the read-query shape; do not answer the user.")
    let reasoning: String
    @Guide(description: "Dataset or subject, such as variableExpenses, plannedExpenses, income, cards, categories, budgets, presets, savingsLedger, reconciliation, or expenseAllocations.")
    let subjectRaw: String?
    @Guide(description: "Operation such as sum, average, rank, group, compare, listRows, or lookupDetails.")
    let operationRaw: String?
    @Guide(description: "Measure such as spend, income, transactionAmount, transactionFrequency, remainingBudget, savings, or reconciliationBalance.")
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

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaFoundationLookupIntent: Codable, Equatable, Sendable {
    @Guide(description: "Short private reason for lookup target and detail choice; do not answer the user.")
    let reasoning: String
    @Guide(description: "Object types to look up, such as card, category, budget, preset, incomeSource, merchant, savingsAccount, or allocationAccount.")
    let objectTypeRaws: [String]
    @Guide(description: "The user's literal name or text to resolve deterministically.")
    let searchText: String?
    let requestedDetailRaw: String?
    let dateRange: MarinaFoundationDateRangeIntent?
    let limit: Int?
    let confidenceRaw: String?
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaFoundationClarificationIntent: Codable, Equatable, Sendable {
    @Guide(description: "Short private reason for what is missing or ambiguous.")
    let reasoning: String
    let kindRaw: String?
    let message: String?
    let missingFieldRaws: [String]
    let ambiguousFieldRaws: [String]
    let patchSlotRaw: String?
    let shouldRunBestEffort: Bool
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaFoundationUnsupportedIntent: Codable, Equatable, Sendable {
    @Guide(description: "Short private reason this cannot be represented as a safe read-only Marina intent.")
    let reasoning: String
    let reasonRaw: String?
    let message: String?
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaFoundationScenarioIntent: Codable, Equatable, Sendable {
    @Guide(description: "Short private reason for the what-if or scenario shape; do not answer the user.")
    let reasoning: String
    @Guide(description: "Scenario type, such as whatIf, affordability, projection, or planningDraft.")
    let scenarioRaw: String?
    let targetTypeRaw: String?
    let targetName: String?
    let valueModeRaw: String?
    let amount: Double?
    let percent: Double?
    let dateRange: MarinaFoundationDateRangeIntent?
    let confidenceRaw: String?
}
#endif

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationRouteIntent {
    var routeKind: MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: routeRaw)
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationReadQueryIntent {
    var aiIntent: MarinaAIReadQueryIntentV2 {
        MarinaAIReadQueryIntentV2(
            reasoning: reasoning,
            subjectRaw: subjectRaw,
            operationRaw: operationRaw,
            measureRaw: measureRaw,
            includeMentions: includeMentions.map(\.aiMention),
            excludeMentions: excludeMentions.map(\.aiMention),
            primaryDateRange: primaryDateRange?.aiDateRange,
            comparisonDateRange: comparisonDateRange?.aiDateRange,
            groupingRaw: groupingRaw,
            rankingRaw: rankingRaw,
            requestedDetailRaw: requestedDetailRaw,
            limit: limit,
            incomeStatusRaw: incomeStatusRaw,
            insightIntentRaw: insightIntentRaw,
            softTimeHintRaw: softTimeHintRaw,
            confidenceRaw: confidenceRaw
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationLookupIntent {
    var aiIntent: MarinaAILookupIntentV2 {
        MarinaAILookupIntentV2(
            reasoning: reasoning,
            objectTypeRaws: objectTypeRaws,
            searchText: searchText,
            requestedDetailRaw: requestedDetailRaw,
            dateRange: dateRange?.aiDateRange,
            limit: limit,
            confidenceRaw: confidenceRaw
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationClarificationIntent {
    var aiIntent: MarinaAIClarificationIntentV2 {
        MarinaAIClarificationIntentV2(
            reasoning: reasoning,
            kindRaw: kindRaw,
            message: message,
            missingFieldRaws: missingFieldRaws,
            ambiguousFieldRaws: ambiguousFieldRaws,
            patchSlotRaw: patchSlotRaw,
            shouldRunBestEffort: shouldRunBestEffort
        )
    }

    var structuredClarification: MarinaStructuredClarification {
        aiIntent.structuredClarification
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationUnsupportedIntent {
    var aiIntent: MarinaAIUnsupportedIntentV2 {
        MarinaAIUnsupportedIntentV2(
            reasoning: reasoning,
            reasonRaw: reasonRaw,
            message: message
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationScenarioIntent {
    var aiIntent: MarinaAIScenarioIntentV2 {
        MarinaAIScenarioIntentV2(
            reasoning: reasoning,
            scenarioRaw: scenarioRaw,
            targetTypeRaw: targetTypeRaw,
            targetName: targetName,
            valueModeRaw: valueModeRaw,
            amount: amount,
            percent: percent,
            dateRange: dateRange?.aiDateRange,
            confidenceRaw: confidenceRaw
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension MarinaFoundationEntityMentionIntent {
    var aiMention: MarinaAIEntityMentionV2 {
        MarinaAIEntityMentionV2(
            roleRaw: roleRaw,
            rawText: rawText,
            typeRaw: typeRaw,
            allowedTypeRaws: allowedTypeRaws
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
private extension MarinaFoundationDateRangeIntent {
    var aiDateRange: MarinaAIDateRangeV2 {
        MarinaAIDateRangeV2(
            startISO8601: startISO8601,
            endISO8601: endISO8601,
            rawText: rawText,
            periodUnitRaw: periodUnitRaw
        )
    }
}
#endif

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
        case "scenario", "whatif", "what_if", "simulation", "simulate":
            self = .scenario
        case "help", "capability", "capabilities":
            self = .help
        default:
            self = .unsupported
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationIntentEnvelope {
    var routeKind: MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: routeRaw)
    }

    var aiIntent: MarinaAIIntentV2 {
        switch routeKind {
        case .readQuery:
            return .readQuery(readQueryIntent)
        case .lookup:
            return .lookup(lookupIntent)
        case .clarification:
            return .clarification(clarificationIntent)
        case .scenario:
            return .scenario(scenarioIntent)
        case .help:
            return .unsupported(
                MarinaAIUnsupportedIntentV2(
                    reasoning: reasoning,
                    reasonRaw: "help",
                    message: unsupportedMessage?.nilIfBlank ?? "Marina can search, summarize, calculate, and run read-only what-if scenarios over this workspace."
                )
            )
        case .unsupported:
            return .unsupported(unsupportedIntent)
        }
    }

    private var readQueryIntent: MarinaAIReadQueryIntentV2 {
        MarinaAIReadQueryIntentV2(
            reasoning: reasoning,
            subjectRaw: subjectRaw,
            operationRaw: operationRaw,
            measureRaw: measureRaw,
            includeMentions: includeMentions,
            excludeMentions: excludeMentions,
            primaryDateRange: primaryDateRange,
            comparisonDateRange: comparisonDateRange,
            groupingRaw: groupingRaw,
            rankingRaw: rankingRaw,
            requestedDetailRaw: requestedDetailRaw,
            limit: normalizedLimit,
            incomeStatusRaw: incomeStatusRaw,
            insightIntentRaw: insightIntentRaw,
            softTimeHintRaw: softTimeHintRaw,
            confidenceRaw: confidenceRaw
        )
    }

    private var lookupIntent: MarinaAILookupIntentV2 {
        let objectTypeRaws = [primaryEntityTypeRaw, secondaryEntityTypeRaw, subjectRaw]
            .compactMap { $0?.nilIfBlank }
        return MarinaAILookupIntentV2(
            reasoning: reasoning,
            objectTypeRaws: objectTypeRaws,
            searchText: primaryEntityName?.nilIfBlank ?? secondaryEntityName?.nilIfBlank,
            requestedDetailRaw: requestedDetailRaw,
            dateRange: primaryDateRange,
            limit: normalizedLimit,
            confidenceRaw: confidenceRaw
        )
    }

    private var clarificationIntent: MarinaAIClarificationIntentV2 {
        MarinaAIClarificationIntentV2(
            reasoning: reasoning,
            kindRaw: clarificationKindRaw,
            message: clarificationMessage,
            missingFieldRaws: [clarificationMissingFieldRaw].compactMap { $0?.nilIfBlank },
            ambiguousFieldRaws: [clarificationAmbiguousFieldRaw].compactMap { $0?.nilIfBlank },
            patchSlotRaw: clarificationPatchSlotRaw,
            shouldRunBestEffort: shouldRunBestEffort
        )
    }

    private var unsupportedIntent: MarinaAIUnsupportedIntentV2 {
        MarinaAIUnsupportedIntentV2(
            reasoning: reasoning,
            reasonRaw: unsupportedReasonRaw,
            message: unsupportedMessage?.nilIfBlank ?? "That request is outside Marina v2's safe read-only scope."
        )
    }

    private var scenarioIntent: MarinaAIScenarioIntentV2 {
        MarinaAIScenarioIntentV2(
            reasoning: reasoning,
            scenarioRaw: scenarioRaw,
            targetTypeRaw: primaryEntityTypeRaw ?? secondaryEntityTypeRaw,
            targetName: primaryEntityName ?? secondaryEntityName,
            valueModeRaw: scenarioValueModeRaw,
            amount: scenarioAmount,
            percent: scenarioPercent,
            dateRange: primaryDateRange,
            confidenceRaw: confidenceRaw
        )
    }

    private var includeMentions: [MarinaAIEntityMentionV2] {
        [
            entityMention(name: primaryEntityName, typeRaw: primaryEntityTypeRaw, roleRaw: "primaryTarget"),
            entityMention(name: secondaryEntityName, typeRaw: secondaryEntityTypeRaw, roleRaw: "filter")
        ].compactMap { $0 }
    }

    private var excludeMentions: [MarinaAIEntityMentionV2] {
        [entityMention(name: excludeEntityName, typeRaw: excludeEntityTypeRaw, roleRaw: "excludeFilter")]
            .compactMap { $0 }
    }

    private var primaryDateRange: MarinaAIDateRangeV2? {
        guard startISO8601?.nilIfBlank != nil
                || endISO8601?.nilIfBlank != nil
                || dateRawText?.nilIfBlank != nil
                || periodUnitRaw?.nilIfBlank != nil else {
            return nil
        }
        return MarinaAIDateRangeV2(
            startISO8601: startISO8601,
            endISO8601: endISO8601,
            rawText: dateRawText,
            periodUnitRaw: periodUnitRaw
        )
    }

    private var comparisonDateRange: MarinaAIDateRangeV2? {
        guard comparisonStartISO8601?.nilIfBlank != nil || comparisonEndISO8601?.nilIfBlank != nil else {
            return nil
        }
        return MarinaAIDateRangeV2(
            startISO8601: comparisonStartISO8601,
            endISO8601: comparisonEndISO8601,
            rawText: nil,
            periodUnitRaw: periodUnitRaw
        )
    }

    private var normalizedLimit: Int? {
        guard let limit else { return nil }
        return max(1, min(limit, 25))
    }

    private func entityMention(
        name: String?,
        typeRaw: String?,
        roleRaw: String
    ) -> MarinaAIEntityMentionV2? {
        guard let name = name?.nilIfBlank else { return nil }
        return MarinaAIEntityMentionV2(
            roleRaw: roleRaw,
            rawText: name,
            typeRaw: typeRaw,
            allowedTypeRaws: [typeRaw].compactMap { $0?.nilIfBlank }
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension MarinaFoundationIntentEnvelopeV2 {
    var routeKind: MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: routeRaw)
    }

    var aiIntent: MarinaAIIntentV2 {
        switch routeKind {
        case .readQuery:
            return .readQuery(readQueryIntent)
        case .lookup:
            return .lookup(lookupIntent)
        case .clarification:
            return .clarification(clarificationIntent)
        case .scenario:
            return .scenario(scenarioIntent)
        case .help:
            return .unsupported(
                MarinaAIUnsupportedIntentV2(
                    reasoning: "",
                    reasonRaw: "help",
                    message: unsupportedMessage?.nilIfBlank ?? "Marina can search, summarize, calculate, and run read-only what-if scenarios over this workspace."
                )
            )
        case .unsupported:
            return .unsupported(unsupportedIntent)
        }
    }

    private var readQueryIntent: MarinaAIReadQueryIntentV2 {
        MarinaAIReadQueryIntentV2(
            reasoning: "",
            subjectRaw: subjectRaw,
            operationRaw: operationRaw,
            measureRaw: measureRaw,
            includeMentions: includeMentions,
            excludeMentions: excludeMentions,
            primaryDateRange: primaryDateRange,
            comparisonDateRange: comparisonDateRange,
            groupingRaw: groupingRaw,
            rankingRaw: rankingRaw,
            requestedDetailRaw: requestedDetailRaw,
            limit: normalizedLimit,
            incomeStatusRaw: incomeStatusRaw,
            insightIntentRaw: insightIntentRaw,
            softTimeHintRaw: softTimeHintRaw,
            confidenceRaw: confidenceRaw
        )
    }

    private var lookupIntent: MarinaAILookupIntentV2 {
        let objectTypeRaws = [targetTypeRaw, secondaryTargetTypeRaw, subjectRaw]
            .compactMap { $0?.nilIfBlank }
        return MarinaAILookupIntentV2(
            reasoning: "",
            objectTypeRaws: objectTypeRaws,
            searchText: targetText?.nilIfBlank ?? secondaryTargetText?.nilIfBlank,
            requestedDetailRaw: requestedDetailRaw,
            dateRange: primaryDateRange,
            limit: normalizedLimit,
            confidenceRaw: confidenceRaw
        )
    }

    private var clarificationIntent: MarinaAIClarificationIntentV2 {
        let field = clarificationFieldRaw?.nilIfBlank
        let kind = clarificationKindRaw?.nilIfBlank
        let normalizedKind = normalizedToken(kind)
        let isAmbiguous = normalizedKind?.contains("ambiguous") == true
        let isMissing = normalizedKind?.contains("missing") == true || isAmbiguous == false
        return MarinaAIClarificationIntentV2(
            reasoning: "",
            kindRaw: kind,
            message: clarificationMessage,
            missingFieldRaws: isMissing ? [field].compactMap { $0 } : [],
            ambiguousFieldRaws: isAmbiguous ? [field].compactMap { $0 } : [],
            patchSlotRaw: clarificationPatchSlotRaw,
            shouldRunBestEffort: false
        )
    }

    private var unsupportedIntent: MarinaAIUnsupportedIntentV2 {
        MarinaAIUnsupportedIntentV2(
            reasoning: "",
            reasonRaw: unsupportedReasonRaw,
            message: unsupportedMessage?.nilIfBlank ?? "That request is outside Marina v2's safe read-only scope."
        )
    }

    private var scenarioIntent: MarinaAIScenarioIntentV2 {
        MarinaAIScenarioIntentV2(
            reasoning: "",
            scenarioRaw: scenarioRaw,
            targetTypeRaw: targetTypeRaw ?? secondaryTargetTypeRaw,
            targetName: targetText ?? secondaryTargetText,
            valueModeRaw: scenarioValueModeRaw,
            amount: normalizedDouble(scenarioAmountRaw),
            percent: normalizedDouble(scenarioPercentRaw),
            dateRange: primaryDateRange,
            confidenceRaw: confidenceRaw
        )
    }

    private var includeMentions: [MarinaAIEntityMentionV2] {
        [
            entityMention(name: targetText, typeRaw: targetTypeRaw, roleRaw: "primaryTarget"),
            entityMention(name: secondaryTargetText, typeRaw: secondaryTargetTypeRaw, roleRaw: "filter")
        ].compactMap { $0 }
    }

    private var excludeMentions: [MarinaAIEntityMentionV2] {
        [entityMention(name: excludeTargetText, typeRaw: excludeTargetTypeRaw, roleRaw: "excludeFilter")]
            .compactMap { $0 }
    }

    private var primaryDateRange: MarinaAIDateRangeV2? {
        guard startISO8601?.nilIfBlank != nil
                || endISO8601?.nilIfBlank != nil
                || dateRawText?.nilIfBlank != nil
                || periodUnitRaw?.nilIfBlank != nil else {
            return nil
        }
        return MarinaAIDateRangeV2(
            startISO8601: startISO8601,
            endISO8601: endISO8601,
            rawText: dateRawText,
            periodUnitRaw: periodUnitRaw
        )
    }

    private var comparisonDateRange: MarinaAIDateRangeV2? {
        guard comparisonStartISO8601?.nilIfBlank != nil || comparisonEndISO8601?.nilIfBlank != nil else {
            return nil
        }
        return MarinaAIDateRangeV2(
            startISO8601: comparisonStartISO8601,
            endISO8601: comparisonEndISO8601,
            rawText: nil,
            periodUnitRaw: periodUnitRaw
        )
    }

    private var normalizedLimit: Int? {
        guard let value = normalizedDouble(limitRaw) else { return nil }
        return max(1, min(Int(value), 25))
    }

    private func normalizedDouble(_ rawValue: String?) -> Double? {
        guard let rawValue = rawValue?.nilIfBlank else { return nil }
        let cleaned = rawValue
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "[^0-9.\\-]+", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private func entityMention(
        name: String?,
        typeRaw: String?,
        roleRaw: String
    ) -> MarinaAIEntityMentionV2? {
        guard let name = name?.nilIfBlank else { return nil }
        return MarinaAIEntityMentionV2(
            roleRaw: roleRaw,
            rawText: name,
            typeRaw: typeRaw,
            allowedTypeRaws: [typeRaw].compactMap { $0?.nilIfBlank }
        )
    }
}

extension MarinaAIIntentV2 {
    var structuredIntent: MarinaStructuredIntent {
        switch self {
        case .readQuery(let intent):
            return intent.structuredIntent
        case .lookup(let intent):
            return intent.structuredIntent
        case .clarification(let intent):
            return .clarification(intent.structuredClarification)
        case .scenario(let intent):
            return intent.structuredIntent
        case .unsupported:
            return .unresolved
        }
    }
}

extension MarinaAIReadQueryIntentV2 {
    var structuredIntent: MarinaStructuredIntent {
        guard let action = semanticAction(from: operationRaw),
              let dataset = semanticDataset(from: subjectRaw) else {
            return .unresolved
        }

        let command = MarinaSemanticCommand(
            family: .analytics,
            action: action,
            datasets: [dataset],
            measure: semanticMeasure(from: measureRaw),
            includeFilters: semanticFilters(from: includeMentions),
            excludeFilters: semanticFilters(from: excludeMentions),
            grouping: semanticGrouping(from: groupingRaw),
            sort: semanticSort(from: rankingRaw),
            dateRange: makeDateRange(from: primaryDateRange),
            comparisonDateRange: makeDateRange(from: comparisonDateRange),
            periodUnit: periodUnit(from: primaryDateRange?.periodUnitRaw),
            limit: limit,
            incomeStatusScope: incomeStatus(from: incomeStatusRaw),
            requestedDetail: requestedDetail(from: requestedDetailRaw),
            insightIntent: insightIntent(from: insightIntentRaw),
            softTimeHint: softTimeHint(from: softTimeHintRaw)
        )
        return .semanticCommand(command)
    }
}

extension MarinaAILookupIntentV2 {
    var structuredIntent: MarinaStructuredIntent {
        guard let searchText = searchText?.nilIfBlank else {
            return .clarification(
                MarinaStructuredClarification(
                    subtitle: "I need the name or text to look up.",
                    missingFields: [.targetName],
                    ambiguities: [],
                    shouldRunBestEffort: false
                )
            )
        }

        let datasets = objectTypeRaws.compactMap(semanticDataset(from:))
        let command = MarinaSemanticCommand(
            family: .databaseLookup,
            action: .lookupDetails,
            datasets: datasets.isEmpty ? [.variableExpenses] : datasets,
            includeFilters: [
                MarinaSemanticCommandFilter(
                    rawText: searchText,
                    allowedTypes: objectTypeRaws.compactMap(entityTypeHint(from:))
                )
            ],
            dateRange: makeDateRange(from: dateRange),
            limit: limit,
            requestedDetail: requestedDetail(from: requestedDetailRaw)
        )
        return .semanticCommand(command)
    }
}

extension MarinaAIScenarioIntentV2 {
    var structuredIntent: MarinaStructuredIntent {
        let filter = targetName?.nilIfBlank.map { target in
            MarinaSemanticCommandFilter(
                rawText: target,
                allowedTypes: targetTypeRaw.flatMap { entityTypeHint(from: $0) }.map { [$0] } ?? []
            )
        }
        return .semanticCommand(
            MarinaSemanticCommand(
                family: .planning,
                action: .simulate,
                datasets: [.budgets],
                measure: .remainingBudget,
                includeFilters: filter.map { [$0] } ?? [],
                dateRange: makeDateRange(from: dateRange),
                requestedDetail: .amount
            )
        )
    }
}

extension MarinaAIClarificationIntentV2 {
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

    nonisolated private static func missingField(from rawValue: String) -> MarinaStructuredMissingField? {
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

private func semanticAction(from rawValue: String?) -> MarinaSemanticCommandAction? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandAction.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "sum", "total", "spend_total", "amount_total", "count", "minimum", "min", "maximum", "max":
        return .total
    case "average", "avg", "normally":
        return .average
    case "rank", "top", "largest", "biggest", "smallest", "bottom":
        return .rank
    case "breakdown", "group", "grouped", "grouped_breakdown":
        return .group
    case "compare", "comparison", "change":
        return .compare
    case "list", "list_rows", "rows", "recent", "latest", "newest":
        return .listRows
    case "lookup", "lookup_details", "details":
        return .lookupDetails
    case "simulate":
        return .simulate
    default:
        return MarinaSemanticCommandAction(rawValue: normalized)
    }
}

private func semanticDataset(from rawValue: String?) -> MarinaSemanticCommandDataset? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandDataset.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "workspace", "workspaces", "current_workspace", "currentworkspace":
        return .workspaces
    case "variable_expenses", "variableexpenses", "expenses", "expense", "transactions", "transaction", "merchant":
        return .variableExpenses
    case "planned_expenses", "plannedexpenses", "planned_expense", "plannedexpense", "presets_due":
        return .plannedExpenses
    case "income", "income_source", "incomesource":
        return .income
    case "income_series", "incomeseries":
        return .incomeSeries
    case "cards", "card":
        return .cards
    case "categories", "category":
        return .categories
    case "presets", "preset":
        return .presets
    case "budgets", "budget":
        return .budgets
    case "savings", "savings_ledger", "savingsledger", "savings_ledger_entries", "savingsledgerentries":
        return .savingsLedger
    case "reconciliation", "reconciliation_accounts", "reconciliationaccounts", "allocation_account", "allocationaccount":
        return .reconciliation
    case "expense_allocations", "expenseallocations", "allocations":
        return .expenseAllocations
    case "import_merchant_rules", "importmerchantrules":
        return .importMerchantRules
    case "assistant_alias_rules", "assistantaliasrules", "aliases":
        return .assistantAliasRules
    default:
        return MarinaSemanticCommandDataset(rawValue: normalized)
    }
}

private func entityTypeHint(from rawValue: String?) -> MarinaCandidateEntityTypeHint? {
    if let exact = exactRawValue(rawValue, as: MarinaCandidateEntityTypeHint.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "category", "categories":
        return .category
    case "merchant":
        return .merchant
    case "expense", "transaction", "transactions":
        return .transaction
    case "card", "cards":
        return .card
    case "budget", "budgets":
        return .budget
    case "preset", "presets":
        return .preset
    case "income_source", "incomesource", "income":
        return .incomeSource
    case "allocation_account", "allocationaccount", "reconciliation":
        return .allocationAccount
    case "savings_account", "savingsaccount", "savings":
        return .savingsAccount
    case "workspace":
        return .workspace
    default:
        return MarinaCandidateEntityTypeHint(rawValue: normalized)
    }
}

private func semanticSort(from rawValue: String?) -> MarinaSemanticCommandSort? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticCommandSort.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "newest", "latest", "recent", "most_recent":
        return .newest
    case "largest", "biggest", "top", "highest":
        return .largest
    case "delta_descending", "changed", "change":
        return .deltaDescending
    case "grouped_total_descending", "breakdown":
        return .groupedTotalDescending
    default:
        return MarinaSemanticCommandSort(rawValue: normalized)
    }
}

private func semanticMeasure(from rawValue: String?) -> MarinaCandidateMeasure? {
    if let exact = exactRawValue(rawValue, as: MarinaCandidateMeasure.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "spend", "spending", "total_spend", "expense_amount":
        return .spend
    case "income", "earnings", "received_income", "planned_income":
        return .income
    case "savings", "saved":
        return .savings
    case "remaining_budget", "remainingbudget", "safe_spend", "safespend":
        return .remainingBudget
    case "reconciliation_balance", "reconciliationbalance", "allocation_balance", "allocationbalance":
        return .reconciliationBalance
    case "category_share", "categoryshare", "share", "percentage":
        return .categoryShare
    case "transaction_amount", "transactionamount", "amount", "purchase_amount", "purchaseamount":
        return .transactionAmount
    case "transaction_frequency", "transactionfrequency", "frequency", "count":
        return .transactionFrequency
    case "preset_amount", "presetamount":
        return .presetAmount
    case "savings_movement", "savingsmovement":
        return .savingsMovement
    default:
        return nil
    }
}

private func semanticGrouping(from rawValue: String?) -> MarinaGroupingDimensionCandidate? {
    if let exact = exactRawValue(rawValue, as: MarinaGroupingDimensionCandidate.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "category", "categories":
        return .category
    case "merchant", "merchants":
        return .merchant
    case "card", "cards":
        return .card
    case "transaction", "transactions", "row", "rows":
        return .transaction
    case "income_source", "incomesource", "source":
        return .incomeSource
    case "preset", "presets":
        return .preset
    case "savings_ledger_entry", "savingsledgerentry", "savings_ledger":
        return .savingsLedgerEntry
    case "allocation_account", "allocationaccount", "reconciliation":
        return .allocationAccount
    case "day", "daily":
        return .day
    case "week", "weekly":
        return .week
    case "month", "monthly":
        return .month
    default:
        return nil
    }
}

private func requestedDetail(from rawValue: String?) -> MarinaSemanticRequestedDetail? {
    if let exact = exactRawValue(rawValue, as: MarinaSemanticRequestedDetail.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "general", "summary", "details":
        return .general
    case "date", "when":
        return .date
    case "amount", "value":
        return .amount
    case "card":
        return .card
    case "category":
        return .category
    case "status":
        return .status
    case "schedule", "due":
        return .schedule
    case "recurrence", "repeat":
        return .recurrence
    case "account":
        return .account
    case "balance":
        return .balance
    case "linked_objects", "linkedobjects", "links":
        return .linkedObjects
    case "linked_cards", "linkedcards":
        return .linkedCards
    case "linked_presets", "linkedpresets":
        return .linkedPresets
    case "category_limits", "categorylimits":
        return .categoryLimits
    case "membership", "member":
        return .membership
    default:
        return nil
    }
}

private func incomeStatus(from rawValue: String?) -> MarinaIncomeStatusScope? {
    if let exact = exactRawValue(rawValue, as: MarinaIncomeStatusScope.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "planned", "expected", "projected":
        return .planned
    case "actual", "received", "real":
        return .actual
    case "all", "both":
        return .all
    default:
        return nil
    }
}

private func insightIntent(from rawValue: String?) -> MarinaInsightIntent? {
    if let exact = exactRawValue(rawValue, as: MarinaInsightIntent.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "change_summary", "changesummary", "changed":
        return .changeSummary
    case "contributor_analysis", "contributoranalysis", "driver", "why":
        return .contributorAnalysis
    case "normality_check", "normalitycheck", "normal", "weird":
        return .normalityCheck
    case "watch_outs", "watchouts", "watch", "risk":
        return .watchOuts
    case "explain_budgeting", "explainbudgeting", "explain":
        return .explainBudgeting
    case "multi_part_contributors", "multipartcontributors", "biggest_offenders", "biggestoffenders":
        return .multiPartContributors
    default:
        return nil
    }
}

private func softTimeHint(from rawValue: String?) -> MarinaInsightSoftTimeHint? {
    if let exact = exactRawValue(rawValue, as: MarinaInsightSoftTimeHint.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "lately", "recently":
        return .lately
    case "since_payday", "sincepayday", "payday":
        return .sincePayday
    case "budget_cycle", "budgetcycle":
        return .budgetCycle
    case "around_trip", "aroundtrip", "trip":
        return .aroundTrip
    default:
        return nil
    }
}

private func periodUnit(from rawValue: String?) -> HomeQueryPeriodUnit? {
    if let exact = exactRawValue(rawValue, as: HomeQueryPeriodUnit.self) {
        return exact
    }
    guard let normalized = normalizedToken(rawValue) else { return nil }
    switch normalized {
    case "day", "daily":
        return .day
    case "week", "weekly":
        return .week
    case "month", "monthly":
        return .month
    case "quarter", "quarterly":
        return .quarter
    case "year", "yearly", "annual":
        return .year
    default:
        return nil
    }
}

private func semanticFilters(from mentions: [MarinaAIEntityMentionV2]) -> [MarinaSemanticCommandFilter] {
    mentions.compactMap { mention in
        guard let rawText = mention.rawText?.nilIfBlank else { return nil }
        let allowed = ([mention.typeRaw].compactMap { $0 } + mention.allowedTypeRaws)
            .compactMap(entityTypeHint(from:))
        return MarinaSemanticCommandFilter(rawText: rawText, allowedTypes: allowed)
    }
}

private func makeDateRange(from intent: MarinaAIDateRangeV2?) -> HomeQueryDateRange? {
    makeDateRange(start: intent?.startISO8601, end: intent?.endISO8601)
}

private func exactRawValue<Value: RawRepresentable>(
    _ rawValue: String?,
    as _: Value.Type
) -> Value? where Value.RawValue == String {
    guard let rawValue = rawValue?.nilIfBlank else { return nil }
    return Value(rawValue: rawValue)
}

private func normalizedToken(_ rawValue: String?) -> String? {
    guard let rawValue = rawValue?.nilIfBlank else { return nil }
    return rawValue
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        .nilIfBlank
}

private func makeDateRange(start: String?, end: String?) -> HomeQueryDateRange? {
    MarinaDateOnlyRangeCodec.dateRange(start: start, end: end)
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        switch trimmed.lowercased() {
        case "null", "nil", "none", "n/a", "na", "unknown":
            return nil
        default:
            return trimmed
        }
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
            throw MarinaFoundationModelsServiceError.diagnosedGenerationFailure(
                MarinaFoundationModelsFailureDiagnostic(
                    category: .unavailable,
                    step: .availability
                )
            )
        }
        guard model.supportsLocale(locale) else {
            throw MarinaFoundationModelsServiceError.diagnosedGenerationFailure(
                MarinaFoundationModelsFailureDiagnostic(
                    category: .unsupportedLanguageOrLocale,
                    step: .availability,
                    availabilityReason: "unsupported_locale"
                )
            )
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
        case .readQuery, .lookup, .clarification, .scenario:
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
