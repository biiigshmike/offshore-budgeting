import Foundation

struct HomeAssistantSharedPipelineCommandGuard {
    let commandParser: HomeAssistantCommandParser

    init(commandParser: HomeAssistantCommandParser = HomeAssistantCommandParser()) {
        self.commandParser = commandParser
    }

    func command(
        for prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeAssistantCommandPlan? {
        commandParser.parse(prompt, defaultPeriodUnit: defaultPeriodUnit)
    }
}

