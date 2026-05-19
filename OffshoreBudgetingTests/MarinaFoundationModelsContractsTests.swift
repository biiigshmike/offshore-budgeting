import Foundation
import Testing
@testable import Offshore

struct MarinaFoundationModelsContractsTests {
    @Test func routeIntent_mapsRawRoutes() {
        #expect(route("read_query") == .readQuery)
        #expect(route("analytics") == .readQuery)
        #expect(route("databaseLookup") == .lookup)
        #expect(route("clarify") == .clarification)
        #expect(route("capabilities") == .help)
        #expect(route("createExpense") == .unsupported)
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test func clarificationIntent_mapsFieldsToStructuredClarification() {
        let intent = MarinaFoundationClarificationIntent(
            reasoning: "Groceries may be a category or merchant.",
            kindRaw: "ambiguousTarget",
            message: "Which Groceries did you mean?",
            missingFieldRaws: ["date_range"],
            ambiguousFieldRaws: ["target"],
            patchSlotRaw: "targetName",
            shouldRunBestEffort: false
        )

        let clarification = intent.structuredClarification

        #expect(clarification.subtitle == "Which Groceries did you mean?")
        #expect(clarification.missingFields == [.dateRange])
        #expect(clarification.ambiguities.map(\.field) == [.targetName])
        #expect(clarification.shouldRunBestEffort == false)
    }

    @Test func evalCorpus_stubbedRouteContractsMatchExpectedRoutes() {
        let corpus: [(prompt: String, routeRaw: String, expected: MarinaFoundationRouteKind)] = [
            (
                "How much did I spend on groceries this month?",
                "readQuery",
                .readQuery
            ),
            (
                "Show me the Apple Card details",
                "lookup",
                .lookup
            ),
            (
                "Add a $25 coffee expense",
                "unsupported",
                .unsupported
            ),
            (
                "What can Marina answer?",
                "help",
                .help
            )
        ]

        for item in corpus {
            #expect(
                MarinaFoundationRouteKind(routeRaw: item.routeRaw) == item.expected,
                "Prompt '\(item.prompt)' should route to \(item.expected.rawValue)"
            )
        }
    }

    @Test func runtimeTraceSummary_includesFoundationPromptVersioning() {
        let settings = MarinaRuntimeSettings.resolve(
            nlqV1Fallback: false,
            sharedPipelineFallback: true,
            aiOptInFallback: true,
            defaults: UserDefaults(suiteName: "MarinaFoundationModelsContractsTests")!,
            arguments: [],
            environment: [:]
        )

        #expect(settings.traceSummary.contains(MarinaFoundationPromptVersion.interpretationV1.rawValue))
        #expect(settings.traceSummary.contains(MarinaFoundationPromptVersion.presentationV1.rawValue))
        #expect(settings.traceSummary.contains("foundationModelBand="))
        #expect(settings.traceSummary.contains("foundationLocale="))
    }

    private func route(_ raw: String) -> MarinaFoundationRouteKind {
        MarinaFoundationRouteKind(routeRaw: raw)
    }
}
