import Foundation
import Testing
@testable import Offshore

#if DEBUG
struct MarinaUniversalRoutingDebugFormatterTests {
    private let formatter = MarinaUniversalRoutingDebugFormatter()

    @Test func universalSuccessSummaryIncludesCoreRoutingFields() {
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            scenario: .merchantVariableSpend,
            usedUniversal: true,
            fallbackReason: nil,
            notes: ["Universal routing succeeded."]
        )

        let summary = formatter.summary(from: diagnostics)

        #expect(summary.contains("Universal: used"))
        #expect(summary.contains("Scenario: merchantVariableSpend"))
        #expect(summary.contains("Entity: variableExpense"))
        #expect(summary.contains("Operation: sum"))
        #expect(summary.contains("Measure: budgetImpact"))
        #expect(summary.contains("Fallback: none"))
        #expect(summary.contains("- Universal routing succeeded."))
    }

    @Test func disabledFallbackSummaryFormatsClearly() {
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            scenario: .merchantVariableSpend,
            usedUniversal: false,
            fallbackReason: .disabled,
            notes: ["Universal routing policy is disabled."]
        )

        let summary = formatter.summary(from: diagnostics)

        #expect(summary.contains("Universal: fallback"))
        #expect(summary.contains("Scenario: merchantVariableSpend"))
        #expect(summary.contains("Fallback: disabled"))
        #expect(summary.contains("- Universal routing policy is disabled."))
    }

    @Test func notAllowlistedFallbackSummaryShowsNoScenarioWhenUnmapped() {
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: .budget,
            operation: .forecast,
            measure: .burnRate,
            usedUniversal: false,
            fallbackReason: .notAllowlisted,
            notes: ["Request is not allowlisted for universal routing."]
        )

        let summary = formatter.summary(from: diagnostics)

        #expect(summary.contains("Universal: fallback"))
        #expect(summary.contains("Scenario: none"))
        #expect(summary.contains("Entity: budget"))
        #expect(summary.contains("Operation: forecast"))
        #expect(summary.contains("Measure: burnRate"))
        #expect(summary.contains("Fallback: notAllowlisted"))
    }

    @Test func runnerUnsupportedFallbackSummaryIncludesRunnerReason() {
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            scenario: .savingsTotalExplicitAccount,
            usedUniversal: false,
            fallbackReason: .unsupportedRunner,
            notes: [
                "Scenario=savingsTotalExplicitAccount",
                "Runner unsupported=measureNotAvailable"
            ]
        )

        let summary = formatter.summary(from: diagnostics)

        #expect(summary.contains("Scenario: savingsTotalExplicitAccount"))
        #expect(summary.contains("Fallback: unsupportedRunner"))
        #expect(summary.contains("- Runner unsupported=measureNotAvailable"))
    }

    @Test func formatterDoesNotIncludeAnswerCopy() {
        let answerCopy = "Emergency savings total should not appear"
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            scenario: .savingsTotalExplicitAccount,
            usedUniversal: true,
            fallbackReason: nil,
            notes: ["Universal routing succeeded."]
        )

        let summary = formatter.summary(from: diagnostics)

        #expect(summary.contains(answerCopy) == false)
    }
}
#endif
