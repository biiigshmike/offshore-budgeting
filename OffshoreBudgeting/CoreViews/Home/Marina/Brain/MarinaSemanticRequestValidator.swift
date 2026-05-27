import Foundation

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
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaInterpretedSemanticRequest {
        var request = interpreted.request
        var notes = interpreted.diagnosticNotes
        var source = interpreted.source

        if request.expectedAnswerShape == .unsupported && request.unsupportedReason == nil {
            request.unsupportedReason = .unsupportedCombination
            notes.append("Validation added missing unsupported reason.")
        }

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation skipped for terminal semantic shape.")
            return interpretedWith(request: request, interpreted: interpreted, source: source, notes: notes)
        }

        let resolved = candidateResolver.resolve(interpreted: interpreted, snapshot: snapshot)
        request = resolved.request
        notes = resolved.diagnosticNotes
        source = resolved.source

        if request.expectedAnswerShape == .clarification || request.expectedAnswerShape == .unsupported {
            notes.append("Validation accepted resolver terminal semantic shape.")
            return interpretedWith(
                request: request,
                interpreted: resolved,
                source: source,
                notes: notes,
                clarificationChoices: resolved.clarificationChoices
            )
        }

        if let repaired = repairMerchantSpendIfNeeded(request, snapshot: snapshot) {
            request = repaired
            notes.append("Validation repaired unresolved card target into merchant text spend.")
            if source == .foundationModel {
                source = .repairedFoundationModel
            }
        }

        guard capabilityRegistry.supports(entity: request.entity, operation: request.operation) else {
            request = unsupported(.unsupportedCombination)
            notes.append("Validation rejected unsupported entity/operation capability.")
            return interpretedWith(request: request, interpreted: resolved, source: source, notes: notes)
        }

        if let rejected = rejectedRequest(for: request, snapshot: snapshot) {
            notes.append("Validation rejected semantic request: \(rejected.unsupportedReason?.rawValue ?? rejected.expectedAnswerShape.rawValue).")
            return interpretedWith(request: rejected, interpreted: interpreted, source: source, notes: notes)
        }

        notes.append("Validation accepted semantic request.")
        return interpretedWith(request: request, interpreted: interpreted, source: source, notes: notes)
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
}
