import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticCatalogExpansionTests {
    @Test func semanticRequestDecodesLegacyPayloadWithContractDefaults() throws {
        let data = try #require(
            """
            {
              "entity": "budget",
              "operation": "list",
              "expectedAnswerShape": "list"
            }
            """.data(using: .utf8)
        )

        let request = try JSONDecoder().decode(MarinaSemanticRequest.self, from: data)

        #expect(request.projection == .records)
        #expect(request.dimensions.isEmpty)
        #expect(request.dateRangeToken == .currentPeriod)
        #expect(request.resolvedScope == nil)
        #expect(request.resultOffset == nil)
    }

    @Test func semanticRequestRoundTripsResolvedScopeAndPaging() throws {
        let budgetID = UUID()
        let identity = MarinaResolvedEntityReference(
            entity: .budget,
            id: budgetID,
            displayName: "July Budget",
            provenance: .candidateResolver
        )
        let request = MarinaSemanticRequest(
            entity: .budget,
            operation: .list,
            measure: .projectedSavings,
            projection: .summary,
            resolvedTarget: identity,
            resolvedScope: .budget(budgetID),
            resultLimit: 20,
            resultOffset: 40,
            expectedAnswerShape: .metric
        )

        let decoded = try JSONDecoder().decode(
            MarinaSemanticRequest.self,
            from: JSONEncoder().encode(request)
        )

        #expect(decoded == request)
        #expect(decoded.resolvedScope == .budget(budgetID))
        #expect(decoded.resolvedTarget?.id == budgetID)
        #expect(decoded.resolvedTarget?.provenance == .candidateResolver)
    }

    @Test func executionContextCarriesPublicPageMetadata() {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            resultLimit: 20,
            resultOffset: 20,
            expectedAnswerShape: .list
        )
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: request,
            dateRange: nil,
            comparisonDateRange: nil,
            now: .now
        )
        let result = MarinaExecutionResult(
            kind: .list,
            title: "Expenses",
            displayedRowCount: 20,
            totalRowCount: 55,
            hasMore: true,
            nextOffset: 40
        )

        let context = MarinaAnswerSemanticContext(plan: plan, result: result)

        #expect(plan.resultOffset == 20)
        #expect(context.hasMore == true)
        #expect(context.nextOffset == 40)
    }

    @Test func catalogRegistersEverySemanticEntityAndProjectionPolicy() {
        let catalog = MarinaEntityCatalog()

        for entity in MarinaSemanticEntity.allCases {
            #expect(catalog.descriptor(for: entity) != nil, "Missing descriptor for \(entity.rawValue)")
            #expect(catalog.projections[entity]?.isEmpty == false, "Missing projections for \(entity.rawValue)")
        }
    }

    @Test func catalogRegistersAllTwentySwiftDataModelsExactlyOnce() {
        let catalog = MarinaEntityCatalog()

        #expect(MarinaSwiftDataModel.allCases.count == 20)
        #expect(catalog.models.count == MarinaSwiftDataModel.allCases.count)

        for model in MarinaSwiftDataModel.allCases {
            #expect(catalog.modelDescriptor(for: model) != nil, "Missing model classification for \(model.rawValue)")
        }
    }

    @Test func modelClassificationsKeepInternalModelsOutOfPublicQuerySurfaces() throws {
        let catalog = MarinaEntityCatalog()
        let importRule = try #require(catalog.modelDescriptor(for: .importMerchantRule))
        let aliasRule = try #require(catalog.modelDescriptor(for: .assistantAliasRule))
        let chatSession = try #require(catalog.modelDescriptor(for: .marinaChatSession))

        #expect(importRule.classification == .supportingData)
        #expect(aliasRule.classification == .resolverMemory)
        #expect(chatSession.classification == .conversationOnly)
        #expect(importRule.isPubliclyQueryable == false)
        #expect(aliasRule.isPubliclyQueryable == false)
        #expect(chatSession.isPubliclyQueryable == false)
    }

    @Test func catalogClassifiesElevenPublicModelsEightInternalSourcesAndConversationState() {
        let descriptors = Array(MarinaEntityCatalog().models.values)

        #expect(descriptors.filter { $0.classification == .publicEntity }.count == 11)
        #expect(descriptors.filter { $0.classification != .publicEntity && $0.classification != .conversationOnly }.count == 8)
        #expect(descriptors.filter { $0.classification == .conversationOnly }.map(\.model) == [.marinaChatSession])
    }

    @Test func activityAndMembershipModelsAreProjectionSources() throws {
        let catalog = MarinaEntityCatalog()
        let expected: [(MarinaSwiftDataModel, MarinaSemanticProjection)] = [
            (.budgetCardLink, .linkedCards),
            (.budgetPresetLink, .linkedPresets),
            (.expenseAllocation, .activity),
            (.allocationSettlement, .activity),
            (.savingsLedgerEntry, .activity)
        ]

        for (model, projection) in expected {
            let descriptor = try #require(catalog.modelDescriptor(for: model))
            #expect(descriptor.classification == .publicProjectionSource)
            #expect(descriptor.publicProjections.contains(projection))
        }
    }

    @Test func incomeSeriesDescriptorExposesScheduleWithoutMutationCapabilities() throws {
        let catalog = MarinaEntityCatalog()
        let descriptor = try #require(catalog.descriptor(for: .incomeSeries))
        let fields = Set(descriptor.fields.map(\.key))

        #expect(fields.isSuperset(of: [
            .source,
            .incomeAmount,
            .isPlanned,
            .frequency,
            .interval,
            .weeklyWeekday,
            .monthlyDayOfMonth,
            .monthlyIsLastDay,
            .yearlyMonth,
            .yearlyDayOfMonth,
            .startDate,
            .endDate
        ]))
        #expect(descriptor.supportedOperations == [.list, .count, .last, .next])
        #expect(catalog.supports(entity: .incomeSeries, projection: .occurrences) == .supported)
    }

    @Test func expandedMeasuresAreRegisteredForTheirOwningEntities() {
        let catalog = MarinaEntityCatalog()

        #expect(catalog.supports(entity: .variableExpense, measure: .ledgerSignedAmount) == .supported)
        #expect(catalog.supports(entity: .plannedExpense, measure: .projectedBudgetImpact) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .maximumSavings) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .projectedSavings) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .actualSavings) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .plannedIncomeTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .actualIncomeTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .plannedExpenseProjectedTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .plannedExpenseActualTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .plannedExpenseEffectiveTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .variableExpenseTotal) == .supported)
        #expect(catalog.supports(entity: .budget, measure: .unifiedExpenseTotal) == .supported)
    }

    @Test func workspaceRemainsMetadataOnly() {
        let catalog = MarinaEntityCatalog()

        #expect(catalog.projections[.workspace] == [.records])
        #expect(catalog.supports(entity: .workspace, operation: .sum) == .unsupported(.operationNotSupported))
        #expect(catalog.supports(entity: .workspace, measure: .projectedSavings) == .unsupported(.measureNotAvailable))
    }
}
