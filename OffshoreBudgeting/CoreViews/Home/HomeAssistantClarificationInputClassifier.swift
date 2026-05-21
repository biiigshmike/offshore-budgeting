import Foundation

struct HomeAssistantClarificationInputClassifier {
    private let turnClassifier: MarinaPromptTurnClassifier

    init(
        commandGuard: HomeAssistantFoundationPipelineCommandGuard = HomeAssistantFoundationPipelineCommandGuard(),
        parser: HomeAssistantTextParser = HomeAssistantTextParser()
    ) {
        self.turnClassifier = MarinaPromptTurnClassifier(
            commandGuard: commandGuard,
            parser: parser
        )
    }

    func shouldTreatAsFreshPrompt(
        _ prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> Bool {
        turnClassifier.shouldTreatAsFreshPrompt(
            prompt,
            defaultPeriodUnit: defaultPeriodUnit
        )
    }
}
