import Foundation
import Testing

@testable import Offshore

struct MarinaFoundationModelAttemptDiagnosticPrivacyTests {
  @Test func compiledAndAlignmentDigestsRedactFinancialAndIdentityValues() throws {
    let privateName = "Private Merchant 6A6DDB4E"
    let privateComparison = "Private Comparison 9937"
    let privateConstraint = "Private Groceries 14F0"
    let privateDisplayName = "Private Display 72DD"
    let privateID = try #require(UUID(uuidString: "A53AC95D-33CF-4582-A16A-6D9B052CB320"))
    let privateAmount = 987_654.32
    let localizedRuntimeError = "Fehler für Private Merchant 6A6DDB4E bei 987654.32"

    let resolvedReference = MarinaResolvedEntityReference(
      entity: .card,
      id: privateID,
      displayName: privateDisplayName,
      provenance: .candidateResolver
    )
    let request = MarinaSemanticRequest(
      entity: .variableExpense,
      operation: .whatIf,
      measure: .budgetImpact,
      dimensions: [.card, .category, .merchantText],
      constraints: [
        MarinaSemanticConstraint(
          dimension: .category,
          value: privateConstraint,
          resolvedReference: resolvedReference,
          kindSource: .explicit
        )
      ],
      targetName: privateName,
      comparisonTargetName: privateComparison,
      textQuery: privateName,
      targetDisplayName: privateDisplayName,
      resolvedTarget: resolvedReference,
      resolvedComparisonTarget: resolvedReference,
      resolvedScope: .workspace(privateID),
      targetKindSource: .explicit,
      comparisonTargetKindSource: .inferred,
      whatIfAmount: privateAmount,
      expectedAnswerShape: .metric
    )
    let actual = MarinaFoundationModelCompiledRequestDigest(request: request)
    let expected = MarinaFoundationModelCompiledRequestDigest(
      request: MarinaSemanticRequest(
        entity: .budget,
        operation: .forecast,
        measure: .safeDailySpend,
        expectedAnswerShape: .metric
      )
    )
    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
      attempt: 1,
      compilerVersion: "marina.semantic-compiler.v3",
      stage: .alignment,
      status: .rejected,
      rejection: .alignment(.entityMismatch),
      alignmentVerdict: .rejected,
      generatedIntent: MarinaFoundationModelGeneratedIntentDigest(
        intent: .metric,
        entity: .variableExpense,
        operation: .whatIf,
        measure: .budgetImpact,
        target: MarinaFoundationModelGeneratedTargetDigest(
          evidence: .explicit,
          dimension: .card
        ),
        constraints: [
          MarinaFoundationModelGeneratedConstraintDigest(
            dimension: .category,
            evidence: .explicit
          )
        ],
        hasScenarioAmount: true,
        answerShape: .metric
      ),
      compiledRequest: actual,
      alignment: MarinaFoundationModelAlignmentDigest(
        expected: expected,
        actual: actual
      )
    )

    let note = diagnostic.diagnosticNote
    for privateValue in [
      privateName,
      privateComparison,
      privateConstraint,
      privateDisplayName,
      privateID.uuidString,
      String(privateAmount),
      "987654.32",
      localizedRuntimeError,
    ] {
      #expect(note.contains(privateValue) == false)
    }
    #expect(note.contains("rejectionCode=alignment.entityMismatch"))
    #expect(note.contains("generatedIntent={intent=metric"))
    #expect(note.contains("compiledRequest={entity=variableExpense"))
    #expect(note.contains("scenario=present"))
    #expect(note.contains("category:explicit"))
  }

  @Test func humanReadableReasonIsDerivedFromStableCode() {
    let diagnostic = MarinaFoundationModelAttemptDiagnostic(
      attempt: 1,
      compilerVersion: "marina.semantic-compiler.v3",
      stage: .alignment,
      status: .rejected,
      rejection: .alignment(.measureMismatch),
      alignmentVerdict: .rejected,
      generatedIntent: nil,
      compiledRequest: nil,
      alignment: nil
    )

    #expect(
      diagnostic.reason
        == MarinaSemanticPromptAlignmentRejectionCode.measureMismatch.humanReadableReason)
    #expect(diagnostic.rejectionCode == "alignment.measureMismatch")
  }

  @Test func clarificationSelectionDigestStoresOnlyTheBoundedIndex() {
    let digest = MarinaFoundationModelGeneratedIntentDigest(
      intent: .clarificationSelection,
      clarificationSelectionIndex: 1
    )

    #expect(digest.clarificationSelectionIndex == 1)
    #expect(digest.rendered.contains("intent=clarificationSelection"))
    #expect(digest.rendered.contains("clarificationIndex=1"))
  }
}
