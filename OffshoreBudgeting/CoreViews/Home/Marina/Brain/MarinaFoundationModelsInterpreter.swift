import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "A compact semantic request for a read-only budgeting assistant.")
fileprivate struct MarinaGeneratedSemanticRequest {
    @Guide(description: "One of: workspace, budget, card, plannedExpense, variableExpense, reconciliationAccount, savingsAccount, income, category, preset. For generic spend on a named target whose type is unclear, use variableExpense and let Marina resolve the target.")
    var entity: String

    @Guide(description: "One of: list, count, sum, average, compare, last, next, group, share, forecast, whatIf.")
    var operation: String

    @Guide(description: "Optional measure: amount, plannedAmount, actualAmount, effectiveAmount, budgetImpact, savingsTotal, incomeAmount, reconciliationBalance, categoryAvailability, remainingRoom, burnRate, projectedSpend, safeDailySpend, paceDifference, coverageRatio, recurringBurden, concentration, color, name.")
    var measure: String?

    @Guide(description: "Dimensions such as category, card, merchantText, incomeSource, preset, reconciliationAccount, date. Use a dimension only when the user's wording explicitly identifies that kind of target.")
    var dimensions: [String]

    @Guide(description: "One of: currentPeriod, previousPeriod, currentMonth, previousMonth, nextSevenDays, allTime.")
    var dateRangeToken: String

    @Guide(description: "The raw primary target text, like Apple, Apple Card, Grocery, Groceries, Salary, or Alejandro. Preserve the user's target wording when the type is unclear.")
    var targetName: String?

    @Guide(description: "The second named entity for compare requests. Leave empty if none.")
    var comparisonTargetName: String?

    @Guide(description: "Expense title/description text to search. Use only when the user explicitly says merchant, store, vendor, title, description, or clearly asks for expense text.")
    var textQuery: String?

    @Guide(description: "Requested list limit, from 1 to 20. Leave empty when not a list.")
    var resultLimit: Int?

    @Guide(description: "Sort mode: dateAscending, dateDescending, amountAscending, amountDescending, nameAscending.")
    var sort: String?

    @Guide(description: "Expense scope: planned, variable, unified.")
    var expenseScope: String?

    @Guide(description: "Income state: planned, actual, all.")
    var incomeState: String?

    @Guide(description: "A virtual spend amount for what-if spending prompts. Leave empty unless the user provides a numeric spend amount.")
    var whatIfAmount: Double?

    @Guide(description: "Category availability list filter: all, over, near, or underLimit. Use only with measure categoryAvailability.")
    var categoryAvailabilityFilter: String?

    @Guide(description: "Expected answer shape: metric, list, comparison, clarification, unsupported.")
    var expectedAnswerShape: String

    @Guide(description: "A clarification question only when required information is missing. Leave empty for target-type ambiguity; Marina's resolver will create executable choices.")
    var clarificationQuestion: String?

    @Guide(description: "Unsupported reason: readOnly, unavailableModel, unsupportedCombination, unresolvedEntity, ambiguousEntity. Leave empty otherwise.")
    var unsupportedReason: String?
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelsInterpreter: MarinaModelInterpreting {
    private let runtime: MarinaFoundationModelRuntime
    private let localeConfiguration: MarinaFoundationModelLocaleConfiguration

    init(
        runtime: MarinaFoundationModelRuntime = MarinaFoundationModelRuntime(),
        localeConfiguration: MarinaFoundationModelLocaleConfiguration = .current
    ) {
        self.runtime = runtime
        self.localeConfiguration = localeConfiguration
    }

    func interpretedSemanticRequest(for prompt: String, context: MarinaBrainContext) async throws -> MarinaInterpretedSemanticRequest {
        let result = await runtime.generateSemanticRequest(
            for: prompt,
            instructions: localeConfiguration.appending(to: instructions),
            localeConfiguration: localeConfiguration
        )

        switch result {
        case .generated(let generated, let diagnosticNotes):
            return MarinaInterpretedSemanticRequest(
                request: semanticRequest(from: generated),
                confidence: .medium,
                source: .foundationModel,
                diagnosticNotes: diagnosticNotes
            )
        case .unsupported(let reason, let diagnosticNotes):
            return MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: reason
                ),
                confidence: .low,
                source: .unavailableFallback,
                diagnosticNotes: diagnosticNotes
            )
        }
    }

    private var instructions: String {
        """
        You are Marina, a read-only budgeting assistant for Offshore.
        Convert the user's message into one compact semantic request.
        Keep every generated enum value, raw semantic token, date-range token, and schema token in the canonical English values described by the schema.
        Natural-language fields such as clarificationQuestion must follow the requested response language.
        Do not calculate money. Do not invent records. Do not mutate data.
        Preserve raw target words and let Marina resolve aliases, singular/plural forms, workspace records, and ambiguity.
        Marina may resolve short follow-up phrases from deterministic local conversation context before this model interpreter runs; if a follow-up reaches you, interpret only the visible prompt and do not assume hidden financial state.
        Use currentPeriod when the user says this period, current period, or gives no date.
        Use currentMonth when the user says this month. Use previousMonth when the user says last month.
        Treat merchant/store/vendor wording as expense title/description text, not a separate stored entity.
        Treat Home metric terms as semantic requests: safe spend means remainingRoom; savings outlook or projected savings means savingsTotal forecast; actual savings means savings status for the current period; income progress means actual-to-planned income share; category availability means categoryAvailability; category spotlight means grouped category spend; spend trends means grouped category spend over date buckets; next planned expense means plannedExpense next; card summary means card budgetImpact.
        If the user asks for expenses, transactions, or rows behind/driving spend trends, return a variableExpense list request with budgetImpact, amountDescending, unified expense scope, and do not return the grouped spend trends summary.
        Formula metric phrases map to deterministic Marina measures only: daily spend, burn rate, or spending rate means entity budget, operation average, measure burnRate; projected spend, where will I end up, or on track to spend means entity budget, operation forecast, measure projectedSpend; daily allowance, safe per day, or what can I spend per day means entity budget, operation forecast, measure safeDailySpend; on track, ahead, behind, or spending too fast means entity budget, operation compare, measure paceDifference; does my income cover, covered by income, or income coverage means measure coverageRatio on income or budget; recurring burden, fixed expenses, or preset burden means entity preset, operation sum, measure recurringBurden; what is eating my budget, biggest share, or concentration means entity category, operation share, measure concentration.
        For "show category availability", use entity category, operation forecast, measure categoryAvailability, and expectedAnswerShape metric.
        For "which/list/show categories are over/near/under limit" requests, use entity category, operation list, measure categoryAvailability, expectedAnswerShape list, and set categoryAvailabilityFilter to over, near, or underLimit. Preserve requested list limits.
        For safe spend, can I spend, remaining room, or budget room, use entity budget and measure remainingRoom.
        For "what if I spend $X" safe-spend questions, use operation whatIf, measure remainingRoom, expectedAnswerShape comparison, and set whatIfAmount.
        Do not calculate safe spend, category cap room, split ownership, or category availability; deterministic Home calculators handle those details.
        For generic spend/list/average/count expense requests such as "spend on Grocery", put the raw target in targetName, leave dimensions empty, use variableExpense, and let Marina clarify category/card/expense text if needed.
        Use dimensions only when the user explicitly names the target type, such as category, card, income source, preset, savings account, reconciliation account, merchant, store, vendor, title, or description.
        If a request asks to delete, move, edit, rename, or create records, return unsupported with readOnly.
        Do not return clarification just because a target could mean multiple stored records or expense text; Marina's deterministic resolver handles that.
        Prefer budgetImpact for spend questions. Prefer incomeAmount for income questions.
        """
    }

    private func semanticRequest(from generated: MarinaGeneratedSemanticRequest) -> MarinaSemanticRequest {
        let entity = MarinaSemanticEntity(rawValue: generated.entity) ?? .workspace
        let operation = MarinaSemanticOperation(rawValue: generated.operation) ?? .list
        let measure = generated.measure.flatMap(MarinaSemanticMeasure.init(rawValue:))
        let dimensions = generated.dimensions.compactMap(MarinaSemanticDimension.init(rawValue:))
        let dateRange = MarinaSemanticDateRangeToken(rawValue: generated.dateRangeToken) ?? .currentPeriod
        let sort = generated.sort.flatMap(MarinaSemanticSort.init(rawValue:))
        let expenseScope = generated.expenseScope.flatMap(MarinaSemanticExpenseScope.init(rawValue:))
        let incomeState = generated.incomeState.flatMap(MarinaSemanticIncomeState.init(rawValue:))
        let answerShape = MarinaSemanticAnswerShape(rawValue: generated.expectedAnswerShape) ?? .metric
        let unsupportedReason = generated.unsupportedReason.flatMap(MarinaSemanticUnsupportedReason.init(rawValue:))
            ?? (answerShape == .unsupported ? .unsupportedCombination : nil)

        return MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRange,
            targetName: normalizedOptional(generated.targetName),
            comparisonTargetName: normalizedOptional(generated.comparisonTargetName),
            textQuery: normalizedOptional(generated.textQuery),
            resultLimit: generated.resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            whatIfAmount: generated.whatIfAmount,
            categoryAvailabilityFilter: generated.categoryAvailabilityFilter.flatMap(MarinaCategoryAvailabilityFilter.init(rawValue:)),
            expectedAnswerShape: answerShape,
            clarificationQuestion: normalizedOptional(generated.clarificationQuestion),
            unsupportedReason: unsupportedReason
        )
    }

    private func normalizedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
fileprivate enum MarinaFoundationModelRuntimeResult {
    case generated(MarinaGeneratedSemanticRequest, diagnosticNotes: [String])
    case unsupported(MarinaSemanticUnsupportedReason, diagnosticNotes: [String])
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelRuntime {
    private let model: SystemLanguageModel
    private let options: GenerationOptions

    init(
        model: SystemLanguageModel = SystemLanguageModel(useCase: .general, guardrails: .default),
        options: GenerationOptions = GenerationOptions(
            sampling: .greedy,
            temperature: 0.0,
            maximumResponseTokens: 512
        )
    ) {
        self.model = model
        self.options = options
    }

    fileprivate func generateSemanticRequest(
        for prompt: String,
        instructions: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult {
        guard model.isAvailable else {
            return .unsupported(
                .unavailableModel,
                diagnosticNotes: ["FoundationModels unavailable: \(availabilityDescription(model.availability))"]
            )
        }

        guard model.supportsLocale(localeConfiguration.locale) else {
            return .unsupported(
                .unsupportedLanguageOrLocale,
                diagnosticNotes: ["FoundationModels unsupported locale: \(localeConfiguration.identifier)"]
            )
        }

        let session = LanguageModelSession(
            model: model,
            tools: [],
            instructions: instructions
        )

        do {
            let response = try await session.respond(
                to: prompt,
                generating: MarinaGeneratedSemanticRequest.self,
                includeSchemaInPrompt: true,
                options: options
            )
            return .generated(
                response.content,
                diagnosticNotes: [
                    "FoundationModels transcriptEntries=\(response.transcriptEntries.count)",
                    "FoundationModels contextSize=\(model.contextSize)"
                ]
            )
        } catch let error as LanguageModelSession.GenerationError {
            return .unsupported(
                unsupportedReason(for: error),
                diagnosticNotes: ["FoundationModels generation error: \(error.localizedDescription)"]
            )
        } catch {
            return .unsupported(
                .modelGenerationFailed,
                diagnosticNotes: ["FoundationModels error: \(error.localizedDescription)"]
            )
        }
    }

    private func unsupportedReason(for error: LanguageModelSession.GenerationError) -> MarinaSemanticUnsupportedReason {
        switch error {
        case .assetsUnavailable, .rateLimited, .concurrentRequests:
            return .unavailableModel
        case .exceededContextWindowSize:
            return .modelContextLimit
        case .guardrailViolation, .refusal:
            return .modelGuardrail
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguageOrLocale
        case .decodingFailure, .unsupportedGuide:
            return .modelGenerationFailed
        @unknown default:
            return .modelGenerationFailed
        }
    }

    private func availabilityDescription(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "available"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "appleIntelligenceNotEnabled"
        case .unavailable(.deviceNotEligible):
            return "deviceNotEligible"
        case .unavailable(.modelNotReady):
            return "modelNotReady"
        @unknown default:
            return "unavailable"
        }
    }
}
#endif

enum MarinaModelInterpreterFactory {
    @MainActor
    static func makeDefault() -> any MarinaModelInterpreting {
        makeDefault(modelBackedInterpreter: makeModelBackedInterpreter())
    }

    @MainActor
    static func makeDefault(modelBackedInterpreter: (any MarinaModelInterpreting)?) -> any MarinaModelInterpreting {
        modelBackedInterpreter ?? MarinaUnavailableModelInterpreter()
    }

    @MainActor
    static func makeModelBackedInterpreter() -> (any MarinaModelInterpreting)? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return MarinaFoundationModelsInterpreter()
        }
        #endif
        return nil
    }
}
