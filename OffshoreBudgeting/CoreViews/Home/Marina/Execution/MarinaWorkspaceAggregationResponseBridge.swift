import Foundation

struct MarinaWorkspaceAggregationResponseBridge {
    func responseCompatibleAnswer(from card: MarinaWorkspaceAggregationCard) -> HomeAnswer {
        let rows = card.rows.isEmpty == false ? card.rows : card.items.map { item in
            MarinaWorkspaceAggregationCard.Row(
                label: item.label,
                value: item.subtitle.map { "\(item.value) • \($0)" } ?? item.value,
                amount: item.amount,
                date: item.date,
                objectType: item.objectType,
                sourceID: item.sourceID,
                sortValue: item.sortValue,
                role: item.role
            )
        }

        return HomeAnswer(
            queryID: card.id,
            kind: card.answerKind,
            title: card.title,
            subtitle: card.subtitle,
            primaryValue: card.primaryValue,
            rows: rows.map {
                HomeAnswerRow(
                    title: $0.label,
                    value: $0.value,
                    sourceID: $0.sourceID,
                    objectType: $0.objectType,
                    amount: $0.amount,
                    date: $0.date,
                    role: $0.role
                )
            }
        )
    }
}
