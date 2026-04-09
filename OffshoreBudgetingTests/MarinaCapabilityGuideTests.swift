import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaCapabilityGuideTests {

    @Test func matchesPrompt_capabilityQuestions_returnTrue() {
        #expect(MarinaCapabilityGuide.matchesPrompt("Marina, what can you do?"))
        #expect(MarinaCapabilityGuide.matchesPrompt("What can't you do yet?"))
        #expect(MarinaCapabilityGuide.matchesPrompt("How should I ask you things?"))
        #expect(MarinaCapabilityGuide.matchesPrompt("What can you help me with?"))
    }

    @Test func matchesPrompt_budgetQuery_returnFalse() {
        #expect(MarinaCapabilityGuide.matchesPrompt("How much did I spend this month?") == false)
    }

    @Test func makeAnswer_includesExamplesPromptPatternAndLimits() {
        let answer = MarinaCapabilityGuide.makeAnswer(for: "What can you do?")

        #expect(answer.kind == .list)
        #expect(answer.title == MarinaCapabilityGuide.title)
        #expect(answer.rows.contains(where: { $0.title == MarinaCapabilityGuide.promptPatternTitle }))
        #expect(answer.rows.contains(where: { $0.title == MarinaCapabilityGuide.limitationsTitle }))
        #expect(answer.rows.contains(where: { $0.value.contains("How am I doing this month?") }))
    }

    @Test func helpSections_shareGuideContent() {
        let topic = GeneratedHelpContent.leafTopic(for: "home-marina")

        #expect(topic != nil)
        #expect(topic?.sections.contains(where: { $0.header == "What Marina Can Answer Today" }) == true)
        #expect(topic?.sections.contains(where: { $0.bodyText.contains("How is my Apple Card doing this month?") }) == true)
        #expect(topic?.sections.contains(where: { $0.header == MarinaCapabilityGuide.limitationsTitle }) == true)
    }
}
