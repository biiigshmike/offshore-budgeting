import Foundation

/// The single source of truth for Marina's user-visible starter prompts and the
/// semantic anchors used to verify their model-generated interpretations.
nonisolated enum MarinaStarterPromptCatalog {
    enum ID: String, CaseIterable, Equatable, Hashable, Sendable {
        case safeSpend
        case savingsOutlook
        case incomeProgress
        case nextPlannedExpense
        case categoryAvailability
        case spendTrends
        case topCategory
        case cardSummary
    }

    enum TargetAnchor: Equatable, Sendable {
        case absent
        case named(
            String,
            kind: MarinaSemanticDimension,
            source: MarinaSemanticTargetKindSource
        )
    }

    struct Contract: Equatable, Sendable {
        let entity: MarinaSemanticEntity
        let projection: MarinaSemanticProjection
        let operation: MarinaSemanticOperation
        let measure: MarinaSemanticMeasure
        let dimensions: [MarinaSemanticDimension]
        let dateRange: MarinaSemanticDateRangeToken
        let dateRangeSource: MarinaSemanticDateRangeSource
        let target: TargetAnchor
        let sort: MarinaSemanticSort?
        let resultLimit: Int?
        let expenseScope: MarinaSemanticExpenseScope?
        let incomeState: MarinaSemanticIncomeState?
        let categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?
        let answerShape: MarinaSemanticAnswerShape

        init(
            entity: MarinaSemanticEntity,
            projection: MarinaSemanticProjection = .records,
            operation: MarinaSemanticOperation,
            measure: MarinaSemanticMeasure,
            dimensions: [MarinaSemanticDimension] = [],
            dateRange: MarinaSemanticDateRangeToken = .currentPeriod,
            dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
            target: TargetAnchor = .absent,
            sort: MarinaSemanticSort? = nil,
            resultLimit: Int? = nil,
            expenseScope: MarinaSemanticExpenseScope? = nil,
            incomeState: MarinaSemanticIncomeState? = nil,
            categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
            answerShape: MarinaSemanticAnswerShape = .metric
        ) {
            self.entity = entity
            self.projection = projection
            self.operation = operation
            self.measure = measure
            self.dimensions = dimensions
            self.dateRange = dateRange
            self.dateRangeSource = dateRangeSource
            self.target = target
            self.sort = sort
            self.resultLimit = resultLimit
            self.expenseScope = expenseScope
            self.incomeState = incomeState
            self.categoryAvailabilityFilter = categoryAvailabilityFilter
            self.answerShape = answerShape
        }
    }

    struct Entry: Equatable, Sendable {
        let id: ID
        let localizationKey: String
        let defaultValue: String
        let localizationComment: String
        let localizedValues: [String: String]
        let contract: Contract

        func prompt(localeIdentifier: String) -> String {
            localizedValues[languageTag(for: localeIdentifier)] ?? defaultValue
        }

        private func languageTag(for localeIdentifier: String) -> String {
            MarinaStarterPromptCatalog.languageTag(for: localeIdentifier)
        }
    }

    struct Match: Equatable, Sendable {
        let id: ID
        let contract: Contract
    }

    static let baseEntries: [Entry] = [
        Entry(
            id: .safeSpend,
            localizationKey: "marina.starter.safeSpend",
            defaultValue: "What is my safe spend today?",
            localizationComment: "Starter prompt asking Marina about safe spend.",
            localizedValues: [
                "ar": "ما هو إنفاقي الآمن اليوم؟",
                "de": "Was kann ich heute sicher ausgeben?",
                "en": "What is my safe spend today?",
                "es": "¿Cuál es mi gasto seguro hoy?",
                "fr": "Quelle est ma dépense sûre aujourd’hui ?",
                "pt-BR": "Qual é meu gasto seguro hoje?",
                "zh-Hans": "我今天的安全支出是多少？"
            ],
            contract: Contract(
                entity: .budget,
                projection: .summary,
                operation: .forecast,
                measure: .safeDailySpend
            )
        ),
        Entry(
            id: .savingsOutlook,
            localizationKey: "marina.starter.savingsOutlook",
            defaultValue: "Show my savings outlook.",
            localizationComment: "Starter prompt asking Marina about savings outlook.",
            localizedValues: [
                "ar": "اعرض توقعات ادخاري.",
                "de": "Zeige meinen Sparausblick.",
                "en": "Show my savings outlook.",
                "es": "Muestra mi panorama de ahorros.",
                "fr": "Affiche mes perspectives d’épargne.",
                "pt-BR": "Mostre minha visão de poupança.",
                "zh-Hans": "显示我的储蓄展望。"
            ],
            contract: Contract(
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal
            )
        ),
        Entry(
            id: .incomeProgress,
            localizationKey: "marina.starter.incomeProgress",
            defaultValue: "How is my income progress?",
            localizationComment: "Starter prompt asking Marina about income progress.",
            localizedValues: [
                "ar": "كيف يتقدم دخلي؟",
                "de": "Wie ist mein Einkommensfortschritt?",
                "en": "How is my income progress?",
                "es": "¿Cómo va mi progreso de ingresos?",
                "fr": "Où en est ma progression de revenus ?",
                "pt-BR": "Como está meu progresso de renda?",
                "zh-Hans": "我的收入进度如何？"
            ],
            contract: Contract(
                entity: .income,
                operation: .share,
                measure: .incomeAmount,
                incomeState: .all
            )
        ),
        Entry(
            id: .nextPlannedExpense,
            localizationKey: "marina.starter.nextPlannedExpense",
            defaultValue: "What is my next planned expense?",
            localizationComment: "Starter prompt asking Marina about the next planned expense.",
            localizedValues: [
                "ar": "ما هو مصروفي المخطط التالي؟",
                "de": "Was ist meine nächste geplante Ausgabe?",
                "en": "What is my next planned expense?",
                "es": "¿Cuál es mi próximo gasto planificado?",
                "fr": "Quelle est ma prochaine dépense planifiée ?",
                "pt-BR": "Qual é minha próxima despesa planejada?",
                "zh-Hans": "我的下一个计划支出是什么？"
            ],
            contract: Contract(
                entity: .plannedExpense,
                operation: .next,
                measure: .effectiveAmount,
                expenseScope: .planned
            )
        ),
        Entry(
            id: .categoryAvailability,
            localizationKey: "marina.starter.categoryAvailability",
            defaultValue: "Show category availability.",
            localizationComment: "Starter prompt asking Marina about category availability.",
            localizedValues: [
                "ar": "اعرض توفر الفئات.",
                "de": "Kategorieverfügbarkeit anzeigen.",
                "en": "Show category availability.",
                "es": "Mostrar disponibilidad de categorías.",
                "fr": "Afficher la disponibilité des catégories.",
                "pt-BR": "Mostrar disponibilidade das categorias.",
                "zh-Hans": "显示类别可用额度。"
            ],
            contract: Contract(
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability
            )
        ),
        Entry(
            id: .spendTrends,
            localizationKey: "marina.starter.spendTrends",
            defaultValue: "What are my spend trends?",
            localizationComment: "Starter prompt asking Marina about spend trends.",
            localizedValues: [
                "ar": "ما اتجاهات إنفاقي؟",
                "de": "Was sind meine Ausgabentrends?",
                "en": "What are my spend trends?",
                "es": "¿Cuáles son mis tendencias de gasto?",
                "fr": "Quelles sont mes tendances de dépense ?",
                "pt-BR": "Quais são minhas tendências de gastos?",
                "zh-Hans": "我的支出趋势是什么？"
            ],
            contract: Contract(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                sort: .amountDescending,
                resultLimit: 3,
                expenseScope: .unified,
                answerShape: .list
            )
        ),
        Entry(
            id: .topCategory,
            localizationKey: "marina.starter.topCategory",
            defaultValue: "What is my top category this period?",
            localizationComment: "Starter prompt asking Marina about the top spending category.",
            localizedValues: [
                "ar": "ما أعلى فئة لدي في هذه الفترة؟",
                "de": "Was ist meine Top-Kategorie in diesem Zeitraum?",
                "en": "What is my top category this period?",
                "es": "¿Cuál es mi categoría principal este periodo?",
                "fr": "Quelle est ma catégorie principale sur cette période ?",
                "pt-BR": "Qual é minha principal categoria neste período?",
                "zh-Hans": "这个期间我的最高类别是什么？"
            ],
            contract: Contract(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeSource: .explicit,
                sort: .amountDescending,
                resultLimit: 1,
                expenseScope: .unified,
                answerShape: .list
            )
        )
    ]

    static let cardSummaryEntry = Entry(
        id: .cardSummary,
        localizationKey: "marina.starter.cardSummaryFormat",
        defaultValue: "Summarize my %@.",
        localizationComment: "Starter prompt asking Marina to summarize a specific card.",
        localizedValues: [
            "ar": "لخص %@ الخاص بي.",
            "de": "Fasse mein %@ zusammen.",
            "en": "Summarize my %@.",
            "es": "Resume mi %@.",
            "fr": "Résume mon %@.",
            "pt-BR": "Resuma meu %@.",
            "zh-Hans": "总结我的 %@。"
        ],
        contract: Contract(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            target: .named("", kind: .card, source: .explicit),
            expenseScope: .unified
        )
    )

    static func match(prompt: String, localeIdentifier: String) -> Match? {
        let normalizedPrompt = MarinaPromptNormalizer.normalize(prompt)
        for entry in baseEntries where MarinaPromptNormalizer.normalize(entry.prompt(localeIdentifier: localeIdentifier)) == normalizedPrompt {
            return Match(id: entry.id, contract: entry.contract)
        }

        guard let cardName = cardName(
            from: normalizedPrompt,
            format: cardSummaryEntry.prompt(localeIdentifier: localeIdentifier)
        ) else {
            return nil
        }
        var contract = cardSummaryEntry.contract
        contract = Contract(
            entity: contract.entity,
            projection: contract.projection,
            operation: contract.operation,
            measure: contract.measure,
            dimensions: contract.dimensions,
            dateRange: contract.dateRange,
            dateRangeSource: contract.dateRangeSource,
            target: .named(cardName, kind: .card, source: .explicit),
            sort: contract.sort,
            resultLimit: contract.resultLimit,
            expenseScope: contract.expenseScope,
            incomeState: contract.incomeState,
            categoryAvailabilityFilter: contract.categoryAvailabilityFilter,
            answerShape: contract.answerShape
        )
        return Match(id: .cardSummary, contract: contract)
    }

    static func languageTag(for localeIdentifier: String) -> String {
        let normalized = localeIdentifier.replacing("_", with: "-")
        if normalized.lowercased().hasPrefix("pt-br") { return "pt-BR" }
        if normalized.lowercased().hasPrefix("zh-hans") { return "zh-Hans" }
        return Locale(identifier: normalized).language.languageCode?.identifier ?? "en"
    }

    private static func cardName(from prompt: String, format: String) -> String? {
        let normalizedFormat = MarinaPromptNormalizer.normalize(format)
        let parts = normalizedFormat.components(separatedBy: "%@")
        guard parts.count == 2,
              prompt.hasPrefix(parts[0]),
              prompt.hasSuffix(parts[1]) else {
            return nil
        }

        let start = prompt.index(prompt.startIndex, offsetBy: parts[0].count)
        let end = prompt.index(prompt.endIndex, offsetBy: -parts[1].count)
        guard start <= end else { return nil }
        let cardName = prompt[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return cardName.isEmpty ? nil : cardName
    }
}
