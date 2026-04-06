import Foundation
import Testing
@testable import Offshore

@MainActor
struct HelpFAQEngineTests {

    // MARK: - Answering

    @Test func answer_exactTopicQuestion_returnsMarinaTopic() {
        let engine = HelpFAQEngine()

        let answer = engine.answer(
            prompt: "How does Marina assistant work in Home?",
            topics: GeneratedHelpContent.allLeafTopics
        )

        #expect(answer != nil)
        #expect(answer?.match.topicID == "home-marina")
    }

    @Test func answer_marinaCapabilityQuestion_returnsMarinaTopic() {
        let engine = HelpFAQEngine()

        let answer = engine.answer(
            prompt: "What kinds of questions should I ask Marina?",
            topics: GeneratedHelpContent.allLeafTopics
        )

        #expect(answer != nil)
        #expect(answer?.match.topicID == "home-marina")
    }

    @Test func answer_marinaComparisonGapQuestion_returnsMarinaTopic() {
        let engine = HelpFAQEngine()

        let answer = engine.answer(
            prompt: "Why does Marina get confused by some comparison questions?",
            topics: GeneratedHelpContent.allLeafTopics
        )

        #expect(answer != nil)
        #expect(answer?.match.topicID == "home-marina")
    }

    @Test func answer_sectionHeaderLanguage_resolvesBudgetOverviewTopic() {
        let engine = HelpFAQEngine()

        let answer = engine.answer(
            prompt: "How do I create a budget?",
            topics: GeneratedHelpContent.allLeafTopics
        )

        #expect(answer != nil)
        #expect(answer?.match.topicID == "budgets-overview")
    }

    @Test func answer_prefersFocusedTitleAndHeader_overBroadBodyMatch() {
        let engine = HelpFAQEngine()

        let topics: [GeneratedHelpLeafTopic] = [
            makeTopic(
                id: "budget-setup",
                title: "Budget Setup",
                header: "Create a Budget",
                body: "Create a budget, choose cards, and verify setup in one flow."
            ),
            makeTopic(
                id: "home-overview",
                title: "Home Overview",
                header: "Overview",
                body: "Home summarizes budgets, spending, and trends after setup is complete."
            )
        ]

        let answer = engine.answer(
            prompt: "How can I create a budget?",
            topics: topics
        )

        #expect(answer != nil)
        #expect(answer?.match.topicID == "budget-setup")
    }

    @Test func resolve_offTopicPrompt_returnsLowConfidenceWithThreeSuggestions() {
        let engine = HelpFAQEngine()

        let resolution = engine.resolve(
            prompt: "Tell me a joke about space turtles",
            topics: GeneratedHelpContent.allLeafTopics
        )

        #expect(resolution.answer == nil)
        #expect(resolution.confidence == .low)
        #expect(resolution.suggestions.count == 3)
    }

    @Test func suggestedTopics_samePrompt_returnsDeterministicTopThree() {
        let engine = HelpFAQEngine()

        let topics: [GeneratedHelpLeafTopic] = [
            makeTopic(
                id: "notifications",
                title: "Notifications",
                header: "Notification Reminders",
                body: "Manage notification reminders and alert schedule for your budget periods."
            ),
            makeTopic(
                id: "general",
                title: "General Settings",
                header: "Defaults",
                body: "Adjust default budgeting period and reminder behavior."
            ),
            makeTopic(
                id: "budgets",
                title: "Budgets",
                header: "Overview",
                body: "Learn about budgets and planned expenses."
            ),
            makeTopic(
                id: "privacy",
                title: "Privacy",
                header: "Permissions",
                body: "Review privacy controls and data settings."
            )
        ]

        let prompt = "notification reminder settings"

        let first = engine.suggestedTopics(for: prompt, topics: topics, limit: 3).map(\.id)
        let second = engine.suggestedTopics(for: prompt, topics: topics, limit: 3).map(\.id)

        #expect(first == second)
        #expect(first == ["notifications", "general", "budgets"])
    }

    @Test func rankedTopicMatches_prioritizesFocusedMatch_andIncludesSectionMetadata() {
        let engine = HelpFAQEngine()

        let topics: [GeneratedHelpLeafTopic] = [
            makeTopic(
                id: "budget-setup",
                title: "Budget Setup",
                header: "Create a Budget",
                body: "Create a budget, choose cards, and verify setup in one flow."
            ),
            makeTopic(
                id: "home-overview",
                title: "Home Overview",
                header: "Overview",
                body: "Home summarizes budgets, spending, and trends after setup is complete."
            )
        ]

        let matches = engine.rankedTopicMatches(
            for: "How can I create a budget?",
            topics: topics
        )

        #expect(matches.isEmpty == false)
        #expect(matches.first?.topicID == "budget-setup")
        #expect(matches.first?.sectionID == "budget-setup-section")
        #expect(matches.first?.sectionTitle == "Create a Budget")
    }

    @Test func rankedTopicMatches_samePrompt_returnsDeterministicOrdering() {
        let engine = HelpFAQEngine()

        let topics: [GeneratedHelpLeafTopic] = [
            makeTopic(
                id: "notifications",
                title: "Notifications",
                header: "Notification Reminders",
                body: "Manage notification reminders and alert schedule for your budget periods."
            ),
            makeTopic(
                id: "general",
                title: "General Settings",
                header: "Defaults",
                body: "Adjust default budgeting period and reminder behavior."
            ),
            makeTopic(
                id: "privacy",
                title: "Privacy",
                header: "Permissions",
                body: "Review privacy controls and data settings."
            )
        ]

        let prompt = "notification reminder settings"
        let first = engine.rankedTopicMatches(for: prompt, topics: topics).map(\.topicID)
        let second = engine.rankedTopicMatches(for: prompt, topics: topics).map(\.topicID)

        #expect(first == second)
        #expect(first.first == "notifications")
    }

    // MARK: - Content Visibility

    @Test func visibleLeafTopic_nonPhone_hidesIntroductionTapToPaySteps_andAddsAvailabilityNote() {
        let topic = GeneratedHelpContent.visibleLeafTopic(
            for: "introduction-quick-actions",
            audience: .nonPhone
        )

        #expect(topic != nil)

        let sectionIDs = Set(topic?.sections.map(\.id) ?? [])
        #expect(sectionIDs.contains("introduction-quick-actions-3") == false)
        #expect(sectionIDs.contains("introduction-quick-actions-nonphone-note"))
    }

    @Test func visibleLeafTopic_nonPhone_hidesSettingsTapToPaySteps_andAddsAvailabilityNote() {
        let topic = GeneratedHelpContent.visibleLeafTopic(
            for: "settings-quick-actions",
            audience: .nonPhone
        )

        #expect(topic != nil)

        let sectionIDs = Set(topic?.sections.map(\.id) ?? [])
        #expect(sectionIDs.contains("settings-quick-actions-2"))
        #expect(sectionIDs.contains("settings-quick-actions-3") == false)
        #expect(sectionIDs.contains("settings-quick-actions-nonphone-note"))
    }

    @Test func visibleLeafTopic_phone_keepsTapToPaySteps_withoutAvailabilityNote() {
        let topic = GeneratedHelpContent.visibleLeafTopic(
            for: "settings-quick-actions",
            audience: .phone
        )

        #expect(topic != nil)

        let sectionIDs = Set(topic?.sections.map(\.id) ?? [])
        #expect(sectionIDs.contains("settings-quick-actions-2"))
        #expect(sectionIDs.contains("settings-quick-actions-3-income-sms"))
        #expect(sectionIDs.contains("settings-quick-actions-nonphone-note") == false)
    }

    // MARK: - Helpers

    private func makeTopic(
        id: String,
        title: LocalizedStringResource,
        header: LocalizedStringResource,
        body: LocalizedStringResource
    ) -> GeneratedHelpLeafTopic {
        GeneratedHelpLeafTopic(
            id: id,
            destinationID: "test",
            title: title,
            sections: [
                GeneratedHelpSection(
                    id: "\(id)-section",
                    header: header,
                    bodyText: body,
                    mediaItems: []
                )
            ]
        )
    }
}
