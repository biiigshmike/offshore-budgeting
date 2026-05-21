import Foundation

struct MarinaDateRangeTextResolver {
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func resolve(
        _ rawText: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> HomeQueryDateRange? {
        let normalized = normalizedText(rawText)
        guard normalized.isEmpty == false else { return nil }

        if normalized.contains("all time")
            || normalized.contains("all-time")
            || normalized == "ever"
            || normalized.hasPrefix("ever ")
            || normalized.hasSuffix(" ever")
            || normalized.contains(" ever ") {
            var components = DateComponents()
            var utcCalendar = Calendar(identifier: .gregorian)
            utcCalendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            components.calendar = utcCalendar
            components.timeZone = utcCalendar.timeZone
            components.year = 2000
            components.month = 1
            components.day = 1
            let start = utcCalendar.startOfDay(for: components.date ?? Date(timeIntervalSince1970: 0))
            return HomeQueryDateRange(startDate: start, endDate: nowProvider())
        }

        return MarinaDateResolver(
            calendar: calendar,
            nowProvider: nowProvider
        ).resolveTextRange(
            rawText,
            defaultPeriodUnit: defaultPeriodUnit
        )?.queryDateRange
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s\\-/]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarinaResultLimitExtractor {
    func limit(in rawText: String) -> Int? {
        let normalized = rawText
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns = [
            "\\btop\\s+(\\d{1,2})\\b",
            "\\bfirst\\s+(\\d{1,2})\\b",
            "\\blast\\s+(\\d{1,2})\\b",
            "\\b(\\d{1,2})\\s+(?:items|transactions|expenses|categories|merchants|cards|periods)\\b"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, range: range),
                  let valueRange = Range(match.range(at: 1), in: normalized),
                  let value = Int(normalized[valueRange]) else {
                continue
            }
            return min(max(1, value), HomeQuery.maxResultLimit)
        }

        return nil
    }
}

struct MarinaMutationIntentGuard {
    func isMutationPrompt(_ rawPrompt: String) -> Bool {
        let normalized = rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return false }

        let mutationVerbs = [
            "add", "create", "make", "log", "record", "enter",
            "edit", "update", "change", "rename", "move",
            "delete", "remove", "mark", "archive"
        ]
        let domainNouns = [
            "expense", "expenses", "income", "budget", "budgets",
            "card", "cards", "category", "categories", "preset", "presets",
            "planned expense", "planned expenses", "transaction", "transactions"
        ]

        return mutationVerbs.contains { verb in
            normalized.range(of: "\\b\(verb)\\b", options: .regularExpression) != nil
        } && domainNouns.contains { normalized.contains($0) }
    }
}
