import Foundation

enum MarinaQueryOwnershipStatus: String, Codable, CaseIterable, Equatable, Sendable {
    case universalOwned
    case legacyOwnedForNow
    case unsupportedGuardrail
}

struct MarinaUniversalOwnershipRecord: Equatable, Sendable {
    let scenario: MarinaUniversalRoutingScenario?
    let status: MarinaQueryOwnershipStatus
    let reason: String
    let legacyFallbackRequired: Bool
}

struct MarinaUniversalOwnershipRegistry: Sendable {
    static let current = MarinaUniversalOwnershipRegistry()

    let records: [MarinaUniversalOwnershipRecord]

    init(records: [MarinaUniversalOwnershipRecord] = MarinaUniversalOwnershipRegistry.universalOwnedRecords) {
        self.records = records
    }

    func record(for scenario: MarinaUniversalRoutingScenario) -> MarinaUniversalOwnershipRecord? {
        records.first { $0.scenario == scenario }
    }

    func status(for scenario: MarinaUniversalRoutingScenario) -> MarinaQueryOwnershipStatus {
        record(for: scenario)?.status ?? .legacyOwnedForNow
    }

    var universalOwnedScenarios: Set<MarinaUniversalRoutingScenario> {
        Set(records.compactMap { record in
            guard record.status == .universalOwned else { return nil }
            return record.scenario
        })
    }

    private static let universalOwnedRecords: [MarinaUniversalOwnershipRecord] = [
        universalOwned(.merchantVariableSpend, "Merchant variable spend has shadow, presentation, and debug-routing parity."),
        universalOwned(.categoryVariableSpend, "Category variable spend has shadow, presentation, and debug-routing parity."),
        universalOwned(.cardVariableSpend, "Card variable spend has shadow, presentation, and debug-routing parity."),
        universalOwned(.plannedExpenseSum, "Planned expense sum has shadow, presentation, and debug-routing parity."),
        universalOwned(.latestVariableExpense, "Latest variable expense has shadow, presentation, and debug-routing parity."),
        universalOwned(.biggestVariableExpenseRows, "Biggest variable expense rows have shadow, presentation, and debug-routing parity."),
        universalOwned(.nextPlannedExpense, "Next planned expense has shadow, presentation, and debug-routing parity."),
        universalOwned(.unifiedExpenseCategoryGroups, "Unified expense category groups have shadow, presentation, and debug-routing parity."),
        universalOwned(.unifiedExpenseCardGroups, "Unified expense card groups have manual fixture, presentation, and debug-routing parity."),
        universalOwned(.incomeTotal, "Income total has shadow, presentation, and debug-routing parity."),
        universalOwned(.incomeBySource, "Income by source has manual fixture, presentation, and debug-routing parity for all-income grouped requests."),
        universalOwned(.savingsTotalExplicitAccount, "Explicit savings account total has shadow, presentation, and debug-routing parity."),
        universalOwned(.reconciliationBalanceExplicitAccount, "Explicit reconciliation account balance has shadow, presentation, and debug-routing parity."),
        universalOwned(.budgetRemainingRoom, "Budget remaining room has shadow, presentation, and debug-routing parity."),
        universalOwned(.safeDailySpend, "Safe daily spend has shadow, presentation, and debug-routing parity.")
    ]

    private static func universalOwned(
        _ scenario: MarinaUniversalRoutingScenario,
        _ reason: String
    ) -> MarinaUniversalOwnershipRecord {
        MarinaUniversalOwnershipRecord(
            scenario: scenario,
            status: .universalOwned,
            reason: reason,
            legacyFallbackRequired: true
        )
    }
}
