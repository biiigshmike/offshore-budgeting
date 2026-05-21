import Foundation
import SwiftData

@MainActor
struct MarinaV2PanelRuntime {
    let modelContext: ModelContext
    let workspaceID: UUID
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let runtimeSettings: MarinaRuntimeSettings
    let routerContext: MarinaLanguageRouterContext
    let turnClassification: MarinaPromptTurnClassification
    let coordinator: MarinaV2TurnCoordinator

    init(
        modelContext: ModelContext,
        workspaceID: UUID,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        runtimeSettings: MarinaRuntimeSettings,
        routerContext: MarinaLanguageRouterContext,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        coordinator: MarinaV2TurnCoordinator? = nil
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.defaultPeriodUnit = defaultPeriodUnit
        self.runtimeSettings = runtimeSettings
        self.routerContext = routerContext
        self.turnClassification = turnClassification
        self.coordinator = coordinator ?? Self.defaultCoordinator()
    }

    func run(prompt: String) async -> MarinaV2TurnResult {
        await coordinator.run(
            prompt: prompt,
            context: turnContext
        )
    }

    func run(query: HomeQuery, sourceTitle: String) async -> MarinaV2TurnResult {
        await coordinator.run(
            query: query,
            sourceTitle: sourceTitle,
            context: turnContext
        )
    }

    func resume(
        clarification: MarinaTypedClarification,
        choice: MarinaClarificationChoice
    ) async -> MarinaV2TurnResult {
        await coordinator.resume(
            clarification: clarification,
            choice: choice,
            context: turnContext
        )
    }

    private var turnContext: MarinaV2TurnContext {
        MarinaV2TurnContext(
            provider: MarinaDataProvider(modelContext: modelContext, workspaceID: workspaceID),
            routerContext: routerContext,
            defaultPeriodUnit: defaultPeriodUnit,
            aiEnabled: runtimeSettings.aiOptIn.isEnabled,
            now: runtimeSettings.now,
            turnClassification: turnClassification
        )
    }

    private static func defaultCoordinator() -> MarinaV2TurnCoordinator {
        #if DEBUG
        if MarinaV2UIFixtureAIInterpreter.isEnabled {
            return MarinaV2TurnCoordinator(
                availability: MarinaV2UIFixtureAvailability(),
                interpreter: MarinaV2UIFixtureAIInterpreter()
            )
        }
        #endif
        return MarinaV2TurnCoordinator()
    }
}
