import Foundation
@testable import Offshore

@MainActor
func sharedContext(
    fixture: MarinaPhase5Fixture,
    sharedPipelineEnabled: Bool = true,
    aiOptInEnabled: Bool = false,
    turnClassification: MarinaPromptTurnClassification = .freshQuestion,
    priorQueryContext: MarinaPriorQueryContext = .empty,
    now: Date = sharedPipelineDate(2026, 5, 15)
) -> MarinaSharedPipelineContext {
    MarinaSharedPipelineContext(
        provider: fixture.provider,
        routerContext: MarinaLanguageRouterContext(
            workspaceName: fixture.workspace.name,
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: priorQueryContext,
            cardNames: ["Apple Card", "Backup Card"],
            categoryNames: ["Groceries", "Travel"],
            incomeSourceNames: ["Salary"],
            presetTitles: [],
            budgetNames: [],
            aliasSummaries: [],
            now: now
        ),
        defaultPeriodUnit: .month,
        sharedPipelineEnabled: sharedPipelineEnabled,
        aiOptInEnabled: aiOptInEnabled,
        turnClassification: turnClassification,
        now: now
    )
}

func sharedPipelineDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
}

struct SharedPipelineStubAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

struct SharedPipelineStubStructuredInterpreter: MarinaStructuredIntentInterpreting {
    let structuredIntent: MarinaStructuredIntent

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        structuredIntent
    }
}

struct SharedPipelineThrowingStructuredInterpreter: MarinaStructuredIntentInterpreting {
    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        throw MarinaFoundationModelsServiceError.malformedResponse
    }
}
