import Foundation
import Testing
@testable import Offshore

struct MarinaMetricContractRegistryTests {
    @Test func registry_declaresAllSeedContractsWithFinancialSemantics() {
        let registry = MarinaMetricContractRegistry.current
        let expectedIDs = Set(MarinaMetricContractID.allCases)
        let actualIDs = Set(registry.contracts.map(\.id))

        #expect(registry.contracts.count == 20)
        #expect(actualIDs == expectedIDs)

        for contract in registry.contracts {
            #expect(contract.seedPrompt.isEmpty == false)
            #expect(contract.formulaName.isEmpty == false)
            #expect(contract.acceptedSubjects.isEmpty == false)
            #expect(contract.acceptedOperations.isEmpty == false)
            #expect(contract.sourceModels.isEmpty == false)
            #expect(contract.amountBasisDescription.isEmpty == false)
            #expect(contract.dateRangeBehavior.isEmpty == false)
            #expect(contract.workspaceScope == "selected workspace")
            #expect(contract.neverSilentlySubstituteRules.isEmpty == false)
            #expect(contract.regressionFixtureIdea.isEmpty == false)
        }
    }

    @Test func resolver_mapsAllSeedPromptsToStableContractIDs() {
        let resolver = MarinaMetricContractResolver()

        for contract in MarinaMetricContractRegistry.current.contracts {
            let candidate = MarinaQueryPlanCandidate(
                source: .foundationModels,
                rawPrompt: contract.seedPrompt,
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedOperation
            )
            let resolved = MarinaResolvedQueryCandidate(
                candidate: candidate,
                resolvedTargets: [],
                unresolvedMentions: [],
                ambiguousMentions: [],
                primaryDateRange: nil,
                comparisonDateRange: nil
            )

            let resolution = resolver.resolve(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: nil,
                outcome: .unsupported(
                    MarinaTypedUnsupportedResponse(
                        kind: .unsupportedOperation,
                        message: "seed"
                    )
                )
            )

            #expect(resolution?.contract.id == contract.id)
            #expect(resolution?.match == .seedPrompt)
        }
    }

    @Test func responseBuilder_makesKnownMissingContractsVisible() throws {
        let contract = try #require(
            MarinaMetricContractRegistry.current.contract(for: .upcomingExpensesBeforeNextIncome)
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: contract.seedPrompt,
            unsupportedHint: .unsupportedOperation
        )

        let answer = MarinaMetricContractResponseBuilder().unsupportedAnswer(
            contract: contract,
            candidate: candidate
        )

        #expect(answer.title == "Marina knows this metric, but cannot run it yet")
        #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == "upcomingExpensesBeforeNextIncome" })
        #expect(answer.rows.contains { $0.title == "Amount basis" && $0.value == "budget impact" })
        #expect(answer.rows.contains { $0.title == "Source rows" && $0.value.contains("PlannedExpense") && $0.value.contains("Income") })
        #expect(answer.rows.contains { $0.title == "Refused substitution" && $0.value.contains("upcoming expenses") })
    }
}
