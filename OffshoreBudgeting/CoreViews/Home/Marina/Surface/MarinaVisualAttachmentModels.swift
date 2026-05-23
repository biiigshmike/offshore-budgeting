//
//  MarinaVisualAttachmentModels.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/22/26.
//

import Foundation

struct MarinaEntitySummaryPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let sourceID: UUID?
    let objectType: MarinaLookupObjectType
    let title: String
    let subtitle: String
    let primaryValue: String?
    let systemImage: String
    let tintHex: String?
    let rows: [DetailRow]

    init(
        id: UUID = UUID(),
        sourceID: UUID?,
        objectType: MarinaLookupObjectType,
        title: String,
        subtitle: String,
        primaryValue: String? = nil,
        systemImage: String,
        tintHex: String? = nil,
        rows: [DetailRow] = []
    ) {
        self.id = id
        self.sourceID = sourceID
        self.objectType = objectType
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.systemImage = systemImage
        self.tintHex = tintHex
        self.rows = rows
    }

    struct DetailRow: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let title: String
        let value: String

        init(id: UUID = UUID(), title: String, value: String) {
            self.id = id
            self.title = title
            self.value = value
        }
    }
}

struct MarinaRowListPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let family: Family
    let rows: [Row]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        family: Family,
        rows: [Row],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.family = family
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }

    enum Family: String, Codable, Equatable, Sendable {
        case expenses
        case reconciliation
        case savings
    }

    struct Row: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let sourceID: UUID?
        let objectType: MarinaLookupObjectType
        let title: String
        let subtitle: String?
        let value: String
        let secondaryValue: String?
        let amount: Double?
        let date: Date?
        let systemImage: String?
        let tintHex: String?

        init(
            id: UUID = UUID(),
            sourceID: UUID?,
            objectType: MarinaLookupObjectType,
            title: String,
            subtitle: String? = nil,
            value: String,
            secondaryValue: String? = nil,
            amount: Double? = nil,
            date: Date? = nil,
            systemImage: String? = nil,
            tintHex: String? = nil
        ) {
            self.id = id
            self.sourceID = sourceID
            self.objectType = objectType
            self.title = title
            self.subtitle = subtitle
            self.value = value
            self.secondaryValue = secondaryValue
            self.amount = amount
            self.date = date
            self.systemImage = systemImage
            self.tintHex = tintHex
        }
    }
}

struct MarinaMetricSummaryPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let systemImage: String
    let tintHex: String?
    let rows: [MarinaDisplayRow]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        systemImage: String = "chart.bar.fill",
        tintHex: String? = "#3B82F6",
        rows: [MarinaDisplayRow] = [],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.systemImage = systemImage
        self.tintHex = tintHex
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }
}

struct MarinaComparisonSummaryPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryLabel: String
    let primaryValue: String
    let comparisonLabel: String
    let comparisonValue: String
    let deltaLabel: String?
    let deltaValue: String?
    let rows: [MarinaDisplayRow]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryLabel: String,
        primaryValue: String,
        comparisonLabel: String,
        comparisonValue: String,
        deltaLabel: String? = nil,
        deltaValue: String? = nil,
        rows: [MarinaDisplayRow] = [],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryLabel = primaryLabel
        self.primaryValue = primaryValue
        self.comparisonLabel = comparisonLabel
        self.comparisonValue = comparisonValue
        self.deltaLabel = deltaLabel
        self.deltaValue = deltaValue
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }
}

struct MarinaBreakdownListPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [MarinaDisplayRow]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [MarinaDisplayRow],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }
}

struct MarinaTrendChartPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let points: [Point]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        points: [Point],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.points = points
        self.hidesSourceRows = hidesSourceRows
    }

    struct Point: Codable, Equatable, Identifiable, Sendable {
        let id: UUID
        let label: String
        let value: Double
        let renderedValue: String

        init(id: UUID = UUID(), label: String, value: Double, renderedValue: String) {
            self.id = id
            self.label = label
            self.value = value
            self.renderedValue = renderedValue
        }
    }
}

struct MarinaFormulaContractPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let status: String?
    let rows: [MarinaDisplayRow]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        status: String? = nil,
        rows: [MarinaDisplayRow],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }
}

struct MarinaGenericSummaryPresentationModel: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [MarinaDisplayRow]
    let hidesSourceRows: Bool

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [MarinaDisplayRow],
        hidesSourceRows: Bool = true
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.hidesSourceRows = hidesSourceRows
    }
}

struct MarinaDisplayRow: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let value: String
    let amount: Double?
    let date: Date?
    let sourceID: UUID?
    let objectType: MarinaLookupObjectType?
    let role: HomeAnswerRowRole

    init(
        id: UUID = UUID(),
        title: String,
        value: String,
        amount: Double? = nil,
        date: Date? = nil,
        sourceID: UUID? = nil,
        objectType: MarinaLookupObjectType? = nil,
        role: HomeAnswerRowRole = .result
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.amount = amount
        self.date = date
        self.sourceID = sourceID
        self.objectType = objectType
        self.role = role
    }
}
