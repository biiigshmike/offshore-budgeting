import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaNLQPipelineTests {
    @Test func normalizedMetricDefinitions_controlRequiresTarget() {
        #expect(MarinaNormalizedMetric.merchantSpendTotal.definition.requiresTarget == true)
        #expect(MarinaNormalizedMetric.categorySpendShare.definition.requiresTarget == false)
        #expect(MarinaNormalizedMetric.spendTotal.definition.requiresTarget == false)
        #expect(MarinaNormalizedMetric.monthComparison.definition.isFamilyMetric == true)
    }

    @Test func normalizer_comparisonFamilyMetric_remainsGeneric() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "Compare Starbucks in March to February")
        #expect(intent.normalizedMetric == .monthComparison)
    }

    @Test func normalizer_recoversMetricFromParserWhenKeywordNormalizationFails() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "Show my month over month change")
        #expect(intent.normalizedMetric == .monthComparison)
    }

    @Test func normalizer_separatesTargetFromComparisonDates() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "Compare Starbucks in March to February")
        #expect(intent.rawTargetText == "starbucks")
        #expect(intent.dateRange != nil)
        #expect(intent.comparisonDateRange != nil)
    }

    @Test func interpreter_topMerchantThisMonth_extractsMerchantRankingShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "top merchant this month",
            normalizedPrompt: normalize("top merchant this month"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .merchant)
        #expect(shape.ranking == .top)
        #expect(shape.targetHint == nil)
    }

    @Test func interpreter_topMerchantOfAllTime_extractsMerchantRankingShape() {
        let interpreter = makeInterpreter()
        let parser = HomeAssistantTextParser()
        let prompt = "who is my top merchant of all time"
        let shape = interpreter.interpretQueryShape(
            rawPrompt: prompt,
            normalizedPrompt: normalize(prompt),
            modifiers: [],
            dateRange: parser.parseDateRange(prompt, defaultPeriodUnit: .month),
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .merchant)
        #expect(shape.ranking == .top)
        #expect(shape.targetHint == nil)
        #expect(shape.dateRange?.startDate == date(2000, 1, 1, 0, 0, 0))
    }

    @Test func interpreter_biggestExpense_extractsTransactionLargestShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "what is my biggest expense",
            normalizedPrompt: normalize("what is my biggest expense"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .transaction)
        #expect(shape.ranking == .largest)
    }

    @Test func interpreter_mostFrequentExpense_extractsFrequencyShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "what is my most frequent expense",
            normalizedPrompt: normalize("what is my most frequent expense"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .transactionFrequency)
        #expect(shape.grouping == .transaction)
        #expect(shape.ranking == .mostFrequent)
    }

    @Test func interpreter_compareGroceries_extractsComparisonTargetHint() {
        let interpreter = makeInterpreter()
        let parser = HomeAssistantTextParser()
        let prompt = "compare groceries this month to last month"
        let shape = interpreter.interpretQueryShape(
            rawPrompt: prompt,
            normalizedPrompt: normalize(prompt),
            modifiers: ["comparison"],
            dateRange: parser.parseDateRange("this month", defaultPeriodUnit: .month),
            comparisonDateRange: parser.parseDateRange("last month", defaultPeriodUnit: .month)
        )

        #expect(shape.comparisonDateRange != nil)
        #expect(shape.targetHint == "groceries")
    }

    @Test func interpreter_spendAtTarget_extractsMerchantAggregateShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "how much did i spend at target this month",
            normalizedPrompt: normalize("how much did i spend at target this month"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .merchant)
        #expect(shape.ranking == nil)
        #expect(shape.targetHint == "target")
    }

    @Test func interpreter_spendTheMostOn_extractsGroupedSpendRankingShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "what do i spend the most on",
            normalizedPrompt: normalize("what do i spend the most on"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .category)
        #expect(shape.ranking == .top)
    }

    @Test func interpreter_moneyGo_extractsIndirectGroupedSpendRankingShape() {
        let interpreter = makeInterpreter()
        let shape = interpreter.interpretQueryShape(
            rawPrompt: "where does most of my money go",
            normalizedPrompt: normalize("where does most of my money go"),
            modifiers: [],
            dateRange: nil,
            comparisonDateRange: nil
        )

        #expect(shape.measure == .spendTotal)
        #expect(shape.grouping == .category)
        #expect(shape.ranking == .top)
    }

    @Test func mapper_resolvesSupportedShapesAndUnsupportedCombinations() {
        let mapper = MarinaMetricMapper()

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .merchant,
                ranking: .top
            )) == .metric(.topMerchants)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .category,
                ranking: .top,
                modifiers: ["breakdown_by_category"]
            )) == .metric(.topCategories)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .transaction,
                ranking: .largest
            )) == .metric(.largestTransactions)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .category,
                ranking: nil,
                modifiers: ["breakdown_by_category"]
            )) == .metric(.categorySpendShare)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .category,
                ranking: nil,
                targetHint: "groceries",
                modifiers: ["share_of_total"]
            )) == .metric(.categorySpendShare)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .transaction,
                ranking: .top
            )) == .metric(.largestTransactions)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .transactionFrequency,
                grouping: .transaction,
                ranking: .mostFrequent
            )) == .metric(.mostFrequentTransactions)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendTotal,
                grouping: .merchant,
                targetHint: "target"
            )) == .metric(.merchantSpendTotal)
        )

        #expect(
            mapper.resolve(shape: MarinaQueryShape(
                measure: .spendAverage,
                grouping: .merchant,
                ranking: .largest
            )) == .unsupported(reason: .rankedAverage(grouping: .merchant))
        )
    }

    @Test func normalizer_topMerchantThisMonth_usesShapeFirstResolution() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "top merchant this month")

        #expect(intent.normalizedMetric == .topMerchants)
        #expect(intent.queryShape.measure == .spendTotal)
        #expect(intent.queryShape.grouping == .merchant)
        #expect(intent.queryShape.ranking == .top)
    }

    @Test func normalizer_topMerchantOfAllTime_usesShapeFirstResolutionAndAllTimeRange() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "who is my top merchant of all time")

        #expect(intent.normalizedMetric == .topMerchants)
        #expect(intent.queryShape.grouping == .merchant)
        #expect(intent.queryShape.ranking == .top)
        #expect(intent.rawTargetText == nil)
        #expect(intent.dateRange?.startDate == date(2000, 1, 1, 0, 0, 0))
    }

    @Test func normalizer_topExpenseOfAllTime_staysLargestTransactions() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "what is my top expense of all time")

        #expect(intent.normalizedMetric == .largestTransactions)
        #expect(intent.queryShape.grouping == .transaction)
        #expect(intent.rawTargetText == nil)
        #expect(intent.dateRange?.startDate == date(2000, 1, 1, 0, 0, 0))
    }

    @Test func normalizer_mostFrequentExpense_mapsToFrequencyMetric() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "what is my most frequent expense")

        #expect(intent.normalizedMetric == .mostFrequentTransactions)
        #expect(intent.queryShape.measure == .transactionFrequency)
        #expect(intent.queryShape.grouping == .transaction)
        #expect(intent.rawTargetText == nil)
    }

    @Test func normalizer_spendAtTarget_prefersShapeTargetHint() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "how much did i spend at target this month")

        #expect(intent.normalizedMetric == .merchantSpendTotal)
        #expect(intent.queryShape.grouping == .merchant)
        #expect(intent.rawTargetText == "target")
    }

    @Test func normalizer_foodDrinkPeriod_preservesCategoryTarget() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "How much did I spend on Food & Drink this period?")

        #expect(intent.normalizedMetric == .categorySpendTotal)
        #expect(intent.rawTargetText == "food & drink")
    }

    @Test func normalizer_costMeCategoryPrompt_promotesToCategorySpendTotal() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "How much did groceries cost me last month?")

        #expect(intent.normalizedMetric == .categorySpendTotal)
        #expect(intent.rawTargetText?.contains("grocer") == true)
    }

    @Test func normalizer_appleCardMonth_mapsToUnscopedSpendWithCardTargetHint() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "What did I spend on my Apple Card this month?")

        #expect(intent.normalizedMetric == .spendTotal)
        #expect(intent.rawTargetText == "apple card")
        #expect(intent.queryShape.grouping == .some(.none))
    }

    @Test func normalizer_targetedComparison_preservesCategoryTargetHint() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "How much did I spend on Food & Drink this period compared to last period?")

        #expect(intent.normalizedMetric == .monthComparison)
        #expect(intent.rawTargetText == "food & drink")
    }

    @Test func normalizer_spendAtTargetLastMonth_preservesNamedTargetAndDateRange() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let parser = HomeAssistantTextParser()
        let prompt = "how much did i spend at target last month"
        let intent = normalizer.normalize(prompt: prompt)
        let expectedRange = parser.parseDateRange(prompt, defaultPeriodUnit: .month)

        #expect(intent.normalizedMetric == .merchantSpendTotal)
        #expect(intent.rawTargetText == "target")
        #expect(intent.dateRange == expectedRange)
    }

    @Test func normalizer_groupedCategoryPrompts_preserveGroupedIntent() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        for prompt in [
            "spending by category for this period",
            "show spending by category this month",
            "show me my category breakdown",
            "break down my spending by category"
        ] {
            let intent = normalizer.normalize(prompt: prompt)
            #expect(intent.normalizedMetric == .categorySpendShare)
            #expect(intent.queryShape.grouping == .category)
            #expect(intent.queryShape.ranking == nil)
            #expect(intent.modifiers.contains("breakdown_by_category"))
        }
    }

    @Test func normalizer_groupedSpendRankingVariants_resolveToTopCategories() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        for prompt in [
            "what do i spend the most on",
            "what do i spend the most money on",
            "what category do i spend the most on",
            "where does most of my money go"
        ] {
            let intent = normalizer.normalize(prompt: prompt)
            #expect(intent.normalizedMetric == .topCategories)
            #expect(intent.queryShape.grouping == .category)
            #expect(intent.queryShape.ranking == .top)
        }
    }

    @Test func normalizer_spendAtTargetInMarch_preservesNamedTargetAndDateRange() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let parser = HomeAssistantTextParser()
        let prompt = "what did i spend at target in march"
        let intent = normalizer.normalize(prompt: prompt)
        let expectedRange = parser.parseDateRange(prompt, defaultPeriodUnit: .month)

        #expect(intent.normalizedMetric == .merchantSpendTotal)
        #expect(intent.rawTargetText == "target")
        #expect(intent.dateRange == expectedRange)
    }

    @Test func normalizer_percentOfSpendingForCategory_routesToCategorySpendShare() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "what percent of my spending was groceries this month")

        #expect(intent.normalizedMetric == .categorySpendShare)
        #expect(intent.rawTargetText == "groceries")
        #expect(intent.modifiers.contains("share_of_total"))
    }

    @Test func normalizer_targetedAverage_promptsAreExplicitlyUnsupported() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        let groceryAverage = normalizer.normalize(prompt: "What is my average grocery spending?")
        #expect(groceryAverage.normalizedMetric == nil)
        #expect(groceryAverage.unsupportedShapeReason == .targetedAverage)

        let foodDrinkMonthlyAverage = normalizer.normalize(prompt: "What do I usually spend on Food & Drink per month?")
        #expect(foodDrinkMonthlyAverage.normalizedMetric == nil)
        #expect(foodDrinkMonthlyAverage.unsupportedShapeReason == .targetedAverage)
        #expect(foodDrinkMonthlyAverage.rawTargetText == "food & drink")
    }

    @Test func normalizer_merchantsSpendMostAt_mapsToTopMerchants() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "What merchants did I spend the most at?")

        #expect(intent.normalizedMetric == .topMerchants || intent.normalizedMetric == .spendTotal)
        #expect(intent.queryShape.grouping == .merchant || intent.queryShape.grouping == nil)
        #expect(intent.queryShape.ranking == .top)
    }

    @Test func normalizer_whatIfPrompts_areExplicitlyUnsupported() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        let first = normalizer.normalize(prompt: "If I spend $50 on Food & Drink, how will that affect my budget?")
        #expect(first.normalizedMetric == nil)
        #expect(first.unsupportedShapeReason == .whatIfSimulation)

        let second = normalizer.normalize(prompt: "If I buy something for $120 today, can I still stay within my safe spend?")
        #expect(second.normalizedMetric == nil)
        #expect(second.unsupportedShapeReason == .whatIfSimulation)
    }

    @Test func normalizer_targetedTotalsAndRanking_doNotDriftIntoShareRouting() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        let merchantTotal = normalizer.normalize(prompt: "how much did i spend at target this month")
        #expect(merchantTotal.normalizedMetric == .merchantSpendTotal)

        let categoryTotal = normalizer.normalize(prompt: "how much did i spend on groceries this month")
        #expect(categoryTotal.normalizedMetric == .categorySpendTotal)

        let ranking = normalizer.normalize(prompt: "what do i spend the most money on")
        #expect(ranking.normalizedMetric == .topCategories)
    }

    @Test func normalizer_unsupportedRecognizedShape_blocksCompatibilityFallback() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "what is my most expensive merchant by average")

        #expect(intent.queryShape.measure == .spendAverage)
        #expect(intent.queryShape.grouping == .merchant)
        #expect(intent.unsupportedShapeReason == .rankedAverage(grouping: .merchant))
        #expect(intent.normalizedMetric == nil)
    }

    @Test func normalizer_unsupportedCategoryAverageRanking_blocksCompatibilityFallback() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)
        let intent = normalizer.normalize(prompt: "top category by average spend")

        #expect(intent.queryShape.measure == .spendAverage)
        #expect(intent.queryShape.grouping == .category)
        #expect(intent.unsupportedShapeReason == .rankedAverage(grouping: .category))
        #expect(intent.normalizedMetric == nil)
    }

    @Test func pipeline_unsupportedRecognizedShape_returnsClarification() throws {
        let pipeline = try makePipeline()
        let result = pipeline.run(
            prompt: "what is my most expensive merchant by average",
            activeBudgetPeriod: nil
        )

        guard case let .clarification(payload) = result else {
            Issue.record("Expected clarification for unsupported recognized shape")
            return
        }

        #expect(payload.message.contains("top merchant"))
        #expect(payload.options.isEmpty)
    }

    @Test func pipeline_broadCategoryBreakdown_preservesShareRowsVerbatim() throws {
        let seeded = try makePipelineWithCategorySpendData()
        let prompt = "show me my category breakdown in february 2026"
        let result = seeded.pipeline.run(
            prompt: prompt,
            activeBudgetPeriod: nil as HomeQueryDateRange?,
            now: date(2026, 2, 20)
        )

        guard case let .answer(answer, execution) = result else {
            Issue.record("Expected broad category breakdown answer")
            return
        }

        #expect(execution.metric == MarinaNormalizedMetric.categorySpendShare)
        #expect(answer.kind == HomeAnswerKind.list)

        let expected = seeded.engine.execute(
            query: HomeQuery(
                intent: .categorySpendShare,
                dateRange: HomeQueryDateRange(
                    startDate: date(2026, 2, 1, 0, 0, 0),
                    endDate: date(2026, 2, 28, 23, 59, 59)
                )
            ),
            categories: seeded.categories,
            plannedExpenses: seeded.plannedExpenses,
            variableExpenses: seeded.variableExpenses,
            now: date(2026, 2, 20)
        )

        let expectedGroceries = expected.rows.first(where: { $0.title == "Groceries" })?.value
        let actualGroceries = answer.rows.first(where: { $0.title == "Groceries" })?.value

        #expect(expectedGroceries != nil)
        #expect(actualGroceries == expectedGroceries)
        #expect(actualGroceries?.contains("%") == true)
        #expect(actualGroceries?.contains("$") == true)
    }

    @Test func pipeline_targetedCategoryComparison_usesCategoryComparisonAggregationPath() throws {
        let seeded = try makePipelineWithCategorySpendData()
        MarinaTraceRecorder.shared.begin(
            prompt: "Compare groceries this month to last month.",
            routingMode: .nlqAuthoritative,
            marinaNLQv1Enabled: true
        )

        let result = seeded.pipeline.run(
            prompt: "Compare groceries this month to last month.",
            activeBudgetPeriod: nil,
            now: date(2026, 2, 20)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        if case let .answer(_, executionContext) = result {
            #expect(executionContext.metric == .monthComparison)
            #expect(executionContext.resolvedTargetType == .category)
            #expect(trace?.aggregationPath == "single_home_query_engine")
        } else if case .clarification = result {
            #expect(trace?.selectedRoute == .clarification)
        } else {
            Issue.record("Expected answer or clarification for targeted category comparison")
        }
        #expect(trace?.normalizedMetric == "monthComparison")
        #expect(trace?.targetText?.contains("groceries") == true)
    }

    @Test func normalizer_topExpenseAllTimeVariants_stayLargestTransactions() {
        let normalizer = MarinaNLQNormalizer(defaultPeriodUnit: .month)

        for prompt in [
            "top expense of all time",
            "largest expense ever",
            "biggest expense all time"
        ] {
            let intent = normalizer.normalize(prompt: prompt)
            #expect(intent.normalizedMetric == .largestTransactions)
            #expect(intent.queryShape.grouping == .transaction)
            #expect(intent.rawTargetText == nil)
            #expect(intent.dateRange?.startDate == date(2000, 1, 1, 0, 0, 0))
        }
    }

    @Test func resolver_sameTypeDistinct_aggregatesWhenMetricAllows() {
        let resolver = MarinaNLQResolver()
        let intent = NormalizedQueryIntent(
            rawPrompt: "what did i spend at star",
            normalizedMetric: .merchantSpendTotal,
            queryShape: MarinaQueryShape(),
            intentSignals: emptySignals(),
            rawTargetText: "star",
            dateRange: nil,
            comparisonDateRange: nil,
            resultLimit: nil,
            modifiers: [],
            confidenceLevel: .high
        )
        let extraction = MarinaNLQTargetExtractionResult(
            rawTargetText: "star",
            matchesByType: [
                .merchant: [
                    MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Starbucks", normalizedValue: "starbucks", matchType: .prefix, sourceID: UUID()),
                    MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Star Market", normalizedValue: "star market", matchType: .prefix, sourceID: UUID())
                ]
            ]
        )

        let outcome = resolver.resolve(intent: intent, extraction: extraction)
        guard case let .execute(resolved) = outcome else {
            Issue.record("Expected execute outcome")
            return
        }

        #expect(resolved.targetType == .merchant)
        #expect(resolved.matches.count == 2)
    }

    @Test func resolver_sameTypeDistinct_clarifiesWhenMetricDisallowsAggregation() {
        let resolver = MarinaNLQResolver()
        let intent = NormalizedQueryIntent(
            rawPrompt: "what are my largest expenses at star",
            normalizedMetric: .largestTransactions,
            queryShape: MarinaQueryShape(),
            intentSignals: emptySignals(),
            rawTargetText: "star",
            dateRange: nil,
            comparisonDateRange: nil,
            resultLimit: nil,
            modifiers: [],
            confidenceLevel: .high
        )
        let extraction = MarinaNLQTargetExtractionResult(
            rawTargetText: "star",
            matchesByType: [
                .merchant: [
                    MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Starbucks", normalizedValue: "starbucks", matchType: .prefix, sourceID: UUID()),
                    MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Star Market", normalizedValue: "star market", matchType: .prefix, sourceID: UUID())
                ]
            ]
        )

        let outcome = resolver.resolve(intent: intent, extraction: extraction)
        guard case let .clarifyAmbiguous(payload) = outcome else {
            Issue.record("Expected clarifyAmbiguous outcome")
            return
        }

        #expect(payload.options.count == 2)
    }

    @Test func resolver_crossTypeAmbiguity_alwaysClarifies() {
        let resolver = MarinaNLQResolver()
        let intent = NormalizedQueryIntent(
            rawPrompt: "what did i spend on star",
            normalizedMetric: .spendTotal,
            queryShape: MarinaQueryShape(),
            intentSignals: emptySignals(),
            rawTargetText: "star",
            dateRange: nil,
            comparisonDateRange: nil,
            resultLimit: nil,
            modifiers: [],
            confidenceLevel: .high
        )
        let extraction = MarinaNLQTargetExtractionResult(
            rawTargetText: "star",
            matchesByType: [
                .merchant: [
                    MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Starbucks", normalizedValue: "starbucks", matchType: .prefix, sourceID: UUID())
                ],
                .category: [
                    MarinaNLQCandidateMatch(entityType: .category, displayValue: "Star Expenses", normalizedValue: "star expenses", matchType: .prefix, sourceID: UUID())
                ]
            ]
        )

        let outcome = resolver.resolve(intent: intent, extraction: extraction)
        guard case .clarifyAmbiguous = outcome else {
            Issue.record("Expected cross-type ambiguity clarification")
            return
        }
    }

    @Test func resolvedTargets_prefixWarnings_emitOncePerNormalizedTarget() {
        let sourceID = UUID()
        let resolved = MarinaNLQResolvedTargets(
            targetType: .merchant,
            matches: [
                MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Starbucks", normalizedValue: "starbucks", matchType: .prefix, sourceID: sourceID),
                MarinaNLQCandidateMatch(entityType: .merchant, displayValue: "Starbucks", normalizedValue: "starbucks", matchType: .prefix, sourceID: sourceID)
            ]
        )

        #expect(resolved.prefixWarningTargets.count == 1)
        #expect(resolved.prefixWarningTargets.first == "Starbucks")
    }

    private func makeInterpreter() -> MarinaIntentInterpreter {
        MarinaIntentInterpreter(
            parser: HomeAssistantTextParser(),
            defaultPeriodUnit: .month
        )
    }

    private func emptySignals() -> MarinaIntentSignals {
        MarinaIntentSignals(
            family: nil,
            subject: nil,
            rankingMode: nil,
            aggregationMode: nil,
            targetHint: nil,
            modifiers: []
        )
    }

    private func makePipeline() throws -> MarinaNLQPipeline {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workspace.self,
            Budget.self,
            Category.self,
            PlannedExpense.self,
            VariableExpense.self,
            Card.self,
            Preset.self,
            Income.self,
            AllocationAccount.self,
            SavingsAccount.self,
            configurations: config
        )
        let context = ModelContext(container)
        let workspace = Workspace(name: "Test Workspace", hexColor: "#3B82F6")
        context.insert(workspace)

        let provider = MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        return MarinaNLQPipeline(provider: provider, defaultPeriodUnit: .month)
    }

    private func makePipelineWithCategorySpendData() throws -> (
        pipeline: MarinaNLQPipeline,
        engine: HomeQueryEngine,
        categories: [Offshore.Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workspace.self,
            Budget.self,
            Offshore.Category.self,
            PlannedExpense.self,
            VariableExpense.self,
            Card.self,
            Preset.self,
            Income.self,
            AllocationAccount.self,
            SavingsAccount.self,
            configurations: config
        )
        let context = ModelContext(container)
        let workspace = Workspace(name: "Seeded Workspace", hexColor: "#3B82F6")
        context.insert(workspace)

        let groceries = Offshore.Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let travel = Offshore.Category(name: "Travel", hexColor: "#0000AA", workspace: workspace)
        context.insert(groceries)
        context.insert(travel)

        let plannedExpenses = [
            PlannedExpense(
                title: "Groceries Plan",
                plannedAmount: 250,
                expenseDate: date(2026, 2, 5),
                workspace: workspace,
                category: groceries
            ),
            PlannedExpense(
                title: "Travel Plan",
                plannedAmount: 150,
                expenseDate: date(2026, 2, 7),
                workspace: workspace,
                category: travel
            )
        ]

        for expense in plannedExpenses {
            context.insert(expense)
        }

        let variableExpenses = [
            VariableExpense(
                descriptionText: "Groceries Variable",
                amount: 50,
                transactionDate: date(2026, 2, 10),
                workspace: workspace,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Travel Variable",
                amount: 150,
                transactionDate: date(2026, 2, 12),
                workspace: workspace,
                category: travel
            )
        ]

        for expense in variableExpenses {
            context.insert(expense)
        }

        try context.save()

        let provider = MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        return (
            pipeline: MarinaNLQPipeline(provider: provider, defaultPeriodUnit: .month),
            engine: HomeQueryEngine(),
            categories: [groceries, travel],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )
    }

    private func normalize(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&-]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
