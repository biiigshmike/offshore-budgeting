import Foundation

struct MarinaStarterPromptFactory {
    static var basePromptPool: [String] {
        MarinaStarterPromptCatalog.baseEntries.map { entry in
            MarinaL10n.string(
                entry.localizationKey,
                defaultValue: entry.defaultValue,
                comment: entry.localizationComment
            )
        }
    }

    static func promptPool(cardNames: [String]) -> [String] {
        var pool = basePromptPool
        if let cardName = cardNames
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.isEmpty == false }) {
            let entry = MarinaStarterPromptCatalog.cardSummaryEntry
            pool.append(MarinaL10n.format(
                entry.localizationKey,
                defaultValue: entry.defaultValue,
                comment: entry.localizationComment,
                cardName
            ))
        }
        return pool
    }

    static func randomPrompts(cardNames: [String]) -> [String] {
        Array(promptPool(cardNames: cardNames).shuffled().prefix(4))
    }
}
