import Foundation

struct MarinaSemanticValidationTrace: Equatable, Sendable {
    let interpreted: MarinaInterpretedSemanticRequest
    let resolverOutput: MarinaInterpretedSemanticRequest
    let candidateSearches: [MarinaCandidateSearchTrace]
}

struct MarinaSemanticRequestValidator {
    private let candidateResolver: MarinaSemanticCandidateResolver
    private let catalog: MarinaEntityCatalog

    init(
        candidateResolver: MarinaSemanticCandidateResolver = MarinaSemanticCandidateResolver(),
        catalog: MarinaEntityCatalog = MarinaEntityCatalog()
    ) {
        self.candidateResolver = candidateResolver
        self.catalog = catalog
    }

    func validate(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        candidateDateRange: HomeQueryDateRange? = nil
    ) -> MarinaInterpretedSemanticRequest {
        validateWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            candidateDateRange: candidateDateRange
        )
        .interpreted
    }

    func validateWithTrace(
        interpreted: MarinaInterpretedSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot,
        candidateDateRange: HomeQueryDateRange? = nil
    ) -> MarinaSemanticValidationTrace {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes
        var source = interpreted.source
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
                candidateSearches: []
            )
        }

        let resolved: MarinaInterpretedSemanticRequest
        let candidateSearches: [MarinaCandidateSearchTrace]
        if hasCompleteResolvedIdentity(request) {
            var identityBacked = interpreted
            identityBacked.diagnosticNotes.append("Validation preserved complete ID-backed target resolution.")
            resolved = identityBacked
            candidateSearches = []
        } else {
            let resolution = candidateResolver.resolveWithTrace(
                interpreted: interpreted,
                snapshot: snapshot,
                candidateDateRange: candidateDateRange
            )
            resolved = resolution.interpreted
            candidateSearches = resolution.candidateSearches
        }
        let resolverOutput = resolved
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
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches
            )
        }

        if request.constraints.contains(where: {
            $0.dimension == .date || $0.resolvedReference == nil
        }) {
            request = unsupported(.unresolvedEntity)
            notes.append("Validation rejected an unresolved or non-canonical typed constraint.")
            let rejected = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches
            )
        }

        if resolvedIdentityIsValid(request, snapshot: snapshot) == false {
            request = unsupported(.unresolvedEntity)
            notes.append("Validation rejected an ID-backed target outside the active Workspace or semantic shape.")
            let rejected = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches
            )
        }

        guard catalog.supports(entity: request.entity, projection: request.projection) == .supported,
              catalog.supports(entity: request.entity, operation: request.operation) == .supported else {
            request = unsupported(.unsupportedCombination)
            notes.append("Validation rejected unsupported entity/operation capability.")
            let rejected = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejected,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches
            )
        }

        if let rejected = rejectedRequest(for: request, snapshot: snapshot) {
            notes.append("Validation rejected semantic request: \(rejected.unsupportedReason?.rawValue ?? rejected.expectedAnswerShape.rawValue).")
            let rejectedInterpreted = interpretedWith(request: rejected, interpreted: resolved, source: source, notes: notes)
            return MarinaSemanticValidationTrace(
                interpreted: rejectedInterpreted,
                resolverOutput: resolverOutput,
                candidateSearches: candidateSearches
            )
        }

        notes.append("Validation accepted semantic request.")
        let accepted = interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
        return MarinaSemanticValidationTrace(
            interpreted: accepted,
            resolverOutput: resolverOutput,
            candidateSearches: candidateSearches
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

    private func hasCompleteResolvedIdentity(_ request: MarinaSemanticRequest) -> Bool {
        let hasPrimaryText = request.targetName?.isEmpty == false || request.textQuery?.isEmpty == false
        let hasComparisonText = request.comparisonTargetName?.isEmpty == false
        let hasUnresolvedConstraint = request.constraints.contains {
            $0.dimension == .date || $0.resolvedReference == nil
        }
        return (hasPrimaryText == false || request.resolvedTarget != nil)
            && (hasComparisonText == false || request.resolvedComparisonTarget != nil)
            && (hasPrimaryText || hasComparisonText)
            && hasUnresolvedConstraint == false
    }

    private func resolvedIdentityIsValid(
        _ request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        switch request.resolvedScope {
        case .workspace(let id):
            guard id == snapshot.workspace.id else { return false }
        case .budget(let id):
            guard snapshot.budgets.contains(where: { $0.id == id }) else { return false }
        case nil:
            break
        }

        let allowedEntities = allowedResolvedEntities(for: request)
        for reference in [request.resolvedTarget, request.resolvedComparisonTarget].compactMap({ $0 }) {
            guard allowedEntities.contains(reference.entity),
                  referenceBelongsToSnapshot(reference, snapshot: snapshot) else {
                return false
            }
        }

        for constraint in request.constraints {
            guard let reference = constraint.resolvedReference else { continue }
            guard constraintAllows(reference.entity, dimension: constraint.dimension),
                  referenceBelongsToSnapshot(reference, snapshot: snapshot) else {
                return false
            }
        }
        return true
    }

    private func constraintAllows(
        _ entity: MarinaSemanticEntity,
        dimension: MarinaSemanticDimension
    ) -> Bool {
        switch dimension {
        case .date:
            return false
        case .category:
            return entity == .category
        case .card:
            return entity == .card
        case .merchantText:
            return entity == .variableExpense || entity == .plannedExpense
        case .budget:
            return entity == .budget
        case .incomeSource:
            return entity == .income
        case .incomeSeries:
            return entity == .incomeSeries
        case .preset:
            return entity == .preset
        case .savingsAccount:
            return entity == .savingsAccount
        case .reconciliationAccount:
            return entity == .reconciliationAccount
        case .workspace:
            return entity == .workspace
        }
    }

    private func allowedResolvedEntities(
        for request: MarinaSemanticRequest
    ) -> Set<MarinaSemanticEntity> {
        var entities: Set<MarinaSemanticEntity> = [request.entity]
        for dimension in request.dimensions {
            switch dimension {
            case .workspace: entities.insert(.workspace)
            case .budget: entities.insert(.budget)
            case .card: entities.insert(.card)
            case .category: entities.insert(.category)
            case .merchantText:
                entities.insert(.variableExpense)
                entities.insert(.plannedExpense)
            case .incomeSource: entities.insert(.income)
            case .incomeSeries: entities.insert(.incomeSeries)
            case .preset: entities.insert(.preset)
            case .savingsAccount: entities.insert(.savingsAccount)
            case .reconciliationAccount: entities.insert(.reconciliationAccount)
            case .date:
                break
            }
        }
        return entities
    }

    private func referenceBelongsToSnapshot(
        _ reference: MarinaResolvedEntityReference,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        guard let id = reference.id else {
            return reference.entity == .variableExpense
                || reference.entity == .plannedExpense
                || reference.entity == .income
                || reference.entity == .incomeSeries
                || reference.entity == .workspace
        }

        switch reference.entity {
        case .workspace:
            return id == snapshot.workspace.id
        case .budget:
            return snapshot.budgets.contains { $0.id == id }
        case .card:
            return snapshot.cards.contains { $0.id == id }
        case .plannedExpense:
            return snapshot.plannedExpenses.contains { $0.id == id }
        case .variableExpense:
            return snapshot.variableExpenses.contains { $0.id == id }
        case .reconciliationAccount:
            return snapshot.reconciliationAccounts.contains { $0.id == id }
        case .savingsAccount:
            return snapshot.savingsAccounts.contains { $0.id == id }
        case .income:
            return snapshot.incomes.contains { $0.id == id }
        case .incomeSeries:
            return snapshot.incomeSeries.contains { $0.id == id }
        case .category:
            return snapshot.categories.contains { $0.id == id }
        case .preset:
            return snapshot.presets.contains { $0.id == id }
        }
    }

    private func rejectedRequest(
        for request: MarinaSemanticRequest,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaSemanticRequest? {
        switch request.entity {
        case .workspace:
            return nil
        case .budget:
            if request.dimensions.contains(.category),
               request.resolvedTarget?.entity != .category,
               let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name))
            }
            if request.resolvedTarget?.entity != .budget,
               let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.budgets, keyPath: \.name))
            }
            return nil
        case .card:
            if request.operation == .count && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if request.resolvedTarget == nil,
               let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            if request.resolvedComparisonTarget == nil,
               let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.cards, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .plannedExpense, .variableExpense:
            if request.dimensions.contains(.card),
               request.resolvedTarget?.entity != .card,
               let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.cards, keyPath: \.name))
            }
            return nil
        case .reconciliationAccount:
            guard request.resolvedTarget != nil || request.targetName != nil else {
                return unsupported(.unresolvedEntity)
            }
            if request.resolvedTarget == nil,
               let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.reconciliationAccounts, keyPath: \.name)) {
                return rejected
            }
            if request.dimensions.contains(.category), let categoryName = request.textQuery {
                return rejectedIfNeeded(resolutionStatus(named: categoryName, in: snapshot.categories, keyPath: \.name))
            }
            return nil
        case .savingsAccount:
            if request.resolvedTarget == nil, let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.savingsAccounts, keyPath: \.name))
            }
            return nil
        case .income:
            if request.resolvedTarget == nil, let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: incomeSources(snapshot), keyPath: \.self))
            }
            return nil
        case .incomeSeries:
            if request.operation == .list || request.operation == .count {
                return nil
            }
            if request.resolvedTarget == nil, let targetName = request.targetName {
                return rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.incomeSeries, keyPath: \.source))
            }
            return nil
        case .category:
            if request.operation == .group && request.targetName == nil && request.comparisonTargetName == nil {
                return nil
            }
            if request.resolvedTarget == nil,
               let targetName = request.targetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: targetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            if request.resolvedComparisonTarget == nil,
               let comparisonTargetName = request.comparisonTargetName,
               let rejected = rejectedIfNeeded(resolutionStatus(named: comparisonTargetName, in: snapshot.categories, keyPath: \.name)) {
                return rejected
            }
            return nil
        case .preset:
            if request.operation == .list || request.operation == .next || request.operation == .group {
                return nil
            }
            if request.resolvedTarget == nil, let targetName = request.targetName {
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

    private func incomeSources(_ snapshot: MarinaWorkspaceSnapshot) -> [String] {
        Array(Set(snapshot.incomes.map(\.source)))
    }
    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .uppercased()
    }
}
