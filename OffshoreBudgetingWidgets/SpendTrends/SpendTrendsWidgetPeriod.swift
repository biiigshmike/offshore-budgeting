//
//  SpendTrendsWidgetPeriod.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation

enum SpendTrendsWidgetPeriod: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
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
