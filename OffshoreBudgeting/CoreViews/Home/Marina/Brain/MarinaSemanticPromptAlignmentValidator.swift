import Foundation

nonisolated enum MarinaSemanticPromptAlignmentRejectionCode: String, Codable, Equatable, Sendable {
    case safetyMismatch = "alignment.safetyMismatch"
    case entityMismatch = "alignment.entityMismatch"
    case projectionMismatch = "alignment.projectionMismatch"
    case operationMismatch = "alignment.operationMismatch"
    case measureMismatch = "alignment.measureMismatch"
    case dimensionMismatch = "alignment.dimensionMismatch"
    case dateRangeMismatch = "alignment.dateRangeMismatch"
    case dateSourceMismatch = "alignment.dateSourceMismatch"
    case targetMismatch = "alignment.targetMismatch"
    case targetSourceMismatch = "alignment.targetSourceMismatch"
    case sortMismatch = "alignment.sortMismatch"
    case countMismatch = "alignment.countMismatch"
    case expenseScopeMismatch = "alignment.expenseScopeMismatch"
    case incomeStateMismatch = "alignment.incomeStateMismatch"
    case categoryFilterMismatch = "alignment.categoryFilterMismatch"
    case continuationMismatch = "alignment.continuationMismatch"
    case scenarioMismatch = "alignment.scenarioMismatch"
    case answerShapeMismatch = "alignment.answerShapeMismatch"
}

nonisolated struct MarinaSemanticPromptAlignmentRejection: Equatable, Sendable {
    let code: MarinaSemanticPromptAlignmentRejectionCode
    let expectedDigest: MarinaFoundationModelCompiledRequestDigest
    let actualDigest: MarinaFoundationModelCompiledRequestDigest

    var reason: String { code.humanReadableReason }
    var expectedAnchor: String { expectedDigest.rendered }
}

nonisolated enum MarinaSemanticPromptAlignmentResult: Equatable, Sendable {
    case accepted(anchorID: String)
    case inconclusive
    case rejected(MarinaSemanticPromptAlignmentRejection)
}

/// Checks only strong, deterministic prompt anchors. It never creates, repairs,
/// or mutates a semantic request; unknown prompts remain model-owned.
nonisolated struct MarinaSemanticPromptAlignmentValidator {
    func validate(
        userInput: String,
        request: MarinaSemanticRequest,
        localeIdentifier: String = Locale.current.identifier
    ) -> MarinaSemanticPromptAlignmentResult {
        if let match = MarinaStarterPromptCatalog.match(
            prompt: userInput,
            localeIdentifier: localeIdentifier
        ) {
            return validate(
                request: request,
                contract: match.contract,
                anchorID: "starter.\(match.id.rawValue)"
            )
        }

        if let regression = regressionAnchor(for: userInput, localeIdentifier: localeIdentifier) {
            return validate(
                request: request,
                contract: regression.contract,
                anchorID: regression.id
            )
        }

        if isStrongReadOnlyMutation(userInput, localeIdentifier: localeIdentifier) {
            guard request.expectedAnswerShape == .unsupported,
                  request.unsupportedReason == .readOnly else {
                return .rejected(MarinaSemanticPromptAlignmentRejection(
                    code: .safetyMismatch,
                    expectedDigest: MarinaFoundationModelCompiledRequestDigest(
                        request: MarinaSemanticRequest(
                            entity: request.entity,
                            operation: request.operation,
                            projection: request.projection,
                            expectedAnswerShape: .unsupported,
                            unsupportedReason: .readOnly
                        )
                    ),
                    actualDigest: MarinaFoundationModelCompiledRequestDigest(request: request)
                ))
            }
            return .accepted(anchorID: "safety.readOnlyMutation")
        }

        return .inconclusive
    }

    private func validate(
        request: MarinaSemanticRequest,
        contract: MarinaStarterPromptCatalog.Contract,
        anchorID: String
    ) -> MarinaSemanticPromptAlignmentResult {
        if request.unsupportedReason != nil {
            return rejection(.safetyMismatch, "safety outcome", "read-only query", request, contract)
        }
        if request.entity != contract.entity {
            return rejection(.entityMismatch, "entity", contract.entity.rawValue, request, contract)
        }
        if request.projection != contract.projection {
            return rejection(.projectionMismatch, "projection", contract.projection.rawValue, request, contract)
        }
        if request.operation != contract.operation {
            return rejection(.operationMismatch, "operation", contract.operation.rawValue, request, contract)
        }
        if request.measure != contract.measure {
            return rejection(.measureMismatch, "measure", contract.measure.rawValue, request, contract)
        }
        if request.dimensions != contract.dimensions {
            return rejection(
                .dimensionMismatch,
                "dimensions",
                contract.dimensions.map(\.rawValue).joined(separator: ","),
                request,
                contract
            )
        }
        if request.dateRangeToken != contract.dateRange {
            return rejection(.dateRangeMismatch, "date range", contract.dateRange.rawValue, request, contract)
        }
        if request.dateRangeSource != contract.dateRangeSource {
            return rejection(.dateSourceMismatch, "date source", contract.dateRangeSource.rawValue, request, contract)
        }
        if let targetRejection = validateTarget(request: request, contract: contract) {
            return targetRejection
        }
        if request.sort != contract.sort {
            return rejection(
                .sortMismatch,
                "sort",
                contract.sort?.rawValue ?? "none",
                request,
                contract
            )
        }
        if request.resultLimit != contract.resultLimit {
            return rejection(
                .countMismatch,
                "result limit",
                contract.resultLimit.map(String.init) ?? "none",
                request,
                contract
            )
        }
        if request.expenseScope != contract.expenseScope {
            return rejection(
                .expenseScopeMismatch,
                "expense scope",
                contract.expenseScope?.rawValue ?? "none",
                request,
                contract
            )
        }
        if request.incomeState != contract.incomeState {
            return rejection(
                .incomeStateMismatch,
                "income state",
                contract.incomeState?.rawValue ?? "none",
                request,
                contract
            )
        }
        if request.categoryAvailabilityFilter != contract.categoryAvailabilityFilter {
            return rejection(
                .categoryFilterMismatch,
                "category filter",
                contract.categoryAvailabilityFilter?.rawValue ?? "none",
                request,
                contract
            )
        }
        if request.continuationIntent != .none || request.resultOffset != nil {
            return rejection(.continuationMismatch, "continuation", "none", request, contract)
        }
        if request.whatIfAmount != nil {
            return rejection(.scenarioMismatch, "what-if amount", "none", request, contract)
        }
        if request.expectedAnswerShape != contract.answerShape {
            return rejection(.answerShapeMismatch, "answer shape", contract.answerShape.rawValue, request, contract)
        }
        return .accepted(anchorID: anchorID)
    }

    private func validateTarget(
        request: MarinaSemanticRequest,
        contract: MarinaStarterPromptCatalog.Contract
    ) -> MarinaSemanticPromptAlignmentResult? {
        switch contract.target {
        case .absent:
            let hasTarget = request.targetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || request.textQuery?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || request.comparisonTargetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                || request.constraints.isEmpty == false
            guard hasTarget == false else {
                return rejection(.targetMismatch, "target", "absent", request, contract)
            }
        case let .named(expectedName, _, source):
            guard let actualName = request.targetName,
                  MarinaCanonicalTextNormalizer.areStronglyEquivalent(expectedName, actualName) else {
                return rejection(.targetMismatch, "target", "named", request, contract)
            }
            guard request.targetKindSource == source else {
                return rejection(.targetSourceMismatch, "target source", source.rawValue, request, contract)
            }
            guard request.comparisonTargetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                  request.constraints.isEmpty else {
                return rejection(.targetMismatch, "comparison target or additional filters", "absent", request, contract)
            }
        }
        return nil
    }

    private func rejection(
        _ code: MarinaSemanticPromptAlignmentRejectionCode,
        _: String,
        _: String,
        _ request: MarinaSemanticRequest,
        _ contract: MarinaStarterPromptCatalog.Contract
    ) -> MarinaSemanticPromptAlignmentResult {
        .rejected(MarinaSemanticPromptAlignmentRejection(
            code: code,
            expectedDigest: MarinaFoundationModelCompiledRequestDigest(contract: contract),
            actualDigest: MarinaFoundationModelCompiledRequestDigest(request: request)
        ))
    }

    private func regressionAnchor(
        for userInput: String,
        localeIdentifier: String
    ) -> (id: String, contract: MarinaStarterPromptCatalog.Contract)? {
        guard MarinaStarterPromptCatalog.languageTag(for: localeIdentifier) == "en" else { return nil }
        let canonical = MarinaCanonicalTextNormalizer.canonical(userInput)
        switch canonical {
        case MarinaCanonicalTextNormalizer.canonical("Which categories were over the limit for last month?"):
            return (
                "regression.categoryOverLimitPreviousMonth",
                .init(
                    entity: .category,
                    operation: .list,
                    measure: .categoryAvailability,
                    dateRange: .previousMonth,
                    dateRangeSource: .explicit,
                    categoryAvailabilityFilter: .over,
                    answerShape: .list
                )
            )
        case MarinaCanonicalTextNormalizer.canonical("What is my income for the current period?"):
            return (
                "regression.actualIncomeCurrentPeriod",
                .init(
                    entity: .income,
                    operation: .sum,
                    measure: .incomeAmount,
                    dateRangeSource: .explicit,
                    incomeState: .actual
                )
            )
        default:
            return nil
        }
    }

    private func isStrongReadOnlyMutation(
        _ userInput: String,
        localeIdentifier: String
    ) -> Bool {
        guard MarinaStarterPromptCatalog.languageTag(for: localeIdentifier) == "en" else { return false }
        let canonical = MarinaCanonicalTextNormalizer.canonical(userInput)
        let releaseSafetyAnchors = [
            "Delete my Apple Card.",
            "Remove every expense.",
            "Erase the Vacation budget.",
            "Delete Groceries.",
            "Create a new card.",
            "Add a $20 expense.",
            "Make a Dining category.",
            "Create next month's budget.",
            "Rename Groceries to Food.",
            "Edit my Apple Card.",
            "Move this expense.",
            "Change the budget dates."
        ].map(MarinaCanonicalTextNormalizer.canonical)
        if releaseSafetyAnchors.contains(canonical) { return true }

        let words = canonical.split(separator: " ").map(String.init)
        guard let firstWord = words.first,
              ["add", "change", "create", "delete", "edit", "erase", "move", "remove", "rename"].contains(firstWord) else {
            return false
        }
        let financialNouns: Set<String> = [
            "budget", "card", "category", "expense", "income", "preset", "saving", "savings", "transaction"
        ]
        return financialNouns.isDisjoint(with: words) == false
    }

}
