import Foundation

struct MarinaFoundationIntentEnvelopeV3Payload: Codable, Equatable, Sendable {
    let routeRaw: String
    let intentRaw: String?
    let targetText: String?
    let secondaryTargetText: String?
    let relationshipText: String?
    let dateText: String?
    let comparisonDateText: String?
    let amountText: String?
    let valueDirectionRaw: String?
    let confidenceRaw: String?
    let unsupportedReasonRaw: String?
}

struct MarinaLiveDomainIntentMapping: Equatable, Sendable {
    let intent: MarinaAIIntentV2
    let liveEnvelopeSummary: String
    let canonicalRouteSummary: String
    let routeOverrideSummary: String?
    let routeGuardSummary: String?
    let routeKeySummary: String?
    let droppedTargetSummary: String?
    let datePolicySummary: String?
    let dateSourceSummary: String?
    let effectiveDateRangeSummary: String?
    let routeRescueSummary: String?
    let blockedWrongQuery: Bool
}

private enum MarinaLiveRouteKey: String, Equatable, Sendable {
    case workspaceLookup
    case activeBudget
    case budgetLinkedCards
    case budgetLinkedPresets
    case budgetCategoryLimit
    case budgetForecastScenario
    case allocationRows
    case settlementRows
    case reconciliationBalance
    case savingsActivity
    case savingsStatus
    case incomePlannedVsActual
    case incomeActual
    case incomePlanned
    case recentTransactions
    case topCategories
    case categoryBreakdown
    case categoryComparison
    case spendTotal
}

private enum MarinaLiveDateDefaultMode: Equatable, Sendable {
    case none
    case ambient
    case explicitText(String)
}

private struct MarinaLiveDateResolution: Equatable, Sendable {
    let intent: MarinaAIDateRangeV2?
    let source: MarinaDateSource
    let policySummary: String?
    let effectiveRangeSummary: String?

    static let none = MarinaLiveDateResolution(
        intent: nil,
        source: .none,
        policySummary: nil,
        effectiveRangeSummary: nil
    )
}

struct MarinaLiveDomainIntentMapper {
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        nowProvider: @escaping () -> Date = Date.init,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    private var localCalendar: Calendar {
        var value = calendar
        if value.timeZone.secondsFromGMT() == 0 {
            value.timeZone = .current
        }
        return value
    }

    func map(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        context: MarinaLanguageRouterContext
    ) -> MarinaLiveDomainIntentMapping {
        let normalizedPrompt = normalized(prompt)
        let envelopeIntent = token(payload.intentRaw)
        let route = MarinaFoundationRouteKind(routeRaw: payload.routeRaw)
        let envelopeSummary = [
            "route=\(route.rawValue)",
            envelopeIntent.map { "intent=\($0)" },
            payload.targetText?.nilIfBlankForV2.map { "target=\($0)" },
            payload.secondaryTargetText?.nilIfBlankForV2.map { "secondary=\($0)" },
            payload.relationshipText?.nilIfBlankForV2.map { "relationship=\($0)" },
            payload.dateText?.nilIfBlankForV2.map { "date=\($0)" },
            payload.comparisonDateText?.nilIfBlankForV2.map { "comparison=\($0)" },
            payload.amountText?.nilIfBlankForV2.map { "amount=\($0)" },
            payload.valueDirectionRaw?.nilIfBlankForV2.map { "direction=\($0)" },
            payload.confidenceRaw?.nilIfBlankForV2.map { "confidence=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")

        if isReadOnlyMutation(normalizedPrompt) {
            return blocked(
                prompt: prompt,
                payload: payload,
                envelopeSummary: envelopeSummary,
                reason: "crudDeferred"
            )
        }

        if let mapped = supportedMapping(
            payload: payload,
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context,
            envelopeSummary: envelopeSummary
        ) {
            return mapped
        }

        switch route {
        case .help:
            return mapped(
                intent: .unsupported(
                    MarinaAIUnsupportedIntentV2(
                        reasoning: "",
                        reasonRaw: "help",
                        message: "Marina can search, summarize, calculate, and run read-only what-if scenarios over this workspace."
                    )
                ),
                payload: payload,
                envelopeSummary: envelopeSummary,
                canonicalRoute: "help",
                datePolicy: nil,
                blockedWrongQuery: false
            )
        case .unsupported, .clarification:
            return mapped(
                intent: .unsupported(
                    MarinaAIUnsupportedIntentV2(
                        reasoning: "",
                        reasonRaw: payload.unsupportedReasonRaw?.nilIfBlankForV2 ?? "unsupported",
                        message: "I could not safely map that to a supported Marina read route, so I did not query your financial data."
                    )
                ),
                payload: payload,
                envelopeSummary: envelopeSummary,
                canonicalRoute: "unsupported:\(payload.unsupportedReasonRaw?.nilIfBlankForV2 ?? "unmapped")",
                datePolicy: nil,
                blockedWrongQuery: false
            )
        case .lookup:
            if let target = payload.targetText?.nilIfBlankForV2,
               isInvalidEntityTarget(target) == false {
                return mappedLookup(
                    payload: payload,
                    envelopeSummary: envelopeSummary,
                    routeKey: nil,
                    canonicalRoute: "generic.lookup",
                    searchText: target,
                    objectTypes: MarinaLookupObjectType.safeDefaultSearchTypes.map(\.rawValue),
                    requestedDetail: "general"
                )
            }
            return blocked(
                prompt: prompt,
                payload: payload,
                envelopeSummary: envelopeSummary,
                reason: "unmappedLookupRoute"
            )
        case .readQuery, .scenario:
            return blocked(
                prompt: prompt,
                payload: payload,
                envelopeSummary: envelopeSummary,
                reason: "unmappedLiveRoute"
            )
        }
    }

    private func supportedMapping(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        normalizedPrompt: String,
        context: MarinaLanguageRouterContext,
        envelopeSummary: String
    ) -> MarinaLiveDomainIntentMapping? {
        guard let routeKey = routeKey(
            payload: payload,
            prompt: prompt,
            normalizedPrompt: normalizedPrompt,
            context: context
        ) else {
            return nil
        }

        switch routeKey {
        case .workspaceLookup:
            return mappedLookup(
                payload: payload,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "workspace.lookup",
                searchText: context.workspaceName,
                objectTypes: ["workspace"],
                requestedDetail: "status"
            )

        case .activeBudget:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "budget.active",
                subject: "budgets",
                operation: "lookupDetails",
                measure: "remainingBudget",
                requestedDetail: "status",
                responseDate: .none
            )

        case .budgetLinkedCards:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "budget.linkedCards",
                subject: "budgets",
                operation: "lookupDetails",
                measure: "remainingBudget",
                target: namedTarget(context.budgetNames, in: prompt, fallback: payload.targetText ?? payload.secondaryTargetText),
                targetType: "budget",
                requestedDetail: "linkedCards",
                responseDate: .none
            )

        case .budgetLinkedPresets:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "budget.linkedPresets",
                subject: "budgets",
                operation: "lookupDetails",
                measure: "remainingBudget",
                target: namedTarget(context.budgetNames, in: prompt, fallback: payload.targetText ?? payload.secondaryTargetText),
                targetType: "budget",
                requestedDetail: "linkedPresets",
                responseDate: .none
            )

        case .budgetCategoryLimit:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "budget.categoryLimit",
                subject: "budgets",
                operation: "lookupDetails",
                measure: "remainingBudget",
                target: namedTarget(context.categoryNames, in: prompt, fallback: payload.targetText ?? payload.secondaryTargetText),
                targetType: "category",
                requestedDetail: "amount",
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .none)
            )

        case .budgetForecastScenario:
            let target = scenarioTarget(payload: payload, prompt: prompt, context: context)
            return mapped(
                intent: .scenario(
                    MarinaAIScenarioIntentV2(
                        reasoning: "",
                        scenarioRaw: "budgetForecast",
                        targetTypeRaw: target?.type,
                        targetName: target?.name,
                        valueModeRaw: payload.valueDirectionRaw?.nilIfBlankForV2 ?? inferredValueDirection(from: normalizedPrompt),
                        amount: amount(from: payload.amountText) ?? amount(from: prompt),
                        percent: nil,
                        dateRange: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient).intent,
                        confidenceRaw: payload.confidenceRaw
                    )
                ),
                payload: payload,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "scenario.budgetForecast",
                dateResolution: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient),
                blockedWrongQuery: false
            )

        case .allocationRows:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "reconciliation.allocationRows",
                subject: "expenseAllocations",
                operation: "listRows",
                measure: "reconciliationBalance",
                target: allocationTarget(payload: payload, prompt: prompt),
                targetType: allocationTarget(payload: payload, prompt: prompt) == nil ? nil : "allocationAccount",
                grouping: "allocationAccount",
                ranking: "newest",
                limit: 10,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .none)
            )

        case .settlementRows:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "reconciliation.settlementRows",
                subject: "reconciliation",
                operation: "listRows",
                measure: "reconciliationBalance",
                target: allocationTarget(payload: payload, prompt: prompt),
                targetType: allocationTarget(payload: payload, prompt: prompt) == nil ? nil : "allocationAccount",
                grouping: "allocationAccount",
                ranking: "newest",
                limit: 10,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .none)
            )

        case .reconciliationBalance:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "reconciliation.balance",
                subject: "reconciliation",
                operation: "lookupDetails",
                measure: "reconciliationBalance",
                target: allocationTarget(payload: payload, prompt: prompt),
                targetType: "allocationAccount",
                requestedDetail: "balance",
                responseDate: .none
            )

        case .savingsActivity:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "savings.activity",
                subject: "savingsLedger",
                operation: "listRows",
                measure: "savingsMovement",
                grouping: "savingsLedgerEntry",
                ranking: "newest",
                limit: 10,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .none)
            )

        case .savingsStatus:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "savings.status",
                subject: "savingsLedger",
                operation: "lookupDetails",
                measure: "savings",
                requestedDetail: "status",
                responseDate: .none
            )

        case .incomePlannedVsActual:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "income.plannedVsActual",
                subject: "income",
                operation: "sum",
                measure: "income",
                requestedDetail: "status",
                incomeStatus: "all",
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )

        case .incomeActual:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "income.actual",
                subject: "income",
                operation: "sum",
                measure: "income",
                incomeStatus: "actual",
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )

        case .incomePlanned:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "income.planned",
                subject: "income",
                operation: "sum",
                measure: "income",
                incomeStatus: "planned",
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )

        case .recentTransactions:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "spending.recentRows",
                subject: "variableExpenses",
                operation: "listRows",
                measure: "transactionAmount",
                grouping: "transaction",
                ranking: "newest",
                limit: explicitLimit(in: normalizedPrompt) ?? 10,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .none)
            )

        case .topCategories:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "spending.topCategories",
                subject: "variableExpenses",
                operation: "rank",
                measure: "spend",
                grouping: "category",
                ranking: "largest",
                limit: explicitLimit(in: normalizedPrompt) ?? 5,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )

        case .categoryBreakdown:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "spending.categoryBreakdown",
                subject: "variableExpenses",
                operation: "group",
                measure: "spend",
                grouping: "category",
                ranking: "largest",
                limit: 10,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )

        case .categoryComparison:
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: "spending.categoryComparison",
                subject: "variableExpenses",
                operation: "compare",
                measure: "spend",
                target: namedTarget(context.categoryNames, in: prompt, fallback: payload.targetText),
                targetType: "category",
                responseDate: dateIntent(from: nil, prompt: prompt, context: context, defaultMode: .ambient, allowComparisonOnlyPromptDate: false),
                comparisonDate: dateIntent(from: payload.comparisonDateText, prompt: prompt, context: context, defaultMode: .explicitText("last month"))
            )

        case .spendTotal:
            let spendTarget = spendingTarget(payload: payload, prompt: prompt, context: context)
            return mappedRead(
                payload: payload,
                prompt: prompt,
                envelopeSummary: envelopeSummary,
                routeKey: routeKey,
                canonicalRoute: spendTarget.map { "spending.total.\($0.type)" } ?? "spending.total.workspace",
                subject: "variableExpenses",
                operation: "sum",
                measure: "spend",
                target: spendTarget?.name,
                targetType: spendTarget?.type,
                responseDate: dateIntent(from: payload.dateText, prompt: prompt, context: context, defaultMode: .ambient)
            )
        }
    }

    private func routeKey(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        normalizedPrompt: String,
        context: MarinaLanguageRouterContext
    ) -> MarinaLiveRouteKey? {
        let signal = routeSignal(payload: payload)
        let normalizedSignal = normalized(signal)

        let asksWorkspaceInventory = containsAny(["workspaces", "how many workspace", "count workspace", "list workspace", "show my workspace"], in: normalizedPrompt)
        if asksWorkspaceInventory == false,
           containsAny(["workspace am i in", "current workspace", "which workspace", "what workspace"], in: normalizedPrompt)
            || (asksWorkspaceInventory == false && containsAny(["workspace", "workspacelookup"], in: normalizedSignal)) {
            return .workspaceLookup
        }

        if containsAll(["active", "budget"], in: normalizedPrompt)
            || containsAny(["current budget", "active budget"], in: normalizedPrompt)
            || containsAny(["activebudget"], in: normalizedSignal) {
            return .activeBudget
        }

        if isBudgetLinkedRelationship(
            normalizedPrompt: normalizedPrompt,
            normalizedSignal: normalizedSignal,
            objectWords: ["card", "cards"]
        ) {
            return .budgetLinkedCards
        }

        if isBudgetLinkedRelationship(
            normalizedPrompt: normalizedPrompt,
            normalizedSignal: normalizedSignal,
            objectWords: ["preset", "presets"]
        ) {
            return .budgetLinkedPresets
        }

        if normalizedPrompt.contains("limit"),
           normalizedPrompt.contains("budget") || normalizedPrompt.contains("category") {
            return .budgetCategoryLimit
        }

        if containsAny(["what if", "if i "], in: normalizedPrompt)
            || containsAny(["whatif", "budgetforecast", "scenario"], in: normalizedSignal) {
            return .budgetForecastScenario
        }

        if containsAny(["allocation row", "allocation rows", "allocations", "allocated"], in: normalizedPrompt)
            || containsAny(["allocationrow", "allocationrows", "allocations"], in: normalizedSignal) {
            return .allocationRows
        }

        if containsAny(["settlement row", "settlement rows", "settlements", "paid me back", "pay me back", "repaid", "reimburse"], in: normalizedPrompt)
            || containsAny(["settlementrow", "settlementrows", "settlements"], in: normalizedSignal) {
            return .settlementRows
        }

        if containsAny(["reconciliation balance", "shared balance"], in: normalizedPrompt)
            || (normalizedPrompt.contains("balance") && normalizedPrompt.contains("roommate"))
            || containsAny(["reconciliationbalance", "sharedbalance"], in: normalizedSignal) {
            return .reconciliationBalance
        }

        if containsAny(["savings activity", "saving activity", "savings transactions"], in: normalizedPrompt)
            || containsAny(["savingsactivity", "savingsmovement"], in: normalizedSignal) {
            return .savingsActivity
        }

        if containsAny(["savings status", "saving status", "savings balance", "actual savings"], in: normalizedPrompt)
            || containsAny(["savingsstatus", "savingsbalance"], in: normalizedSignal) {
            return .savingsStatus
        }

        if containsAny(["planned vs actual income", "actual vs planned income"], in: normalizedPrompt)
            || (normalizedPrompt.contains("income") && normalizedPrompt.contains("planned") && normalizedPrompt.contains("actual"))
            || containsAny(["incomecomparison", "plannedvsactualincome"], in: normalizedSignal) {
            return .incomePlannedVsActual
        }

        if normalizedPrompt.contains("actual income")
            || normalizedPrompt.contains("received income")
            || normalizedPrompt.contains("income so far")
            || containsAny(["incomeactual", "actualincome"], in: normalizedSignal) {
            return .incomeActual
        }

        if normalizedPrompt.contains("planned income")
            || normalizedPrompt.contains("expected income")
            || normalizedPrompt.contains("projected income")
            || containsAny(["incomeplanned", "plannedincome"], in: normalizedSignal) {
            return .incomePlanned
        }

        let promptAsksForSpend = normalizedPrompt.contains("spend")
            || normalizedPrompt.contains("spent")
            || normalizedPrompt.contains("spending")
        if containsAny(["recent transactions", "recent purchases", "latest transactions", "last purchase", "newest transactions"], in: normalizedPrompt)
            || (promptAsksForSpend == false && containsAny(["recenttransactions", "transactionrows"], in: normalizedSignal)) {
            return .recentTransactions
        }

        if containsAny(["top categories", "biggest categories", "largest categories"], in: normalizedPrompt)
            || containsAny(["topcategories", "categoryranking"], in: normalizedSignal) {
            return .topCategories
        }

        if normalizedPrompt.contains("break") && normalizedPrompt.contains("category") && normalizedPrompt.contains("spend")
            || containsAny(["categorybreakdown"], in: normalizedSignal) {
            return .categoryBreakdown
        }

        if normalizedPrompt.contains("compare"),
           normalizedPrompt.contains("income") == false,
           containsAny(context.categoryNames.map { normalized($0) }, in: normalizedPrompt) {
            return .categoryComparison
        }

        if promptAsksForSpend {
            return .spendTotal
        }

        return nil
    }

    private func routeSignal(payload: MarinaFoundationIntentEnvelopeV3Payload) -> String {
        [
            payload.intentRaw,
            payload.relationshipText,
            payload.targetText,
            payload.secondaryTargetText,
            payload.unsupportedReasonRaw
        ]
        .compactMap { $0?.nilIfBlankForV2 }
        .joined(separator: " ")
    }

    private func isBudgetLinkedRelationship(
        normalizedPrompt: String,
        normalizedSignal: String,
        objectWords: [String]
    ) -> Bool {
        let mentionsBudget = normalizedPrompt.contains("budget")
        let mentionsObject = objectWords.contains { normalizedPrompt.contains($0) }
        let mentionsRelationship = containsAny(["linked", "link", "attached", "included", "member", "membership"], in: normalizedPrompt)
        return mentionsBudget && mentionsObject && mentionsRelationship
    }

    private func mappedRead(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        envelopeSummary: String,
        routeKey: MarinaLiveRouteKey?,
        canonicalRoute: String,
        subject: String,
        operation: String,
        measure: String,
        target: String? = nil,
        targetType: String? = nil,
        secondaryTarget: String? = nil,
        secondaryTargetType: String? = nil,
        grouping: String? = nil,
        ranking: String? = nil,
        requestedDetail: String? = nil,
        limit: Int? = nil,
        incomeStatus: String? = nil,
        responseDate: MarinaLiveDateResolution = .none,
        comparisonDate: MarinaLiveDateResolution = .none
    ) -> MarinaLiveDomainIntentMapping {
        mapped(
            intent: .readQuery(
                MarinaAIReadQueryIntentV2(
                    reasoning: "",
                    subjectRaw: subject,
                    operationRaw: operation,
                    measureRaw: measure,
                    includeMentions: [
                        entityMention(name: target, type: targetType),
                        entityMention(name: secondaryTarget, type: secondaryTargetType)
                    ].compactMap { $0 },
                    excludeMentions: [],
                    primaryDateRange: responseDate.intent,
                    comparisonDateRange: comparisonDate.intent,
                    groupingRaw: grouping,
                    rankingRaw: ranking,
                    requestedDetailRaw: requestedDetail,
                    limit: limit,
                    incomeStatusRaw: incomeStatus,
                    insightIntentRaw: nil,
                    softTimeHintRaw: nil,
                    confidenceRaw: "high"
                )
            ),
            payload: payload,
            envelopeSummary: envelopeSummary,
            routeKey: routeKey,
            canonicalRoute: canonicalRoute,
            dateResolution: mergedDateResolution(responseDate, comparisonDate),
            blockedWrongQuery: false
        )
    }

    private func mappedLookup(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        envelopeSummary: String,
        routeKey: MarinaLiveRouteKey?,
        canonicalRoute: String,
        searchText: String,
        objectTypes: [String],
        requestedDetail: String?
    ) -> MarinaLiveDomainIntentMapping {
        mapped(
            intent: .lookup(
                MarinaAILookupIntentV2(
                    reasoning: "",
                    objectTypeRaws: objectTypes,
                    searchText: searchText,
                    requestedDetailRaw: requestedDetail,
                    dateRange: nil,
                    limit: 1,
                    confidenceRaw: "high"
                )
            ),
            payload: payload,
            envelopeSummary: envelopeSummary,
            routeKey: routeKey,
            canonicalRoute: canonicalRoute,
            datePolicy: nil,
            dateSource: .none,
            effectiveDateRange: nil,
            blockedWrongQuery: false
        )
    }

    private func mapped(
        intent: MarinaAIIntentV2,
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        envelopeSummary: String,
        routeKey: MarinaLiveRouteKey? = nil,
        canonicalRoute: String,
        dateResolution: MarinaLiveDateResolution,
        routeRescue: String? = nil,
        blockedWrongQuery: Bool
    ) -> MarinaLiveDomainIntentMapping {
        mapped(
            intent: intent,
            payload: payload,
            envelopeSummary: envelopeSummary,
            routeKey: routeKey,
            canonicalRoute: canonicalRoute,
            datePolicy: dateResolution.policySummary,
            dateSource: dateResolution.source,
            effectiveDateRange: dateResolution.effectiveRangeSummary,
            routeRescue: routeRescue,
            blockedWrongQuery: blockedWrongQuery
        )
    }

    private func mapped(
        intent: MarinaAIIntentV2,
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        envelopeSummary: String,
        routeKey: MarinaLiveRouteKey? = nil,
        canonicalRoute: String,
        datePolicy: String?,
        dateSource: MarinaDateSource = .none,
        effectiveDateRange: String? = nil,
        routeRescue: String? = nil,
        blockedWrongQuery: Bool
    ) -> MarinaLiveDomainIntentMapping {
        let routeOverride: String?
        let envelopeIntent = token(payload.intentRaw)
        if envelopeIntent == nil || envelopeIntent == token(canonicalRoute) {
            routeOverride = nil
        } else {
            routeOverride = "swiftCanonicalized:\(envelopeIntent ?? "nil")->\(canonicalRoute)"
        }

        return MarinaLiveDomainIntentMapping(
            intent: intent,
            liveEnvelopeSummary: envelopeSummary,
            canonicalRouteSummary: canonicalRoute,
            routeOverrideSummary: routeOverride,
            routeGuardSummary: blockedWrongQuery ? "blockedWrongQuery" : "allowedCanonicalRoute",
            routeKeySummary: routeKey?.rawValue,
            droppedTargetSummary: droppedTargetSummary(payload: payload, promptDatePolicy: datePolicy),
            datePolicySummary: datePolicy,
            dateSourceSummary: dateSource == .none ? nil : dateSource.rawValue,
            effectiveDateRangeSummary: effectiveDateRange,
            routeRescueSummary: routeRescue ?? (routeOverride == nil ? nil : "postAIMapperCanonicalized"),
            blockedWrongQuery: blockedWrongQuery
        )
    }

    private func blocked(
        prompt: String,
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        envelopeSummary: String,
        reason: String
    ) -> MarinaLiveDomainIntentMapping {
        mapped(
            intent: .unsupported(
                MarinaAIUnsupportedIntentV2(
                    reasoning: "",
                    reasonRaw: reason,
                    message: "I could not safely map that to a supported Marina read route, so I did not query your financial data."
                )
            ),
            payload: payload,
            envelopeSummary: envelopeSummary,
            routeKey: nil,
            canonicalRoute: "blocked.\(reason)",
            datePolicy: nil,
            blockedWrongQuery: true
        )
    }

    private func entityMention(name: String?, type: String?) -> MarinaAIEntityMentionV2? {
        guard let name = name?.nilIfBlankForV2 else { return nil }
        return MarinaAIEntityMentionV2(
            roleRaw: "filter",
            rawText: name,
            typeRaw: type,
            allowedTypeRaws: []
        )
    }

    private func spendingTarget(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        context: MarinaLanguageRouterContext
    ) -> (name: String, type: String)? {
        let normalizedPrompt = normalized(prompt)
        if normalizedPrompt.contains("uncategorized") {
            return ("Uncategorized", "category")
        }

        if normalizedPrompt.contains(" at ") {
            return phraseAfter([" at "], in: prompt)
                .map { (cleanSpendTarget($0), "merchant") }
        }

        if let card = namedTarget(context.cardNames, in: prompt, fallback: nil),
           normalizedPrompt.contains(" card") || normalized(card).contains("card") {
            return (card, "card")
        }

        if let category = namedTarget(context.categoryNames, in: prompt, fallback: nil) {
            return (category, "category")
        }

        if let card = namedTarget(context.cardNames, in: prompt, fallback: nil) {
            return (card, "card")
        }

        guard let fallback = (payload.targetText ?? payload.secondaryTargetText)?.nilIfBlankForV2,
              isInvalidEntityTarget(fallback) == false else {
            return nil
        }

        let fallbackType = normalizedPrompt.contains(" card") ? "card" : "merchant"
        return (cleanSpendTarget(fallback), fallbackType)
    }

    private func scenarioTarget(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String,
        context: MarinaLanguageRouterContext
    ) -> (name: String, type: String)? {
        if let category = namedTarget(context.categoryNames, in: prompt, fallback: payload.targetText) {
            return (category, "category")
        }
        if let card = namedTarget(context.cardNames, in: prompt, fallback: payload.targetText) {
            return (card, "card")
        }
        guard let target = payload.targetText?.nilIfBlankForV2,
              isInvalidEntityTarget(target) == false else {
            return nil
        }
        return (cleanSpendTarget(target), "category")
    }

    private func allocationTarget(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        prompt: String
    ) -> String? {
        if let target = payload.targetText?.nilIfBlankForV2,
           isInvalidEntityTarget(target) == false {
            let cleaned = cleanReconciliationTarget(target)
            return isInvalidEntityTarget(cleaned) ? nil : cleaned.nilIfBlankForV2
        }
        let normalizedPrompt = normalized(prompt)
        if normalizedPrompt.contains("roommate") {
            return "Roommate"
        }
        return nil
    }

    private func namedTarget(
        _ names: [String],
        in prompt: String,
        fallback: String?
    ) -> String? {
        let normalizedPrompt = normalized(prompt)
        if let exact = names.first(where: { normalizedPrompt.contains(normalized($0)) }) {
            return exact
        }
        if let cardLike = names.first(where: { normalizedPrompt.contains(normalized($0) + " card") }) {
            return cardLike
        }
        guard let fallback = fallback?.nilIfBlankForV2,
              isGenericTarget(fallback) == false else {
            return nil
        }
        let normalizedFallback = normalized(fallback)
        if let exactFallback = names.first(where: { normalized($0) == normalizedFallback }) {
            return exactFallback
        }
        if let prefixFallback = names.first(where: { normalizedFallback.contains(normalized($0)) }) {
            return prefixFallback
        }
        return nil
    }

    private func dateIntent(
        from rawDate: String?,
        prompt: String,
        context: MarinaLanguageRouterContext,
        defaultMode: MarinaLiveDateDefaultMode,
        allowComparisonOnlyPromptDate: Bool = true
    ) -> MarinaLiveDateResolution {
        var promptRaw = explicitDatePhrase(in: prompt)
        if allowComparisonOnlyPromptDate == false,
           isComparisonOnlyDatePhrase(promptRaw, prompt: prompt) {
            promptRaw = nil
        }
        let modelRaw = rawDate?.nilIfBlankForV2
        let groundedModel = groundedModelDateText(modelRaw, prompt: prompt)
        let textResolution: (raw: String, source: MarinaDateSource)?
        if let promptRaw {
            textResolution = (promptRaw, .promptExplicit)
        } else if let groundedModel {
            textResolution = (groundedModel, .modelGrounded)
        } else if case .explicitText(let fallbackText) = defaultMode {
            textResolution = (fallbackText, .promptExplicit)
        } else {
            textResolution = nil
        }

        if let textResolution,
           let range = MarinaDateResolver(calendar: localCalendar, nowProvider: nowProvider).resolve(
                input: textResolution.raw,
                modelStartISO8601: nil,
                modelEndISO8601: nil,
                defaultPeriodUnit: context.defaultPeriodUnit
           )?.queryDateRange {
            return dateResolution(
                range: range,
                rawText: textResolution.raw,
                source: textResolution.source,
                periodUnit: context.defaultPeriodUnit,
                modelRaw: modelRaw,
                promptOrModelRaw: promptRaw ?? groundedModel
            )
        }

        if defaultMode == .ambient {
            if let ambient = context.ambientDateRange {
                return dateResolution(
                    range: ambient,
                    rawText: nil,
                    source: .homeAppliedRange,
                    periodUnit: context.defaultPeriodUnit,
                    modelRaw: modelRaw,
                    promptOrModelRaw: promptRaw ?? groundedModel
                )
            }
            if let fallback = MarinaDateOnlyRangeCodec.defaultRange(
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit,
                calendar: localCalendar
            ) {
                return dateResolution(
                    range: fallback,
                    rawText: nil,
                    source: .defaultBudgetingPeriod,
                    periodUnit: context.defaultPeriodUnit,
                    modelRaw: modelRaw,
                    promptOrModelRaw: promptRaw ?? groundedModel
                )
            }
        }

        let modelDropped = modelRaw != nil && modelRaw != groundedModel && modelRaw != promptRaw
        let policy = modelDropped
            ? ["dateSource=none", modelRaw.map { "aiDateDropped=\($0)" }, "modelISO=ignored"].compactMap { $0 }.joined(separator: ",")
            : nil
        return MarinaLiveDateResolution(
            intent: nil,
            source: .none,
            policySummary: policy,
            effectiveRangeSummary: nil
        )
    }

    private func dateResolution(
        range: HomeQueryDateRange,
        rawText: String?,
        source: MarinaDateSource,
        periodUnit: HomeQueryPeriodUnit,
        modelRaw: String?,
        promptOrModelRaw: String?
    ) -> MarinaLiveDateResolution {
        let modelDropped = modelRaw != nil && modelRaw != promptOrModelRaw
        let effective = MarinaDateOnlyRangeCodec.traceSummary(range, calendar: localCalendar)
        return [
            "dateSource=\(source.rawValue)",
            rawText.map { "dateRaw=\($0)" },
            effective.map { "effective=\($0)" },
            modelDropped ? modelRaw.map { "aiDateDropped=\($0)" } : nil,
            "modelISO=ignored"
        ]
        .compactMap { $0 }
        .joined(separator: ",")
        .nilIfBlankForV2
        .map {
            MarinaLiveDateResolution(
                intent: MarinaDateOnlyRangeCodec.aiDateRange(
                    from: range,
                    rawText: rawText,
                    periodUnit: periodUnit,
                    calendar: localCalendar
                ),
                source: source,
                policySummary: $0,
                effectiveRangeSummary: effective
            )
        } ?? .none
    }

    private func mergedDateResolution(
        _ primary: MarinaLiveDateResolution,
        _ comparison: MarinaLiveDateResolution
    ) -> MarinaLiveDateResolution {
        if comparison.intent == nil { return primary }
        let source = primary.source != .none ? primary.source : comparison.source
        let summary = [
            primary.policySummary,
            comparison.policySummary.map { "comparison{\($0)}" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
        .nilIfBlankForV2
        let effective = [
            primary.effectiveRangeSummary.map { "primary=\($0)" },
            comparison.effectiveRangeSummary.map { "comparison=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: ",")
        .nilIfBlankForV2
        return MarinaLiveDateResolution(
            intent: primary.intent,
            source: source,
            policySummary: summary,
            effectiveRangeSummary: effective
        )
    }

    private func explicitDatePhrase(in prompt: String) -> String? {
        let normalizedPrompt = normalized(prompt)
        let phrases = [
            "this month", "current month", "month to date", "last month", "previous month",
            "this week", "last week", "today", "yesterday", "this year", "last year"
        ]
        return phrases.first { normalizedPrompt.contains($0) }
    }

    private func isComparisonOnlyDatePhrase(_ phrase: String?, prompt: String) -> Bool {
        guard let phrase else { return false }
        let normalizedPhrase = normalized(phrase)
        guard normalizedPhrase == "last month" || normalizedPhrase == "previous month" || normalizedPhrase == "last week" || normalizedPhrase == "previous week" else {
            return false
        }
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.contains("compare") || normalizedPrompt.contains(" vs ") || normalizedPrompt.contains(" versus ") else {
            return false
        }
        return containsAny(["this month", "current month", "month to date", "this week", "current week", "this period", "current period"], in: normalizedPrompt) == false
    }

    private func inferredValueDirection(from normalizedPrompt: String) -> String? {
        if containsAny([" less", " lower", " reduce", " decrease", " cut "], in: " \(normalizedPrompt) ") {
            return "less"
        }
        if containsAny([" more", " extra", " increase", " add "], in: " \(normalizedPrompt) ") {
            return "more"
        }
        return nil
    }

    private func explicitLimit(in normalizedPrompt: String) -> Int? {
        guard let range = normalizedPrompt.range(of: #"\b\d{1,2}\b"#, options: .regularExpression) else {
            return nil
        }
        return Int(normalizedPrompt[range])
    }

    private func phraseAfter(_ delimiters: [String], in prompt: String) -> String? {
        let lowered = prompt.lowercased()
        for delimiter in delimiters {
            if let range = lowered.range(of: delimiter) {
                let suffix = prompt[range.upperBound...]
                return String(suffix)
                    .replacingOccurrences(of: #"(?i)\b(this|last|current|previous)\s+(month|week|year)\b"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ?."))
                    .nilIfBlankForV2
            }
        }
        return nil
    }

    private func cleanSpendTarget(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)['’]s\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(this|last|current|previous)\s+(month|week|year)\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bspending|spend|spent|budget|limit|rows?\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.'"))
    }

    private func cleanReconciliationTarget(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"(?i)['’]s\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(balance|allocation|settlement|rows?|reconciliation|account)\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ?.'"))
    }

    private func groundedModelDateText(_ rawValue: String?, prompt: String) -> String? {
        guard let rawValue = rawValue?.nilIfBlankForV2 else { return nil }
        let normalizedRaw = normalized(rawValue)
        guard normalizedRaw.isEmpty == false else { return nil }
        guard normalized(prompt).contains(normalizedRaw) else { return nil }
        guard rawValue.range(of: #"\b\d{4}\b"#, options: .regularExpression) != nil
                || relativeDatePhrases.contains(where: { normalizedRaw.contains($0) }) else {
            return nil
        }
        guard normalizedRaw.contains("budget") == false else { return nil }
        return rawValue
    }

    private var relativeDatePhrases: [String] {
        [
            "this month", "current month", "month to date", "last month", "previous month",
            "this week", "last week", "today", "yesterday", "this year", "last year"
        ]
    }

    private func droppedTargetSummary(
        payload: MarinaFoundationIntentEnvelopeV3Payload,
        promptDatePolicy: String?
    ) -> String? {
        var dropped: [String] = []
        for target in [payload.targetText, payload.secondaryTargetText].compactMap({ $0?.nilIfBlankForV2 }) {
            if isInvalidEntityTarget(target) {
                dropped.append("target=\(target)")
            }
        }
        if promptDatePolicy?.contains("aiDateDropped=") == true {
            dropped.append("dateTarget")
        }
        return dropped.isEmpty ? nil : dropped.joined(separator: ";")
    }

    private func isInvalidEntityTarget(_ value: String) -> Bool {
        isGenericTarget(value) || isTimeTarget(value)
    }

    private func isGenericTarget(_ value: String) -> Bool {
        [
            "spending", "total spending", "income", "actual income", "planned income",
            "incomeactual", "incomeplanned", "income actual", "income planned",
            "income comparison", "incomecomparison", "planned vs actual income",
            "active budget", "budget", "category", "categories", "transactions",
            "recent transactions", "savings", "savings status", "savings activity",
            "savingsactivity", "allocation rows", "allocationrows",
            "settlement rows", "settlementrows", "uncategorized spending",
            "linked cards", "linkedcards", "linked presets", "linkedpresets"
        ].contains(normalized(value))
    }

    private func isTimeTarget(_ value: String) -> Bool {
        let normalizedValue = normalized(value)
        if relativeDatePhrases.contains(normalizedValue) {
            return true
        }
        return normalizedValue.hasSuffix(" month")
            || normalizedValue.hasSuffix(" week")
            || normalizedValue.hasSuffix(" year")
    }

    private func isReadOnlyMutation(_ normalizedPrompt: String) -> Bool {
        let verbs = ["add", "create", "delete", "remove", "update", "edit", "move", "transfer", "settle", "allocate"]
        guard verbs.contains(where: { containsWord($0, in: normalizedPrompt) }) else { return false }
        return containsAny(["expense", "income", "budget", "card", "category", "preset", "savings", "settlement", "allocation"], in: normalizedPrompt)
    }

    private func containsWord(_ word: String, in text: String) -> Bool {
        text.split(separator: " ").contains { $0 == word }
    }

    private func containsAny(_ needles: [String], in haystack: String) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private func containsAll(_ needles: [String], in haystack: String) -> Bool {
        needles.allSatisfy { haystack.contains($0) }
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func token(_ value: String?) -> String? {
        value?
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .nilIfBlankForV2
    }

    private func amount(from rawValue: String?) -> Double? {
        guard let rawValue = rawValue?.nilIfBlankForV2 else { return nil }
        let cleaned = rawValue
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: "[^0-9.\\-]+", with: "", options: .regularExpression)
        return Double(cleaned)
    }

}

private extension String {
    var nilIfBlankForV2: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
