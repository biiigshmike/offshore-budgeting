//
//  CardWidgetPeriod.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation

enum CardWidgetPeriod: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case period = "P"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case oneYear = "1Y"
    case q1 = "Q1"
    case q2 = "Q2"
    case q3 = "Q3"
    case q4 = "Q4"

    var id: String { rawValue }
}
