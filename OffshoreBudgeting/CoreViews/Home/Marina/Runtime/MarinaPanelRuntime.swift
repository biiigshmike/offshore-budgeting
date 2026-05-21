import Foundation
import SwiftData

@MainActor
struct MarinaPanelRuntime {
    let modelContext: ModelContext
    let workspaceID: UUID
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let runtimeSettings: MarinaRuntimeSettings
    let routerContext: MarinaInterpretationContext
    let turnClassification: MarinaPromptTurnClassification
    let coordinator: MarinaTurnCoordinator

    init(
        modelContext: ModelContext,
        workspaceID: UUID,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        runtimeSettings: MarinaRuntimeSettings,
        routerContext: MarinaInterpretationContext,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        coordinator: MarinaTurnCoordinator? = nil
    ) {
        self.modelContext = modelContext
        self.workspaceID = workspaceID
        self.defaultPeriodUnit = defaultPeriodUnit
        self.runtimeSettings = runtimeSettings
        self.routerContext = routerContext
        self.turnClassification = turnClassification
        self.coordinator = coordinator ?? Self.defaultCoordinator()
    }

    func run(prompt: String) async -> MarinaTurnResult {
        await coordinator.run(
            prompt: prompt,
            context: turnContext
        )
    }

    func run(query: HomeQuery, sourceTitle: String) async -> MarinaTurnResult {
        await coordinator.run(
            query: query,
            sourceTitle: sourceTitle,
            context: turnContext
        )
    }

    func resume(
        clarification: MarinaTypedClarification,
        choice: MarinaClarificationChoice
    ) async -> MarinaTurnResult {
        await coordinator.resume(
            clarification: clarification,
            choice: choice,
            context: turnContext
        )
    }

    private var turnContext: MarinaTurnContext {
        MarinaTurnContext(
            provider: MarinaDataProvider(modelContext: modelContext, workspaceID: workspaceID),
            routerContext: routerContext,
            defaultPeriodUnit: defaultPeriodUnit,
            aiEnabled: runtimeSettings.aiOptIn.isEnabled,
            now: runtimeSettings.now,
            turnClassification: turnClassification
        )
    }

    private static func defaultCoordinator() -> MarinaTurnCoordinator {
        #if DEBUG
        if MarinaTypedFixtureInterpreter.isEnabled {
            return MarinaTurnCoordinator(
                availability: MarinaTypedFixtureAvailability(),
                interpreter: MarinaTypedFixtureInterpreter()
            )
        }
        #endif
        return MarinaTurnCoordinator()
    }
}
