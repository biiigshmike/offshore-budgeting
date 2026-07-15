import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaClarificationChoiceContractTests {
    @Test func matchingRequiresExactlyOneChoice() {
        let first = choice(
            meaningKey: "primary|category|one",
            title: "Groceries",
            aliases: ["category", "grocery"]
        )
        let second = choice(
            meaningKey: "primary|variableExpense|two",
            title: "Grocery Outlet",
            aliases: ["merchant", "grocery"]
        )
        let choices = MarinaClarificationChoices(
            question: "Which Grocery meaning?",
            choices: [first, second]
        )

        #expect(choices.choice(matching: "grocery") == nil)
        #expect(choices.choice(matching: "category")?.id == first.id)
        #expect(choices.choice(matching: "merchant")?.id == second.id)
        #expect(choices.choice(matching: first.meaningKey)?.id == first.id)
        #expect(choices.choice(matching: "unknown") == nil)
    }

    @Test func comparisonTargetPatchPreservesResolvedPrimaryIdentity() {
        let workspaceID = UUID()
        let primaryID = UUID()
        let comparisonID = UUID()
        let primaryReference = MarinaResolvedEntityReference(
            entity: .card,
            id: primaryID,
            displayName: "Apple Card",
            provenance: .candidateResolver
        )
        let comparisonReference = MarinaResolvedEntityReference(
            entity: .card,
            id: comparisonID,
            displayName: "Chase Card",
            provenance: .clarificationChoice
        )
        let request = MarinaSemanticRequest(
            entity: .card,
            operation: .compare,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: "Apple Card",
            comparisonTargetName: "Chase",
            resolvedTarget: primaryReference,
            resolvedScope: .workspace(workspaceID),
            expectedAnswerShape: .comparison
        )
        let patch = MarinaClarificationTargetPatch(
            slot: .comparison,
            reference: comparisonReference,
            scope: .workspace(workspaceID)
        )
        let choice = MarinaClarificationChoice(
            meaningKey: "comparison|card|\(comparisonID.uuidString)",
            title: "Chase Card",
            subtitle: "Use Chase Card as the comparison card.",
            aliases: ["chase card"],
            targetPatch: patch,
            request: request
        )

        #expect(choice.executableRequest.resolvedTarget == primaryReference)
        #expect(choice.executableRequest.resolvedComparisonTarget == comparisonReference)
        #expect(choice.executableRequest.resolvedScope == .workspace(workspaceID))
    }

    @Test func subtitleMeaningAndPatchSurviveCodingRoundTrip() throws {
        let workspaceID = UUID()
        let categoryID = UUID()
        let reference = MarinaResolvedEntityReference(
            entity: .category,
            id: categoryID,
            displayName: "Groceries",
            provenance: .clarificationChoice
        )
        let original = MarinaClarificationChoice(
            meaningKey: "primary|category|\(categoryID.uuidString)",
            title: "Groceries",
            kindLabel: "Category",
            subtitle: "Use the Groceries category.",
            aliases: ["category"],
            targetPatch: MarinaClarificationTargetPatch(
                slot: .primary,
                reference: reference,
                scope: .workspace(workspaceID)
            ),
            request: MarinaSemanticRequest(
                entity: .category,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                targetName: "Groceries",
                expectedAnswerShape: .metric
            )
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MarinaClarificationChoice.self, from: data)

        #expect(decoded == original)
        #expect(decoded.subtitle == "Use the Groceries category.")
        #expect(decoded.executableRequest.resolvedTarget == reference)
    }

    @Test func lifecycleCommitsOnlyAcceptedNonClarificationAnswers() {
        let unresolved = MarinaClarificationChoices(
            question: "Which one?",
            choices: [choice(meaningKey: "one", title: "One", aliases: ["one"])]
        )
        var resolved = unresolved
        resolved.resolvedChoiceID = resolved.choices[0].id

        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: true,
            executionSucceeded: true,
            answerAttachment: nil
        ))
        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: false,
            executionSucceeded: true,
            answerAttachment: nil
        ) == false)
        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: nil,
            executionSucceeded: true,
            answerAttachment: nil
        ) == false)
        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: true,
            executionSucceeded: false,
            answerAttachment: nil
        ) == false)
        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: true,
            executionSucceeded: true,
            answerAttachment: .clarificationChoices(unresolved)
        ) == false)
        #expect(MarinaClarificationResolutionLifecycle.shouldCommit(
            validatorAccepted: true,
            executionSucceeded: true,
            answerAttachment: .clarificationChoices(resolved)
        ))
    }

    private func choice(
        meaningKey: String,
        title: String,
        aliases: [String]
    ) -> MarinaClarificationChoice {
        MarinaClarificationChoice(
            meaningKey: meaningKey,
            title: title,
            aliases: aliases,
            request: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .list
            )
        )
    }
}
