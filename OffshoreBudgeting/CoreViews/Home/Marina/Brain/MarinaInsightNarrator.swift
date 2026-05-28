import Foundation

protocol MarinaInsightNarrating {
    func narration(for context: MarinaInsightContext) async throws -> String?
    func narrationStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error>
}

extension MarinaInsightNarrating {
    func narrationStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    if let narration = try await narration(for: context) {
                        continuation.yield(narration)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct MarinaInsightContext: Equatable, Sendable {
    static let maxRows = 6

    struct Perspective: Equatable, Sendable {
        enum Direction: String, Equatable, Sendable {
            case partyOwesUser
            case userOwesParty
            case settled
        }

        let partyName: String
        let direction: Direction
        let requiredRelationshipSentence: String
    }

    struct Row: Equatable, Sendable {
        let title: String
        let value: String
        let amount: Double?
        let role: HomeAnswerRowRole
    }

    let prompt: String?
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let answerKind: HomeAnswerKind
    let dateRangeLabel: String
    let entity: MarinaSemanticEntity
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let perspective: Perspective?
    let rows: [Row]

    init(
        prompt: String?,
        result: MarinaExecutionResult,
        plan: MarinaQueryPlan
    ) {
        self.prompt = Self.trimmedOptional(prompt)
        self.title = result.title
        self.subtitle = Self.trimmedOptional(result.subtitle)
        self.primaryValue = Self.trimmedOptional(result.primaryValue)
        self.answerKind = result.kind
        self.dateRangeLabel = Self.rangeLabel(plan.dateRange)
        self.entity = plan.entity
        self.operation = plan.operation
        self.measure = plan.measure
        let rows = result.rows.prefix(Self.maxRows).map {
            Row(
                title: $0.title,
                value: $0.value,
                amount: $0.amount,
                role: $0.role
            )
        }
        self.rows = rows
        self.perspective = Self.perspective(result: result, plan: plan, rows: rows)
    }

    var isNarratable: Bool {
        switch answerKind {
        case .metric, .list, .comparison:
            return true
        case .message:
            return false
        }
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func rangeLabel(_ range: HomeQueryDateRange?) -> String {
        guard let range else { return "All time" }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private static func perspective(
        result: MarinaExecutionResult,
        plan: MarinaQueryPlan,
        rows: [Row]
    ) -> Perspective? {
        guard result.kind == .metric,
              plan.entity == .reconciliationAccount,
              plan.measure == .reconciliationBalance,
              plan.dateRange == nil,
              let partyName = trimmedOptional(plan.targetName),
              let balance = rows.first(where: { $0.title == "Balance" })?.amount else {
            return nil
        }

        if abs(balance) < 0.005 {
            return Perspective(
                partyName: partyName,
                direction: .settled,
                requiredRelationshipSentence: "\(partyName) is settled up with you."
            )
        }

        let amount = CurrencyFormatter.string(from: abs(balance))
        if balance > 0 {
            return Perspective(
                partyName: partyName,
                direction: .partyOwesUser,
                requiredRelationshipSentence: "\(partyName) owes you \(amount)."
            )
        }

        return Perspective(
            partyName: partyName,
            direction: .userOwesParty,
            requiredRelationshipSentence: "You owe \(partyName) \(amount)."
        )
    }
}

struct MarinaAnswerFactsDigest: Equatable {
    let context: MarinaInsightContext

    func text() -> String {
        var lines: [String] = [
            "Prompt: \(context.prompt ?? "None")",
            "Answer kind: \(context.answerKind.rawValue)",
            "Title: \(context.title)",
            "Date range: \(context.dateRangeLabel)",
            "Semantic request: \(context.entity.rawValue).\(context.operation.rawValue)"
        ]

        if let measure = context.measure {
            lines.append("Measure: \(measure.rawValue)")
        }
        if let subtitle = context.subtitle {
            lines.append("Subtitle: \(subtitle)")
        }
        if let primaryValue = context.primaryValue {
            lines.append("Primary value: \(primaryValue)")
        }
        lines.append("Pronoun rules: Marina may use I/me/my only for assistant actions or limitations. The user is you/your. Words like me in the prompt refer to the user, not Marina.")
        lines.append("Ownership rules: The user's money, budgets, cards, income, spending, savings, and reconciliation balances are your/the user's, never Marina's.")

        if let perspective = context.perspective {
            lines.append("Named reconciliation party: \(perspective.partyName)")
            lines.append("Reconciliation party pronouns: Use the party name first; use they/their only in any follow-up sentence.")
            lines.append("Required relationship sentence: \(perspective.requiredRelationshipSentence)")
        }

        if context.rows.isEmpty {
            lines.append("Rows: none")
        } else {
            lines.append("Rows:")
            for row in context.rows {
                lines.append("- \(row.title): \(row.value)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

enum MarinaVoiceSanitizer {
    private static let lowercaseLabelPrefixes = [
        "marina:",
        "marina -",
        "marina --",
        "marina says:",
        "marina says -"
    ]
    private static let userOwnedFinancialPrefixes: [(source: String, replacement: String)] = [
        ("my income status", "Your income status"),
        ("my safe spend", "Your safe spend"),
        ("my budget progress", "Your budget progress"),
        ("my cash flow", "Your cash flow"),
        ("my spending", "Your spending"),
        ("my spend", "Your spend"),
        ("my expenses", "Your expenses"),
        ("my expense", "Your expense"),
        ("my transactions", "Your transactions"),
        ("my transaction", "Your transaction"),
        ("my planned expenses", "Your planned expenses"),
        ("my planned expense", "Your planned expense"),
        ("my savings", "Your savings"),
        ("my income", "Your income"),
        ("my budgets", "Your budgets"),
        ("my budget", "Your budget"),
        ("my categories", "Your categories"),
        ("my category", "Your category"),
        ("my accounts", "Your accounts"),
        ("my account", "Your account"),
        ("my cards", "Your cards"),
        ("my card", "Your card")
    ]

    static func sanitizedFinal(_ value: String?, context: MarinaInsightContext? = nil) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let lowercased = trimmed.lowercased()

        for prefix in lowercaseLabelPrefixes where lowercased.hasPrefix(prefix) {
            let index = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
            let stripped = trimmed[index...].trimmingCharacters(in: .whitespacesAndNewlines)
            return stripped.isEmpty ? nil : sanitizedFinal(String(stripped), context: context)
        }

        if let repaired = replacingReconciliationOwnershipInversion(in: trimmed, context: context) {
            return repaired
        }

        return replacingAssistantOwnedFinancialOpening(in: trimmed)
    }

    static func sanitizedStreaming(_ value: String?, context: MarinaInsightContext? = nil) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        if isPartialNameLabel(trimmed)
            || isPartialAssistantOwnedFinancialOpening(trimmed)
            || isPartialReconciliationOwnershipInversion(trimmed, context: context) {
            return nil
        }

        return sanitizedFinal(trimmed, context: context)
    }

    private static func isPartialNameLabel(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard lowercased.count < "marina says:".count else { return false }

        let possibleLabels = [
            "marina:",
            "marina -",
            "marina says:"
        ]
        return possibleLabels.contains { $0.hasPrefix(lowercased) }
    }

    private static func replacingAssistantOwnedFinancialOpening(in value: String) -> String {
        let lowercased = value.lowercased()
        for prefix in userOwnedFinancialPrefixes where lowercased.hasPrefix(prefix.source) {
            let nextIndex = value.index(value.startIndex, offsetBy: prefix.source.count)
            guard nextIndex == value.endIndex || value[nextIndex].isLetter == false else { continue }
            return prefix.replacement + value[nextIndex...]
        }
        return value
    }

    private static func isPartialAssistantOwnedFinancialOpening(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        guard lowercased.hasPrefix("my") else { return false }

        return userOwnedFinancialPrefixes.contains {
            $0.source.hasPrefix(lowercased) && lowercased.count < $0.source.count
        }
    }

    private static func replacingReconciliationOwnershipInversion(
        in value: String,
        context: MarinaInsightContext?
    ) -> String? {
        guard let perspective = context?.perspective else { return nil }
        let lowercased = value.lowercased()

        switch perspective.direction {
        case .partyOwesUser:
            guard lowercased.hasPrefix("you owe me")
                    || lowercased.hasPrefix("you owe marina")
                    || lowercased.hasPrefix("you owe us") else {
                return nil
            }
            return perspective.requiredRelationshipSentence
        case .userOwesParty:
            guard lowercased.hasPrefix("i owe you")
                    || lowercased.hasPrefix("marina owes you")
                    || lowercased.hasPrefix("we owe you") else {
                return nil
            }
            return perspective.requiredRelationshipSentence
        case .settled:
            guard lowercased.hasPrefix("you owe me")
                    || lowercased.hasPrefix("i owe you")
                    || lowercased.hasPrefix("marina owes you")
                    || lowercased.hasPrefix("you owe marina") else {
                return nil
            }
            return perspective.requiredRelationshipSentence
        }
    }

    private static func isPartialReconciliationOwnershipInversion(
        _ value: String,
        context: MarinaInsightContext?
    ) -> Bool {
        guard context?.perspective != nil else { return false }
        let lowercased = value.lowercased()
        let wrongOpenings = [
            "you owe me",
            "you owe marina",
            "you owe us",
            "i owe you",
            "marina owes you",
            "we owe you"
        ]
        return wrongOpenings.contains {
            $0.hasPrefix(lowercased) && lowercased.count <= $0.count
        }
    }
}

struct MarinaDeterministicInsightNarrator: MarinaInsightNarrating {
    func narration(for context: MarinaInsightContext) async throws -> String? {
        guard context.isNarratable else { return nil }

        switch context.answerKind {
        case .metric:
            return metricNarration(for: context)
        case .list:
            return listNarration(for: context)
        case .comparison:
            return comparisonNarration(for: context)
        case .message:
            return nil
        }
    }

    private func metricNarration(for context: MarinaInsightContext) -> String? {
        if let perspective = context.perspective {
            return perspective.requiredRelationshipSentence
        }

        guard let primaryValue = context.primaryValue else {
            return evidenceNarration(prefix: "\(context.title) is ready to review", context: context)
        }

        return evidenceNarration(
            prefix: "\(context.title) is \(primaryValue)",
            context: context
        )
    }

    private func listNarration(for context: MarinaInsightContext) -> String? {
        guard let first = context.rows.first else {
            return "\(context.title) does not have any matching rows for \(context.dateRangeLabel)."
        }

        return "\(context.title) is led by \(first.title) at \(first.value). That is the clearest place to start if you want to understand this slice."
    }

    private func comparisonNarration(for context: MarinaInsightContext) -> String? {
        if let primaryValue = context.primaryValue {
            return evidenceNarration(
                prefix: "\(context.title) lands at \(primaryValue)",
                context: context
            )
        }

        return evidenceNarration(prefix: "\(context.title) is ready to compare", context: context)
    }

    private func evidenceNarration(prefix: String, context: MarinaInsightContext) -> String {
        guard let row = context.rows.first else {
            return "\(prefix) for \(context.dateRangeLabel)."
        }

        return "\(prefix) for \(context.dateRangeLabel). \(row.title) is \(row.value), so keep that detail in view before changing course."
    }
}

struct MarinaInsightNarrator: MarinaInsightNarrating {
    typealias NarrationStream = AsyncThrowingStream<String, Error>
    typealias ModelStreamProvider = (MarinaInsightContext) -> NarrationStream?

    private let fallbackNarrator: MarinaDeterministicInsightNarrator
    private let modelStreamProvider: ModelStreamProvider?

    init(
        fallbackNarrator: MarinaDeterministicInsightNarrator = MarinaDeterministicInsightNarrator(),
        modelStreamProvider: ModelStreamProvider? = nil
    ) {
        self.fallbackNarrator = fallbackNarrator
        self.modelStreamProvider = modelStreamProvider
    }

    func narration(for context: MarinaInsightContext) async throws -> String? {
        var latest: String?
        for try await partial in narrationStream(for: context) {
            latest = partial
        }
        return latest
    }

    func narrationStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard context.isNarratable else {
                    continuation.finish()
                    return
                }

                if let modelStream = modelStream(for: context) {
                    do {
                        for try await partial in modelStream {
                            guard Task.isCancelled == false else {
                                continuation.finish()
                                return
                            }
                            if let sanitized = MarinaVoiceSanitizer.sanitizedStreaming(partial, context: context) {
                                continuation.yield(sanitized)
                            }
                        }
                        continuation.finish()
                        return
                    } catch {
                        await yieldFallback(for: context, continuation: continuation)
                        return
                    }
                }

                await yieldFallback(for: context, continuation: continuation)
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func modelStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error>? {
        guard context.isNarratable else { return nil }

        if let modelStreamProvider {
            return modelStreamProvider(context)
        }

        #if canImport(FoundationModels)
        if shouldUseFoundationModelInsights {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                return MarinaFoundationModelsInsightRuntime().narrationStream(for: context)
            }
        }
        #endif

        return nil
    }

    private func yieldFallback(
        for context: MarinaInsightContext,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async {
        do {
            if let fallback = try await fallbackNarrator.narration(for: context),
               let sanitized = MarinaVoiceSanitizer.sanitizedFinal(fallback, context: context),
               Task.isCancelled == false {
                continuation.yield(sanitized)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    private var shouldUseFoundationModelInsights: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }
        #endif
        return true
    }
}

extension MarinaExecutionResult {
    func withAppendingExplanation(_ appended: String?) -> MarinaExecutionResult {
        let pieces = [explanation, appended]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        let combined = pieces.isEmpty ? nil : pieces.joined(separator: "\n\n")

        return MarinaExecutionResult(
            kind: kind,
            title: title,
            subtitle: subtitle,
            primaryValue: primaryValue,
            rows: rows,
            attachment: attachment,
            explanation: combined
        )
    }
}
