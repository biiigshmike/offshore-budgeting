//
//  NextPlannedExpenseWidgetPeriod.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation

enum NextPlannedExpenseWidgetPeriod: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case period = "P"
    case oneWeek = "1W"
    case oneMonth = "1M"
    case oneYear = "1Y"
    case q = "Q"

    var id: String { rawValue }
}
