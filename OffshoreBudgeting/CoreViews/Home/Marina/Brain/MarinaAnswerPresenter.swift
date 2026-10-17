import Foundation

struct MarinaAnswerPresenter {
    func present(
        result: MarinaExecutionResult,
        prompt: String?,
        queryID: UUID,
        semanticContext: MarinaAnswerSemanticContext? = nil,
        insightBundle: MarinaInsightBundle? = nil
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: queryID,
            kind: result.kind,
            userPrompt: prompt,
            title: result.title,
            subtitle: result.subtitle,
            primaryValue: result.primaryValue,
            rows: result.rows,
            attachment: result.attachment,
            explanation: result.explanation,
            semanticContext: semanticContext,
            insightBundle: insightBundle
        )
    }
}
