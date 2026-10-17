import Foundation

// MARK: - FAQ Models

enum HelpFAQConfidence: String, Equatable {
    case high
    case medium
    case low
}

struct HelpFAQMatch: Equatable {
    let topicID: String
    let topicTitle: String
    let sectionID: String
    let sectionTitle: String?
    let score: Int
    let coverage: Double
}

struct HelpFAQAnswer: Equatable {
    let title: String
    let narrative: String
    let confidence: HelpFAQConfidence
    let match: HelpFAQMatch
}

struct HelpFAQResolution: Equatable {
    let answer: HelpFAQAnswer?
    let suggestions: [GeneratedHelpLeafTopic]
    let confidence: HelpFAQConfidence
}

struct HelpFAQTopicMatch: Equatable {
    let topicID: String
    let topicTitle: String
    let sectionID: String
    let sectionTitle: String?
    let score: Int
    let coverage: Double
}

// MARK: - FAQ Engine

struct HelpFAQEngine {
    private struct TopicCandidate {
        let topic: GeneratedHelpLeafTopic
        let section: GeneratedHelpSection
        let score: Int
        let coverage: Double
    }

    private let stopWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "but", "by", "do", "for", "from",
        "help", "how", "i", "if", "in", "is", "it", "me", "my", "of", "on", "or",
        "so", "that", "the", "this", "to", "up", "what", "with", "you", "your"
    ]

    private let fallbackTopicIDs: [String] = [
        "home-marina",
        "introduction-building-blocks",
        "budgets-overview",
        "accounts-overview",
        "settings-overview"
    ]

    func answer(prompt: String, topics: [GeneratedHelpLeafTopic]) -> HelpFAQAnswer? {
        let resolution = resolve(prompt: prompt, topics: topics)
        return resolution.answer
    }

    func suggestedTopics(
        for prompt: String,
        topics: [GeneratedHelpLeafTopic],
        limit: Int = 3
    ) -> [GeneratedHelpLeafTopic] {
        let sanitizedLimit = max(1, limit)
        let normalizedPrompt = normalized(prompt)
        let ranked = rankedTopics(for: normalizedPrompt, topics: topics)

        var suggestions: [GeneratedHelpLeafTopic] = []
        var seenIDs: Set<String> = []

        for candidate in ranked {
            guard isStrongSuggestionCandidate(candidate) else { continue }

            if seenIDs.insert(candidate.topic.id).inserted {
                suggestions.append(candidate.topic)
            }

            if suggestions.count == sanitizedLimit {
                return suggestions
            }
        }

        for topicID in fallbackTopicIDs {
            guard let topic = topics.first(where: { $0.id == topicID }) else { continue }
            if seenIDs.insert(topic.id).inserted {
                suggestions.append(topic)
            }
            if suggestions.count == sanitizedLimit {
                return suggestions
            }
        }

        for topic in topics.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) {
            if seenIDs.insert(topic.id).inserted {
                suggestions.append(topic)
            }
            if suggestions.count == sanitizedLimit {
                return suggestions
            }
        }

        return suggestions
    }

    func resolve(prompt: String, topics: [GeneratedHelpLeafTopic]) -> HelpFAQResolution {
        let normalizedPrompt = normalized(prompt)

        guard normalizedPrompt.isEmpty == false else {
            let suggestions = suggestedTopics(for: normalizedPrompt, topics: topics)
            return HelpFAQResolution(answer: nil, suggestions: suggestions, confidence: .low)
        }

        let ranked = rankedTopics(for: normalizedPrompt, topics: topics)
        guard let best = ranked.first else {
            let suggestions = suggestedTopics(for: normalizedPrompt, topics: topics)
            return HelpFAQResolution(answer: nil, suggestions: suggestions, confidence: .low)
        }

        let confidence = confidence(for: best)
        if confidence == .low {
            let suggestions = suggestedTopics(for: normalizedPrompt, topics: topics)
            return HelpFAQResolution(answer: nil, suggestions: suggestions, confidence: .low)
        }

        let answer = HelpFAQAnswer(
            title: best.topic.title,
            narrative: narrative(from: best.section),
            confidence: confidence,
            match: HelpFAQMatch(
                topicID: best.topic.id,
                topicTitle: best.topic.title,
                sectionID: best.section.id,
                sectionTitle: best.section.header,
                score: best.score,
                coverage: best.coverage
            )
        )

        return HelpFAQResolution(answer: answer, suggestions: [], confidence: confidence)
    }

    func rankedTopicMatches(
        for prompt: String,
        topics: [GeneratedHelpLeafTopic]
    ) -> [HelpFAQTopicMatch] {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false else { return [] }

        let ranked = rankedTopics(for: normalizedPrompt, topics: topics)
        return ranked.map { candidate in
            HelpFAQTopicMatch(
                topicID: candidate.topic.id,
                topicTitle: candidate.topic.title,
                sectionID: candidate.section.id,
                sectionTitle: candidate.section.header,
                score: candidate.score,
                coverage: candidate.coverage
            )
        }
    }

    func queryTokens(for prompt: String) -> Set<String> {
        tokenSet(from: prompt)
    }

    // MARK: - Ranking

    private func rankedTopics(for normalizedPrompt: String, topics: [GeneratedHelpLeafTopic]) -> [TopicCandidate] {
        let promptTokens = tokenSet(from: normalizedPrompt)

        let candidates = topics.compactMap { topic -> TopicCandidate? in
            bestCandidate(for: topic, normalizedPrompt: normalizedPrompt, promptTokens: promptTokens)
        }

        return candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.coverage != $1.coverage { return $0.coverage > $1.coverage }
            return $0.topic.title.localizedCaseInsensitiveCompare($1.topic.title) == .orderedAscending
        }
    }

    private func bestCandidate(
        for topic: GeneratedHelpLeafTopic,
        normalizedPrompt: String,
        promptTokens: Set<String>
    ) -> TopicCandidate? {
        let titleText = normalized(topic.title)
        let titleTokens = tokenSet(from: titleText)
        let destinationTitle = GeneratedHelpContent.destination(for: topic.destinationID)?.title ?? ""
        let destinationTokens = tokenSet(from: destinationTitle)

        var best: TopicCandidate?

        for section in topic.sections {
            let sectionHeader = normalized(section.header ?? "")
            let sectionBody = normalized(section.bodyText)
            let mediaText = normalized(section.mediaItems.map { item in
                [item.displayTitle ?? "", item.bodyText, item.fullscreenCaptionText ?? ""]
                    .joined(separator: " ")
            }.joined(separator: " "))

            let headerTokens = tokenSet(from: sectionHeader)
            let bodyTokens = tokenSet(from: sectionBody)
            let mediaTokens = tokenSet(from: mediaText)

            let matchedTitle = promptTokens.intersection(titleTokens)
            let matchedHeader = promptTokens.intersection(headerTokens)
            let matchedBody = promptTokens.intersection(bodyTokens)
            let matchedMedia = promptTokens.intersection(mediaTokens)
            let matchedDestination = promptTokens.intersection(destinationTokens)

            var score = 0
            score += phraseBonus(prompt: normalizedPrompt, candidate: titleText, highWeight: 16, inverseWeight: 12)
            score += phraseBonus(prompt: normalizedPrompt, candidate: sectionHeader, highWeight: 14, inverseWeight: 10)

            score += matchedTitle.count * 4
            score += matchedHeader.count * 3
            score += matchedBody.count * 2
            score += matchedMedia.count
            score += matchedDestination.count * 2

            if score == 0 { continue }

            let matchedTokens = matchedTitle
                .union(matchedHeader)
                .union(matchedBody)
                .union(matchedMedia)
                .union(matchedDestination)
            let denominator = max(promptTokens.count, 1)
            let coverage = Double(matchedTokens.count) / Double(denominator)

            let candidate = TopicCandidate(
                topic: topic,
                section: section,
                score: score,
                coverage: coverage
            )

            if let currentBest = best {
                if candidate.score > currentBest.score {
                    best = candidate
                } else if candidate.score == currentBest.score, candidate.coverage > currentBest.coverage {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    private func confidence(for candidate: TopicCandidate) -> HelpFAQConfidence {
        if candidate.score >= 20 && candidate.coverage >= 0.35 {
            return .high
        }

        if candidate.score >= 12 && candidate.coverage >= 0.2 {
            return .medium
        }

        return .low
    }

    private func isStrongSuggestionCandidate(_ candidate: TopicCandidate) -> Bool {
        candidate.score >= 3
    }

    // MARK: - Formatting

    private func narrative(from section: GeneratedHelpSection) -> String {
        let rawBody = section.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawBody.isEmpty == false else {
            return "Open the matched Help topic for details."
        }

        let firstParagraph = rawBody
            .components(separatedBy: "\n\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawBody

        return truncated(firstParagraph, maxLength: 300)
    }

    private func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }

        let limitIndex = text.index(text.startIndex, offsetBy: maxLength)
        let prefix = String(text[..<limitIndex])

        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[..<lastSpace]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        }

        return prefix + "..."
    }

    // MARK: - Normalization

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func tokenSet(from text: String) -> Set<String> {
        let normalizedText = normalized(text)
        guard normalizedText.isEmpty == false else { return [] }

        let rawTokens = normalizedText.split(separator: " ").map(String.init)
        var tokens: Set<String> = []

        for token in rawTokens {
            let canonical = canonicalToken(token)
            guard canonical.count >= 2 else { continue }
            guard stopWords.contains(canonical) == false else { continue }
            tokens.insert(canonical)
        }

        return tokens
    }

    private func canonicalToken(_ token: String) -> String {
        var value = token

        if value.hasSuffix("ies"), value.count > 4 {
            value = String(value.dropLast(3)) + "y"
        } else if value.hasSuffix("s"), value.count > 3 {
            value = String(value.dropLast())
        }

        return value
    }

    private func phraseBonus(
        prompt: String,
        candidate: String,
        highWeight: Int,
        inverseWeight: Int
    ) -> Int {
        guard candidate.isEmpty == false else { return 0 }
        guard candidate.count >= 5 else { return 0 }

        if prompt.contains(candidate) {
            return highWeight
        }

        if candidate.contains(prompt), prompt.split(separator: " ").count >= 2 {
            return inverseWeight
        }

        return 0
    }
}
