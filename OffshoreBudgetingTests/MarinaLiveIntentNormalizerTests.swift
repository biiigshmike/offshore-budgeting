import Foundation
import Testing
@testable import Offshore

struct MarinaLiveIntentNormalizerTests {
    @Test func normalizer_preservesFormulaMetadataWhenDroppingGenericCommandFilters() {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .average,
            datasets: [.variableExpenses],
            measure: .spend,
            includeFilters: [
                MarinaSemanticCommandFilter(
                    rawText: "spending",
                    allowedTypes: [.merchant]
                )
            ],
            formulaKind: .recurringChargeAnomaly,
            formulaFamily: .average,
            formulaMeasure: .variableBudgetImpact,
            formulaBacklogRecipe: .medianAmount,
            formulaFacets: MarinaFormulaFacets(
                thresholdRaw: "250",
                baselineRaw: "last month",
                assumptionRaw: "ignore refunds",
                excludeIncome: true
            )
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "Average spending using the formula.",
            operation: .average,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "spending",
                    typeHint: .merchant,
                    allowedTypeHints: [.merchant]
                )
            ],
            semanticCommand: command,
            formulaKind: .recurringChargeAnomaly,
            formulaFamily: .average,
            formulaMeasure: .variableBudgetImpact,
            formulaBacklogRecipe: .medianAmount,
            formulaFacets: command.formulaFacets
        )
        let interpretation = MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )

        let normalized = MarinaLiveIntentNormalizer().normalized(
            interpretation,
            prompt: candidate.rawPrompt,
            context: context(),
            defaultPeriodUnit: .month
        )

        let normalizedCommand = normalized.compatibilityCandidate.semanticCommand
        #expect(normalizedCommand?.includeFilters.isEmpty == true)
        #expect(normalizedCommand?.formulaKind == .recurringChargeAnomaly)
        #expect(normalizedCommand?.formulaFamily == .average)
        #expect(normalizedCommand?.formulaMeasure == .variableBudgetImpact)
        #expect(normalizedCommand?.formulaBacklogRecipe == .medianAmount)
        #expect(normalizedCommand?.formulaFacets.thresholdRaw == "250")
        #expect(normalizedCommand?.formulaFacets.baselineRaw == "last month")
        #expect(normalizedCommand?.formulaFacets.assumptionRaw == "ignore refunds")
        #expect(normalizedCommand?.formulaFacets.excludeIncome == true)
        #expect(normalized.compatibilityCandidate.formulaKind == .recurringChargeAnomaly)
        #expect(normalized.compatibilityCandidate.formulaFamily == .average)
        #expect(normalized.compatibilityCandidate.formulaMeasure == .variableBudgetImpact)
    }

    private func context() -> MarinaInterpretationContext {
        MarinaInterpretationContext(
            workspaceName: "Personal",
            defaultPeriodUnit: .month,
            sessionContext: MarinaSessionContext(),
            priorQueryContext: .empty,
            cardNames: ["Apple Card"],
            categoryNames: ["Groceries"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["May Budget"],
            allocationAccountNames: ["Alejandro"],
            aliasSummaries: [],
            now: date(2026, 5, 15)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
