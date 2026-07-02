import Foundation

struct MarinaSemanticValidationTrace: Equatable, Sendable {
    let interpreted: MarinaInterpretedSemanticRequest
    let resolverOutput: MarinaInterpretedSemanticRequest
    let candidateSearches: [MarinaCandidateSearchTrace]
    let explicitPromptTargets: [String]
}

struct MarinaSemanticRequestValidator {
    private let candidateResolver: MarinaSemanticCandidateResolver
    private let capabilityRegistry: MarinaQueryCapabilityRegistry

    init(
        candidateResolver: MarinaSemanticCandidateResolver = MarinaSemanticCandidateResolver(),
        capabilityRegistry: MarinaQueryCapabilityRegistry = MarinaQueryCapabilityRegistry()
    ) {
        self.candidateResolver = candidateResolver
        self.capabilityRegistry = capabilityRegistry
    }

    func validate(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        originalPrompt: String? = nil
    ) -> MarinaInterpretedSemanticRequest {
        validateWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            originalPrompt: originalPrompt
        )
        .interpreted
    }

    func validateWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        originalPrompt: String? = nil
    ) -> MarinaSemanticValidationTrace {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes
        var source = interpreted.source
        let explicitTargets = explicitPromptTargets(in: originalPrompt, snapshot: snapshot)

        if request.expectedAnswerShape == .unsupported && request.unsupportedReason == nil {
            request.unsupportedReason = .unsupportedCombination
            notes.append("Validation added missing unsupported reason.")
        }

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation skipped for terminal semantic shape.")
            let terminal = interpretedWith(request: request, interpreted: interpreted, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: terminal,
                resolverOutput: terminal,
                candidateSearches: [],
                explicitPromptTargets: explicitTargets
            )
        }

        let resolution = candidateResolver.resolveWithTrace(interpreted: interpreted, snapshot: snapshot)
        let resolved = resolution.interpreted
        request = resolved.request
        notes = resolved.diagnosticNotes
        source = resolved.source

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation accepted resolver terminal semantic shape.")
            let terminal = interpretedWith(
                request: request,
                interpreted: resolved,
                source: source,
                notes: notes,
                clarificationChoices: resolved.clarificationChoices
            )
            return MarinaSemanticValidationTrace(
                interpreted: terminal,
                resolverOutput: resolved,
                candidateSearches: resolution.candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        if let repaired = repairMerchantSpendIfNeeded(request, snapshot: snapshot) {
            request = repaired
            notes.append("Validation repaired unresolved card target into merchant text spend.")
            if source == .foundationModel {
                source = .repairedFoundationModel
            }
        }

        if shouldEnforcePromptTargetRetention(source: source),
           let targetLoss = targetLossRejection(for: request, explicitTargets: explicitTargets) {
            notes.append("Validation rejected semantic request because prompt target(s) were not retained: \(targetLoss.joined(separator: ", ")).")
            let rejected = interpretedWith(
                request: unsupported(.unresolvedEntity),
                interpreted: resolved,
                source: source,
                notes: notes,
                clarificationChoices: resolved.clarificationChoices
            )
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolved,
                candidateSearches: resolution.candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        guard capabilityRegistry.supports(entity: request.entity, operation: request.operation) else {
            request = unsupported(.unsupportedCombination)
            notes.append("Validation rejected unsupported entity/operation capability.")
            let rejected = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolved,
                candidateSearches: resolution.candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        if let rejected = rejectedRequest(for: request, snapshot: snapshot) {
            notes.append("Validation rejected semantic request: \(rejected.unsupportedReason?.rawValue ?? rejected.expectedAnswerShape.rawValue).")
            let rejectedInterpreted = interpretedWith(request: rejected, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejectedInterpreted,
                resolverOutput: resolved,
                candidateSearches: resolution.candidateSearches,
                explicitPromptTargets: explicitTargets
            )
        }

        notes.append("Validation accepted semantic request.")
        let accepted = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
        return MarinaSemanticValidationTrace(
            interpreted: accepted,
            resolverOutput: resolved,
            candidateSearches: resolution.candidateSearches,
            explicitPromptTargets: explicitTargets
        )
    }

    private func interpretedWith(
        request: MarinaSemanticRequest,
        interpreted: MarinaInterpretedSemanticRequest,
        source: MarinaSemanticSource,
        notes: [String],
        clarificationChoices: MarinaClarificationChoices? = nil
    ) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: interpreted.confidence,
            source: source,
            diagnosticNotes: notes,
            clarificationChoices: clarificationChoices ?? interpreted.clarificationChoices
        )
    }

    private func repairMerchantSpendIfNeeded(
        _ request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        guard request.operation == .sum,
              let targetName = request.targetName,
              merchantExists(targetName, snapshot: snapshot) else {
            return nil
        }

        if request.entity == .card,
           resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name) == .missing {
            var repaired = request
            repaired.entity = .variableExpense
            repaired.dimensions = unique(repaired.dimensions.filter { $0 != .card } + [.merchantText])
            repaired.targetName = nil
            repaired.textQuery = request.textQuery ?? targetName
            repaired.expenseScope = .variable
            repaired.expectedAnswerShape = .metric
            return repaired
        }

        if (request.entity == .variableExpense || request.entity == .plannedExpense),
           request.dimensions.contains(.card) == false,
           request.textQuery == nil {
            var repaired = request
            repaired.dimensions = unique(repaired.dimensions + [.merchantText])
            repaired.targetName = nil
            repaired.textQuery = targetName
            repaired.expenseScope = request.entity == .plannedExpense ? .planned : .variable
            repaired.expectedAnswerShape = .metric
            return repaired
        }

        return nil
    }

    private func rejectedRequest(
        for request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        switch request.entity {
        case .workspace:
            return nil
        case .budget:
            if request.dimensions.contains(.category), let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name))
            }
            return nil
        case .card:
            if request.operation == .count && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            if let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .plannedExpense, .variableExpense:
            if request.dimensions.contains(.card), let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name))
            }
            return nil
        case .reconciliationAccount:
            guard let targetName = request.targetName else {
                return unsupported(.unresolvedEntity)
            }
            if let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.reconciliationAccounts, keyPath: \.name)) {
                return rejected
            }
            if request.dimensions.contains(.category), let categoryName = request.textQuery {
                return rejectedIfNeeded(resolutionStatus(named: categoryName, in: snapshot.categories, keyPath: \.name))
            }
            return nil
        case .savingsAccount:
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.savingsAccounts, keyPath: \.name))
            }
            return nil
        case .income:
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: incomeSources(snapshot), keyPath: \.self))
            }
            return nil
        case .category:
            if request.operation == .group && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            if let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .preset:
            if request.operation == .list || request.operation == .next || request.operation == .group {
                return nil
            }
            if let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.presets, keyPath: \.title))
            }
            return nil
        }
    }

    private func rejectedIfNeeded(_ status: ResolutionStatus) -> MarinaSemanticRequest? {
        switch status {
        case .resolved:
            return nil
        case .missing:
            return unsupported(.unresolvedEntity)
        case .ambiguous:
            return clarification("Which matching record should Marina use?")
        }
    }

    private func unsupported(_ reason: MarinaSemanticUnsupportedReason) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: reason
        )
    }

    private func clarification(_ question: String) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .clarification,
            clarificationQuestion: question,
            unsupportedReason: .ambiguousEntity
        )
    }

    private enum ResolutionStatus {
        case resolved
        case missing
        case ambiguous
    }

    private func resolutionStatus<T>(
        named name: String,
        in values: [T],
        keyPath: KeyPath<T, String>
    ) -> ResolutionStatus {
        let normalized = normalize(name)
        let exactMatches = values.filter { normalize($0[keyPath: keyPath]) == normalized }
        if exactMatches.count > 1 {
            return .ambiguous
        }
        if exactMatches.count == 1 {
            return .resolved
        }
        return values.contains { normalize($0[keyPath: keyPath]).contains(normalized) } ? .resolved : .missing
    }

    private func merchantExists(_ text: String, snapshot: MarinaWorkspaceSnapshot) -> Bool {
        let normalized = normalize(text)
        return snapshot.variableExpenses.contains { normalize($0.descriptionText).contains(normalized) }
            || snapshot.plannedExpenses.contains { normalize($0.title).contains(normalized) }
    }

    private func incomeSources(_ snapshot: MarinaWorkspaceSnapshot) -> [String] {
        Array(Set(snapshot.incomes.map(\.source)))
    }

    private func explicitPromptTargets(
        in prompt: String?,
        snapshot: MarinaWorkspaceSnapshot
    ) -> [String] {
        guard let prompt, prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return []
        }

        let normalizedPrompt = targetNormalized(prompt)
        let names = snapshot.cards.map(\.name)
            + snapshot.categories.map(\.name)
            + snapshot.presets.map(\.title)
            + Array(Set(snapshot.incomes.map(\.source)))
            + snapshot.savingsAccounts.map(\.name)
            + snapshot.reconciliationAccounts.map(\.name)
            + snapshot.budgets.map(\.name)
            + snapshot.variableExpenses.map(\.descriptionText)
            + snapshot.plannedExpenses.map(\.title)

        var seen: Set<String> = []
        var result: [String] = []
        for name in names {
            let normalizedName = targetNormalized(name)
            guard normalizedName.isEmpty == false,
                  normalizedPrompt.contains(normalizedName),
                  seen.contains(normalizedName) == false else {
                continue
            }
            seen.insert(normalizedName)
            result.append(name)
        }
        return result
    }

    private func targetLossRejection(
        for request: MarinaSemanticRequest,
        explicitTargets: [String]
    ) -> [String]? {
        guard explicitTargets.isEmpty == false,
              request.expectedAnswerShape != .clarification,
              request.expectedAnswerShape != .unsupported else {
            return nil
        }

        let retainedText = [
            request.targetName,
            request.comparisonTargetName,
            request.textQuery,
            request.targetDisplayName
        ]
        .compactMap { $0 }
        .map(targetNormalized)
        .joined(separator: " ")

        let missing = explicitTargets.filter { target in
            let normalizedTarget = targetNormalized(target)
            guard normalizedTarget.isEmpty == false else { return false }
            return retainedText.contains(normalizedTarget) == false
        }

        return missing.isEmpty ? nil : missing
    }

    private func shouldEnforcePromptTargetRetention(source: MarinaSemanticSource) -> Bool {
        source == .foundationModel || source == .repairedFoundationModel
    }

    private func unique(_ dimensions: [MarinaSemanticDimension]) -> [MarinaSemanticDimension] {
        var result: [MarinaSemanticDimension] = []
        for dimension in dimensions where result.contains(dimension) == false {
            result.append(dimension)
        }
        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }

    private func targetNormalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "[^A-Za-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .lowercased()
    }
}
