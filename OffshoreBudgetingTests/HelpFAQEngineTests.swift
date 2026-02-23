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

    // MARK: - Helpers

    private func makeTopic(
        id: String,
        title: String,
        header: String,
        body: String
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
