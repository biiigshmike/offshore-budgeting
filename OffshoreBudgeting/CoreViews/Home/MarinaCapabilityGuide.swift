//
//  MarinaCapabilityGuide.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/9/26.
//

import Foundation

struct MarinaCapabilityGuide {
    struct CapabilityGroup: Equatable {
        let title: String
        let examples: [String]
    }

    static let title = "Here’s what I can do right now"
    static let promptPatternTitle = "Ask me like this"
    static let limitationsTitle = "Not great yet"

    static let introBody = "I work best when the question is one metric, one target, and one period. I’m strongest with focused budgeting questions about spending, comparisons, cards, merchants, income, savings, and a few planning checks."

    static let promptPatternBody = "For the highest reliability, ask in this shape: one metric, one target, one period. Good patterns are Compare [category] this month vs last month, How much did I spend at [merchant] this month, Which categories still have room this month, and What is my safe spend today?"

    static let limitationsBody = "I am not great yet at multi-target comparisons, open-ended explanation questions like why something changed, or prompts that leave out the target or date window I need to run the analysis cleanly."

    static let capabilityGroups: [CapabilityGroup] = [
        CapabilityGroup(
            title: "Check-ins and spending",
            examples: [
                "How am I doing this month?",
                "How much did I spend this month?",
                "What did I spend money on today?"
            ]
        ),
        CapabilityGroup(
            title: "Comparisons and changes",
            examples: [
                "Compare this month vs last month",
                "Compare groceries this month vs last month",
                "Which categories changed most vs last month?"
            ]
        ),
        CapabilityGroup(
            title: "Categories, cards, and merchants",
            examples: [
                "Which categories still have room this month?",
                "How is my Apple Card doing this month?",
                "How much did I spend at Starbucks this month?"
            ]
        ),
        CapabilityGroup(
            title: "Income and savings",
            examples: [
                "What portion of my income comes from Salary this month?",
                "How am I doing with savings this month?",
                "What are my projected savings for April?"
            ]
        ),
        CapabilityGroup(
            title: "Planning extras",
            examples: [
                "What is my safe spend today?",
                "What is my next planned expense?",
                "What if I spend $25 less on dining each week?"
            ]
        )
    ]

    static func matchesPrompt(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        guard normalized.isEmpty == false else { return false }

        let directPhrases = [
            "what can you do",
            "what can marina do",
            "what can you help with",
            "what can you help me with",
            "what can t you do",
            "what cant you do",
            "how should i ask you",
            "how do i use you",
            "how can i use you",
            "what kinds of questions should i ask",
            "what kinds of questions can i ask",
            "what do you do",
            "what are your capabilities",
            "tell me your capabilities",
            "tell me what you can do"
        ]

        if directPhrases.contains(where: normalized.contains) {
            return true
        }

        let asksAboutMarina = normalized.contains("marina")
            && (normalized.contains("help") || normalized.contains("capab") || normalized.contains("questions"))
        if asksAboutMarina {
            return true
        }

        let asksAboutAssistant = normalized.contains("assistant")
            && (normalized.contains("help with") || normalized.contains("can do") || normalized.contains("questions"))
        return asksAboutAssistant
    }

    static func makeAnswer(for prompt: String) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .list,
            userPrompt: prompt,
            title: title,
            subtitle: "\(introBody)\n\n\(limitationsBody)",
            rows: answerRows
        )
    }

    static var answerRows: [HomeAnswerRow] {
        var rows = capabilityGroups.map { group in
            HomeAnswerRow(
                title: group.title,
                value: group.examples.joined(separator: "  •  ")
            )
        }

        rows.append(HomeAnswerRow(title: promptPatternTitle, value: promptPatternBody))
        rows.append(HomeAnswerRow(title: limitationsTitle, value: limitationsBody))
        return rows
    }

    static func helpSections(prefix: String) -> [GeneratedHelpSection] {
        [
            GeneratedHelpSection(
                id: "\(prefix)-capability-groups",
                resolvedHeader: "What Marina Can Answer Today",
                resolvedBodyText: capabilityGroups.map { group in
                    "\(group.title): \(group.examples.joined(separator: " • "))"
                }.joined(separator: "\n\n")
            ),
            GeneratedHelpSection(
                id: "\(prefix)-limitations",
                resolvedHeader: limitationsTitle,
                resolvedBodyText: limitationsBody
            ),
            GeneratedHelpSection(
                id: "\(prefix)-prompt-pattern",
                resolvedHeader: "Best Prompt Pattern Right Now",
                resolvedBodyText: promptPatternBody
            )
        ]
    }

    private static func normalizedPrompt(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
