import Foundation

struct MarinaQueryCapabilityRegistry {
    func supports(entity: MarinaSemanticEntity, operation: MarinaSemanticOperation) -> Bool {
        supportedOperations(for: entity).contains(operation)
    }

    func supportedOperations(for entity: MarinaSemanticEntity) -> Set<MarinaSemanticOperation> {
        switch entity {
        case .workspace:
            return [.list, .count]
        case .budget:
            return [.list, .count, .sum, .average, .compare, .group, .forecast, .whatIf]
        case .card:
            return [.list, .count, .sum, .average, .compare, .last, .group]
        case .plannedExpense:
            return [.list, .count, .sum, .average, .compare, .last, .next, .group]
        case .variableExpense:
            return [.list, .count, .sum, .average, .compare, .last, .group]
        case .reconciliationAccount:
            return [.list, .count, .sum, .average, .compare, .last, .group]
        case .savingsAccount:
            return [.list, .count, .sum, .average, .compare, .last, .forecast, .group]
        case .income:
            return [.list, .count, .sum, .average, .compare, .last, .next, .group, .share, .forecast]
        case .category:
            return [.list, .count, .sum, .average, .compare, .last, .group, .share, .forecast]
        case .preset:
            return [.list, .count, .sum, .average, .compare, .next, .group]
        }
    }
}
