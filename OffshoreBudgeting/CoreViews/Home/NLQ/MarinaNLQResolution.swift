import Foundation

struct MarinaNLQResolver {
    func resolve(
        intent: NormalizedQueryIntent,
        extraction: MarinaNLQTargetExtractionResult
    ) -> MarinaNLQResolutionOutcome {
        guard let metric = intent.normalizedMetric else {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: metric missing")
            return .clarifyNoMatch(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I can help with spending, comparisons, income averages, and due presets. Try one of those.",
                    options: []
                )
            )
        }

        let definition = metric.definition
        let scoped = scopedMatches(extraction.matchesByType, allowedTypes: definition.allowedTargetTypes)
        let typeCount = scoped.keys.count

        if definition.requiresTarget == false && (intent.rawTargetText == nil || scoped.isEmpty) {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: execute without target metric=\(metric.rawValue)")
            return .execute(MarinaNLQResolvedTargets(targetType: nil, matches: []))
        }

        if definition.requiresTarget && (intent.rawTargetText == nil || extraction.rawTargetText == nil) {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: clarify missing required target metric=\(metric.rawValue)")
            return .clarifyNoMatch(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I need a specific target for this query.",
                    options: makeTypeOptions(allowed: definition.allowedTargetTypes)
                )
            )
        }

        if scoped.isEmpty {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: clarify no match target='\(intent.rawTargetText ?? "nil")'")
            return .clarifyNoMatch(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I couldn't find a safe match for that target.",
                    options: makeTypeOptions(allowed: definition.allowedTargetTypes)
                )
            )
        }

        if typeCount > 1 {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: cross-domain ambiguity types=\(scoped.keys.map(\.rawValue).sorted())")
            return .clarifyAmbiguous(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I found matches in multiple domains. Pick one.",
                    options: scoped.keys.sorted(by: { $0.rawValue < $1.rawValue }).map {
                        MarinaNLQClarificationOption(
                            targetType: $0,
                            displayLabel: $0.rawValue.capitalized,
                            targetName: $0.rawValue,
                            typedAliases: typedAliases(for: $0)
                        )
                    }
                )
            )
        }

        guard let type = scoped.keys.first,
              let matches = scoped[type],
              matches.isEmpty == false
        else {
            return .clarifyNoMatch(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I couldn't safely resolve that target.",
                    options: []
                )
            )
        }

        let uniqueNames = Dictionary(grouping: matches, by: \.normalizedValue)
        let representativeMatches = uniqueNames.values.compactMap { bucket in
            bucket.first(where: { $0.matchType == .exact }) ?? bucket.first
        }.sorted { lhs, rhs in
            lhs.displayValue.localizedCaseInsensitiveCompare(rhs.displayValue) == .orderedAscending
        }

        if representativeMatches.count > 1 && definition.withinTypeAggregationPolicy == .clarifyDistinct {
            MarinaDebugLogger.log("[MarinaNLQ] resolution: same-type distinct values require clarification type=\(type.rawValue)")
            return .clarifyAmbiguous(
                MarinaNLQClarificationPayload(
                    rawTargetText: intent.rawTargetText,
                    message: "I found multiple \(type.rawValue) matches. Pick one.",
                    options: representativeMatches.map {
                        MarinaNLQClarificationOption(
                            targetType: type,
                            displayLabel: $0.displayValue,
                            targetName: $0.displayValue,
                            typedAliases: typedAliases(for: type)
                        )
                    }
                )
            )
        }

        MarinaDebugLogger.log("[MarinaNLQ] resolution: execute type=\(type.rawValue) count=\(representativeMatches.count)")
        return .execute(MarinaNLQResolvedTargets(targetType: type, matches: representativeMatches))
    }

    private func scopedMatches(
        _ allMatches: [MarinaNLQTargetType: [MarinaNLQCandidateMatch]],
        allowedTypes: Set<MarinaNLQTargetType>
    ) -> [MarinaNLQTargetType: [MarinaNLQCandidateMatch]] {
        guard allowedTypes.isEmpty == false else { return allMatches.filter { $0.value.isEmpty == false } }
        return allMatches.filter { allowedTypes.contains($0.key) && $0.value.isEmpty == false }
    }

    private func makeTypeOptions(allowed: Set<MarinaNLQTargetType>) -> [MarinaNLQClarificationOption] {
        let source = allowed.isEmpty ? Set([MarinaNLQTargetType.category, .merchant, .expense, .card]) : allowed
        return source.sorted(by: { $0.rawValue < $1.rawValue }).map { type in
            MarinaNLQClarificationOption(
                targetType: type,
                displayLabel: type.rawValue.capitalized,
                targetName: type.rawValue,
                typedAliases: typedAliases(for: type)
            )
        }
    }

    private func typedAliases(for type: MarinaNLQTargetType) -> [String] {
        switch type {
        case .category:
            return ["category"]
        case .merchant:
            return ["merchant"]
        case .expense:
            return ["expense"]
        case .card:
            return ["card"]
        case .budget, .preset, .incomeSource, .allocationAccount, .savingsAccount:
            return []
        }
    }
}

struct MarinaNLQClarificationResolver {
    func resolveTypedResponse(
        _ typedInput: String,
        payload: MarinaNLQClarificationPayload
    ) -> MarinaNLQResolutionOutcome {
        let normalizedInput = normalize(typedInput)
        guard payload.options.isEmpty == false else {
            return .clarifyNoMatch(payload)
        }

        let typeAliasMatches = payload.options.filter { option in
            option.typedAliases.contains(where: { normalize($0) == normalizedInput })
        }

        if typeAliasMatches.count > 1 {
            MarinaDebugLogger.log("[MarinaNLQ] clarification typed alias ambiguous input='\(typedInput)'")
            return .clarifyAmbiguous(
                MarinaNLQClarificationPayload(
                    rawTargetText: payload.rawTargetText,
                    message: "That alias maps to multiple target types. Pick one.",
                    options: typeAliasMatches
                )
            )
        }

        if let typeAliasMatch = typeAliasMatches.first {
            let sameType = payload.options.filter { $0.targetType == typeAliasMatch.targetType }
            if sameType.count > 1 {
                MarinaDebugLogger.log("[MarinaNLQ] clarification typed alias second-step required type=\(typeAliasMatch.targetType.rawValue)")
                return .clarifyAmbiguous(
                    MarinaNLQClarificationPayload(
                        rawTargetText: payload.rawTargetText,
                        message: "I found multiple \(typeAliasMatch.targetType.rawValue) options. Pick one.",
                        options: sameType
                    )
                )
            }

            return .execute(
                MarinaNLQResolvedTargets(
                    targetType: typeAliasMatch.targetType,
                    matches: [
                        MarinaNLQCandidateMatch(
                            entityType: typeAliasMatch.targetType,
                            displayValue: typeAliasMatch.targetName,
                            normalizedValue: normalize(typeAliasMatch.targetName),
                            matchType: .exact,
                            sourceID: UUID()
                        )
                    ]
                )
            )
        }

        let directMatches = payload.options.filter {
            normalize($0.displayLabel) == normalizedInput || normalize($0.targetName) == normalizedInput
        }

        if directMatches.count == 1, let selected = directMatches.first {
            MarinaDebugLogger.log("[MarinaNLQ] clarification selected typed option='\(selected.targetName)'")
            return .execute(
                MarinaNLQResolvedTargets(
                    targetType: selected.targetType,
                    matches: [
                        MarinaNLQCandidateMatch(
                            entityType: selected.targetType,
                            displayValue: selected.targetName,
                            normalizedValue: normalize(selected.targetName),
                            matchType: .exact,
                            sourceID: UUID()
                        )
                    ]
                )
            )
        }

        MarinaDebugLogger.log("[MarinaNLQ] clarification no typed match input='\(typedInput)'")
        return .clarifyNoMatch(
            MarinaNLQClarificationPayload(
                rawTargetText: payload.rawTargetText,
                message: "I couldn't map that response. Pick one of the shown options.",
                options: payload.options
            )
        )
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
