import Foundation
import Testing
@testable import Offshore

struct MarinaMetricContractRegistryTests {
    @Test func registry_declaresAllSeedContractsWithFinancialSemantics() {
        let registry = MarinaMetricContractRegistry.current
        let expectedIDs = Set(MarinaMetricContractID.allCases)
        let actualIDs = Set(registry.contracts.map(\.id))

        #expect(registry.contracts.count == expectedIDs.count)
        #expect(registry.contracts.count >= 60)
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

    @Test func resolver_mapsFormulaNamePhrasesToStableContractIDs() {
        let resolver = MarinaMetricContractResolver()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "income by source",
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
                    message: "formula phrase"
                )
            )
        )

        #expect(resolution?.contract.id == .incomeBySource)
        #expect(resolution?.match == .formulaPhrase)
    }

    @Test func resolver_mapsEveryFormulaNamePhraseToStableContractIDs() {
        let resolver = MarinaMetricContractResolver()

        for contract in MarinaMetricContractRegistry.current.contracts {
            for prompt in Set([contract.id.rawValue, contract.formulaName, spaced(contract.id.rawValue), spaced(contract.formulaName)]) {
                let candidate = MarinaQueryPlanCandidate(
                    source: .foundationModels,
                    rawPrompt: prompt,
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
                            message: "formula phrase"
                        )
                    )
                )

                #expect(resolution?.contract.id == contract.id, "Prompt '\(prompt)' should resolve \(contract.id.rawValue).")
                #expect(resolution?.match == .formulaPhrase)
            }
        }
    }

    @Test func responseBuilder_makesKnownPartialContractsVisible() throws {
        let contract = try #require(
            MarinaMetricContractRegistry.current.contract(for: .subscriptionSpend)
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
        #expect(answer.rows.contains { $0.title == "Metric contract" && $0.value == "subscriptionSpend" })
        #expect(answer.rows.contains { $0.title == "Amount basis" && $0.value == "budget impact" })
        #expect(answer.rows.contains { $0.title == "Source rows" && $0.value.contains("PlannedExpense") && $0.value.contains("Preset") })
        #expect(answer.rows.contains { $0.title == "Refused substitution" && $0.value.contains("subscriptions") })
    }

    @Test func expandedRegistry_declaresFormulaContractsAcrossUserFacingSurfaces() throws {
        let registry = MarinaMetricContractRegistry.current

        let phaseA: [MarinaMetricContractID] = [
            .periodOverview, .safeSpendToday, .forecastSavings, .periodCashFlow,
            .spendTrendSummary, .largestTransactions, .mostFrequentTransactions,
            .nextPlannedExpense
        ]
        let phaseB: [MarinaMetricContractID] = [
            .budgetSavingsSummary, .budgetIncomeSummary, .budgetExpenseMix,
            .budgetLinkedCardSpend, .budgetLinkedPresetForecast, .budgetCategoryLimitStatus,
            .budgetOverlapImpact, .budgetDeletionImpactPreview, .cardSpendTotal,
            .cardLedgerSummary, .cardBudgetImpactSummary, .cardPlannedVsActual,
            .cardCategoryMix, .cardMerchantMix, .cardFutureCommitments,
            .cardCreditRefundImpact, .cardDeletionImpactPreview
        ]
        let phaseC: [MarinaMetricContractID] = [
            .reconciliationBalance, .reconciliationPeriodActivity,
            .reconciliationSettlementHistory, .reconciliationUnsettledItems,
            .reconciliationCategoryMix, .allocationGrossVsOwnedImpact,
            .savingsRunningTotal, .savingsPeriodMovement, .savingsAdjustmentTotal,
            .savingsOffsetUsage, .savingsLedgerByKind, .incomeBySource,
            .incomeTimingVariance, .incomeAverageActual, .incomeSourceShare
        ]
        let phaseD: [MarinaMetricContractID] = [
            .categorySpendSummary, .categoryTrend, .categoryMerchantDrivers,
            .grossVsOwnedSpendBridge, .presetDueSoon, .presetHighestCost,
            .presetBudgetCoverage, .presetActualVariance, .presetSchedulePreview,
            .presetArchiveImpact, .presetDeletionImpactPreview
        ]

        for id in phaseA + phaseB + phaseC + phaseD {
            let contract = try #require(registry.contract(for: id))
            #expect(contract.sourceModels.isEmpty == false)
            #expect(contract.dateRangeBehavior.isEmpty == false)
            #expect(contract.neverSilentlySubstituteRules.isEmpty == false)
            #expect(contract.workspaceScope == "selected workspace")
        }
    }

    @Test func expandedRegistry_declaresDistinctAmountBasesForNonSpendMoney() throws {
        let registry = MarinaMetricContractRegistry.current

        let incomeVariance = try #require(registry.contract(for: .incomeActualVsExpected))
        let incomeBySource = try #require(registry.contract(for: .incomeBySource))
        let savingsTotal = try #require(registry.contract(for: .savingsRunningTotal))
        let savingsMovement = try #require(registry.contract(for: .savingsPeriodMovement))
        let savingsAdjustment = try #require(registry.contract(for: .savingsAdjustmentTotal))
        let savingsOffset = try #require(registry.contract(for: .savingsOffsetUsage))
        let settlementHistory = try #require(registry.contract(for: .reconciliationSettlementHistory))
        let cardLedger = try #require(registry.contract(for: .cardLedgerSummary))
        let cardSpend = try #require(registry.contract(for: .cardSpendTotal))
        let cardImpact = try #require(registry.contract(for: .cardBudgetImpactSummary))

        #expect(incomeVariance.amountBasis == .actualIncome)
        #expect(incomeBySource.amountBasis == .actualIncome)
        #expect(savingsTotal.amountBasis == .savingsRunningTotal)
        #expect(savingsMovement.amountBasis == .savingsMovement)
        #expect(savingsAdjustment.amountBasis == .savingsAdjustment)
        #expect(savingsOffset.amountBasis == .savingsOffset)
        #expect(settlementHistory.amountBasis == .reconciliationSettlement)
        #expect(cardLedger.amountBasis == .ledgerSigned)
        #expect(cardSpend.amountBasis == .cardDisplaySpend)
        #expect(cardImpact.amountBasis == .budgetImpact)
    }

    @Test func formulaContracts_lockHighRiskRefusalRules() throws {
        let registry = MarinaMetricContractRegistry.current

        let subscription = try #require(registry.contract(for: .subscriptionSpend))
        #expect(subscription.neverSilentlySubstituteRules.joined(separator: " ").contains("recurring expenses"))

        let reconciliation = try #require(registry.contract(for: .reconciliationOwedThisMonth))
        #expect(reconciliation.sourceModels.contains("ExpenseAllocation"))
        #expect(reconciliation.sourceModels.contains("AllocationSettlement"))
        #expect(reconciliation.neverSilentlySubstituteRules.joined(separator: " ").contains("savings"))

        let cardOverspending = try #require(registry.contract(for: .cardOverspendingDriver))
        #expect(cardOverspending.neverSilentlySubstituteRules.joined(separator: " ").contains("raw card spend"))

        let plannedVsActual = try #require(registry.contract(for: .plannedVsActualSpend))
        #expect(plannedVsActual.neverSilentlySubstituteRules.joined(separator: " ").contains("actualAmount == 0"))

        let presetDelete = try #require(registry.contract(for: .presetDeletionImpactPreview))
        #expect(presetDelete.neverSilentlySubstituteRules.joined(separator: " ").contains("Preview only"))
    }

    @Test func entityQueryContracts_areSeparateFromMetricFormulas() throws {
        let registry = MarinaEntityQueryContractRegistry.current
        let expectedIDs = Set(MarinaEntityQueryContractID.allCases)
        let actualIDs = Set(registry.contracts.map(\.id))

        #expect(actualIDs == expectedIDs)
        let metricRawValues = Set(MarinaMetricContractID.allCases.map(\.rawValue))
        let entityRawValues = Set(expectedIDs.map(\.rawValue))
        #expect(metricRawValues.intersection(entityRawValues).isEmpty)

        for contract in registry.contracts {
            #expect(contract.acceptedObjectTypes.isEmpty == false)
            #expect(contract.sourceModels.isEmpty == false)
            #expect(contract.dateRangeBehavior.isEmpty == false)
            #expect(contract.neverSilentlySubstituteRules.isEmpty == false)
            #expect(contract.workspaceScope == "selected workspace")
        }

        let deletion = try #require(registry.contract(for: .deletionImpactPreview))
        #expect(deletion.supportStatus == .contractOnly)
        #expect(deletion.neverSilentlySubstituteRules.joined(separator: " ").contains("Preview only"))
    }

    private func spaced(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]", with: " ", options: .regularExpression)
            .lowercased()
    }
}
