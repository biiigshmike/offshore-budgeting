import Foundation
import Testing
@testable import Offshore

#if canImport(FoundationModels)
@MainActor
struct MarinaNarrationValidationTests {
    private let fact = MarinaNarrationEvidence(id: "q0f0", subject: "Dining",
        relation: "is your biggest category at", value: "$500.38", scope: "Personal · October 2026", isFocus: true)

    @available(iOS 26.0, macCatalyst 26.0, *)
    private func draft(_ text: String, reference: String = "q0f0", introduction: String = "") -> MarinaNarrationDraft {
        .init(introduction: introduction, claims: [.init(reference: reference, wording: text)], question: "")
    }

    @Test func modelWordingResolvesVerifiedValuesAndScope() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let value = draft("For {scope}, {subject} {relation} {value}.", introduction: "Here’s what stands out.")
        let text = try #require(MarinaNarrationValidator.render(draft: value, evidence: [fact], requiresFinancialEvidence: true))
        #expect(text == "Here’s what stands out. For Personal · October 2026, Dining is your biggest category at $500.38.")
    }

    @Test func unknownAndStaleReferencesCannotAuthorizeClaims() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        #expect(MarinaNarrationValidator.render(draft: draft("{subject} {relation} {value} for {scope}.", reference: "q1f0"), evidence: [fact], requiresFinancialEvidence: true) == nil)
    }

    @Test func inventedAmountsDatesNamesAndDirectionsAreRejected() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        for wording in [
            "{subject} {relation} $900 for {scope}.",
            "{subject} {relation} {value} for June 2025, {scope}.",
            "Travel and {subject} {relation} {value} for {scope}.",
            "{subject} is not {relation} {value} for {scope}.",
            "{subject} is lower, {relation} {value} for {scope}.",
            "{subject} {relation} {value} for {scope}, because restaurants caused it.",
            "{value} {relation} {subject} for {scope}.",
            "{subject} {relation} over {value} for {scope}."
        ] {
            #expect(MarinaNarrationValidator.render(draft: draft(wording), evidence: [fact], requiresFinancialEvidence: true) == nil)
        }
    }

    @Test func requestedFocusCannotBeReplacedBySecondaryTotal() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let other = MarinaNarrationEvidence(id: "q0f1", subject: "Your total", relation: "is", value: "$900", scope: fact.scope, isFocus: false)
        #expect(MarinaNarrationValidator.render(draft: draft("{subject} {relation} {value} for {scope}.", reference: other.id), evidence: [fact, other], requiresFinancialEvidence: true) == nil)
    }

    @Test func exploratoryReadDoesNotForceAnUnrequestedTotalIntoTheAnswer() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let earlier = MarinaNarrationEvidence(id: "q0f0", subject: "Your total", relation: "is", value: "$900", scope: fact.scope, isFocus: false)
        var winner = fact
        winner.id = "q1f0"
        let value = draft("For {scope}, {subject} {relation} {value}.", reference: winner.id)
        let text = try #require(MarinaNarrationValidator.render(draft: value, evidence: [winner, earlier], requiresFinancialEvidence: true))
        #expect(text.contains("Dining"))
        #expect(!text.contains("$900"))
    }

    @Test func financialReadDoesNotAuthorizeFreeformFinancialProse() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        #expect(MarinaNarrationValidator.render(draft: draft("{subject} {relation} {value} for {scope}.", introduction: "You’re spending too much."), evidence: [fact], requiresFinancialEvidence: true) == nil)
        let unbound = MarinaNarrationDraft(introduction: "You saved $500.", claims: [], question: "")
        #expect(MarinaNarrationValidator.render(draft: unbound, evidence: [fact], requiresFinancialEvidence: true) == nil)
    }

    @Test func repeatedScopeMayBeOmittedOnlyAfterFirstBoundClaim() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let other = MarinaNarrationEvidence(id: "q0f1", subject: "Your total", relation: "is", value: "$900", scope: fact.scope, isFocus: false)
        let value = MarinaNarrationDraft(introduction: "", claims: [
            .init(reference: fact.id, wording: "{subject} {relation} {value} for {scope}."),
            .init(reference: other.id, wording: "Also, {subject} {relation} {value}.")
        ], question: "")
        let text = try #require(MarinaNarrationValidator.render(draft: value, evidence: [fact, other], requiresFinancialEvidence: true))
        #expect(text.components(separatedBy: fact.scope).count == 2)
        #expect(text.contains("$900"))
        #expect(MarinaNarrationValidator.render(draft: draft("{subject} {relation} {value}."), evidence: [fact], requiresFinancialEvidence: true) == nil)
    }

    @Test func greetingsAndBroadClarificationsNeedNoFinancialRead() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let greeting = MarinaNarrationDraft(act: .greeting, introduction: "Hey! I’m Marina, your Offshore budgeting assistant.", claims: [], question: "What would you like to look at?")
        #expect(try #require(MarinaNarrationValidator.render(draft: greeting, evidence: [], requiresFinancialEvidence: false)).contains("I’m Marina"))
        let question = MarinaNarrationDraft(act: .clarification, introduction: "", claims: [], question: "Would you like to look at spending, category limits, income, or savings?")
        #expect(MarinaNarrationValidator.render(draft: question, evidence: [], requiresFinancialEvidence: false) != nil)
        #expect(MarinaNarrationValidator.render(draft: greeting, evidence: [], requiresFinancialEvidence: true) == nil)
    }

    @Test func unsupportedWordOnlyFinancialAssertionsStillRequireEvidence() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let value = MarinaNarrationDraft(act: .greeting, introduction: "You’re on track.", claims: [], question: "")
        #expect(MarinaNarrationValidator.render(draft: value, evidence: [], requiresFinancialEvidence: false) == nil)
    }

    @Test func noReadActsCannotSmuggleWordOnlyFinancialAssertions() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        for act in [MarinaNarrationAct.greeting, .clarification, .help] {
            for text in ["Your debts exceed income.", "All your categories are within limits.", "You’re doing great financially.", "Your income is savings."] {
                let value = MarinaNarrationDraft(act: act, introduction: text, claims: [], question: "")
                #expect(MarinaNarrationValidator.render(draft: value, evidence: [], requiresFinancialEvidence: false) == nil)
            }
        }
    }

    @Test func neutralFramingCannotComposeAnUnsupportedAssessment() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        for introduction in ["Your results are okay.", "Your results are sure.", "Sure. Your results are okay."] {
            let value = draft("{subject} {relation} {value} for {scope}.", introduction: introduction)
            #expect(MarinaNarrationValidator.render(draft: value, evidence: [fact], requiresFinancialEvidence: true) == nil)
        }
    }

    @Test func neutralIntrosRemainAvailableForNoReadClarification() {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        for introduction in ["Sure!", "Let’s take a look.", "Okay."] {
            let value = MarinaNarrationDraft(act: .clarification, introduction: introduction, claims: [],
                question: "Would you like to review spending, category limits, income, or savings?")
            #expect(MarinaNarrationValidator.render(draft: value, evidence: [], requiresFinancialEvidence: false) != nil)
        }
    }

    @Test func focusFactsUseWholeResultMetricsAndNeverPageMath() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        var request = MarinaDataRequest(tool: .expenses)
        request.metric = .average
        let result = MarinaDataResult(scope: "October", metrics: [
            .init(label: "Total", value: 200), .init(label: "Average per record", value: 20)
        ], records: [.init(id: "first", kind: "variableExpense", title: "First", amount: 90)], totalCount: 10)
        let focused = try #require(MarinaNarrationEvidence.facts(request: request, result: result, prefix: "q0").first)
        #expect(focused.value == CurrencyFormatter.string(from: 20))
        #expect(focused.value != CurrencyFormatter.string(from: 90))
    }

    @Test func emptyAverageDoesNotTurnIntoAZeroTotalAnswer() throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        var request = MarinaDataRequest(tool: .expenses)
        request.metric = .average
        let result = MarinaDataResult(status: "empty", scope: "October", metrics: [.init(label: "Total", value: 0)])
        let text = try #require(MarinaVerifiedNarration.text(request: request, result: result))
        #expect(text.contains("isn’t available"))
        #expect(!text.contains(CurrencyFormatter.string(from: 0)))
    }
}
#endif
