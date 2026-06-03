import Foundation

enum MarinaHomeAnswerLocalizer {
    static func localized(_ answer: HomeAnswer) -> HomeAnswer {
        HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: localizedTitle(answer.title),
            subtitle: answer.subtitle.map { localizedSubtitle($0) },
            primaryValue: answer.primaryValue.map { localizedValue($0) },
            rows: answer.rows.map { localizedRow($0) },
            attachment: answer.attachment,
            explanation: answer.explanation,
            semanticContext: answer.semanticContext,
            insightBundle: answer.insightBundle,
            generatedAt: answer.generatedAt
        )
    }

    private static func localizedRow(_ row: HomeAnswerRow) -> HomeAnswerRow {
        HomeAnswerRow(
            id: row.id,
            title: localizedRowTitle(row.title),
            value: localizedValue(row.value),
            sourceID: row.sourceID,
            objectType: row.objectType,
            amount: row.amount,
            date: row.date,
            role: row.role
        )
    }

    private static func localizedTitle(_ value: String) -> String {
        if let target = parentheticalTarget(in: value, base: "Next Planned Expense") {
            return MarinaL10n.format("marina.homeAnswer.nextPlannedExpenseFormat", defaultValue: "Next Planned Expense (%@)", comment: "Home answer title reused by Marina with a named target.", target)
        }
        if let target = parentheticalTarget(in: value, base: "Spend Trends") {
            return MarinaL10n.format("marina.homeAnswer.spendTrendsFormat", defaultValue: "Spend Trends (%@)", comment: "Home answer title reused by Marina with a named target.", target)
        }
        if let target = suffixTarget(in: value, suffix: " Snapshot") {
            return MarinaL10n.format("marina.homeAnswer.namedSnapshot", defaultValue: "%@ Snapshot", comment: "Home answer title reused by Marina with a named target.", target)
        }

        switch value {
        case "Budget Overview":
            return MarinaL10n.string("marina.homeAnswer.budgetOverview", defaultValue: "Budget Overview", comment: "Home answer title reused by Marina.")
        case "Category Availability":
            return MarinaL10n.string("marina.answer.categoryAvailability.title", defaultValue: "Category Availability", comment: "Marina answer title for category availability.")
        case "Category Spend Share":
            return MarinaL10n.string("marina.homeAnswer.categorySpendShare", defaultValue: "Category Spend Share", comment: "Home answer title reused by Marina.")
        case "Forecast Savings":
            return MarinaL10n.string("marina.homeAnswer.forecastSavings", defaultValue: "Forecast Savings", comment: "Home answer title reused by Marina.")
        case "Income Progress":
            return MarinaL10n.string("marina.homeAnswer.incomeProgress", defaultValue: "Income Progress", comment: "Home answer title reused by Marina.")
        case "Next Planned Expense":
            return MarinaL10n.string("marina.homeAnswer.nextPlannedExpense", defaultValue: "Next Planned Expense", comment: "Home answer title reused by Marina.")
        case "Safe Spend Today":
            return MarinaL10n.string("marina.homeAnswer.safeSpendToday", defaultValue: "Safe Spend Today", comment: "Home answer title reused by Marina.")
        case "Savings Status":
            return MarinaL10n.string("marina.homeAnswer.savingsStatus", defaultValue: "Savings Status", comment: "Home answer title reused by Marina.")
        case "Spend Trends":
            return MarinaL10n.string("marina.homeAnswer.spendTrends", defaultValue: "Spend Trends", comment: "Home answer title reused by Marina.")
        default:
            return value
        }
    }

    private static func localizedSubtitle(_ value: String) -> String {
        switch value {
        case "No budget overlaps this range.":
            return MarinaL10n.string("marina.homeAnswer.noBudgetOverlaps", defaultValue: "No budget overlaps this range.", comment: "Home answer subtitle reused by Marina.")
        case "No categories found.":
            return MarinaL10n.string("marina.homeAnswer.noCategoriesFound", defaultValue: "No categories found.", comment: "Home answer subtitle reused by Marina.")
        case "No savings activity in this range yet.":
            return MarinaL10n.string("marina.homeAnswer.noSavingsActivity", defaultValue: "No savings activity in this range yet.", comment: "Home answer subtitle reused by Marina.")
        case "No spending activity in this range yet.":
            return MarinaL10n.string("marina.homeAnswer.noSpendingActivity", defaultValue: "No spending activity in this range yet.", comment: "Home answer subtitle reused by Marina.")
        case "No upcoming planned expenses in this range.":
            return MarinaL10n.string("marina.homeAnswer.noUpcomingPlannedExpenses", defaultValue: "No upcoming planned expenses in this range.", comment: "Home answer subtitle reused by Marina.")
        case "Not enough budget activity in this range yet.":
            return MarinaL10n.string("marina.homeAnswer.notEnoughBudgetActivity", defaultValue: "Not enough budget activity in this range yet.", comment: "Home answer subtitle reused by Marina.")
        default:
            return value
        }
    }

    private static func localizedRowTitle(_ value: String) -> String {
        switch value {
        case "Actual":
            return MarinaL10n.common("actual", defaultValue: "Actual", comment: "Common label for actual values.")
        case "Actual savings":
            return MarinaL10n.string("marina.homeAnswer.actualSavings", defaultValue: "Actual savings", comment: "Home answer row label reused by Marina.")
        case "Budget":
            return MarinaL10n.common("budget", defaultValue: "Budget", comment: "Common label for budget.")
        case "Card":
            return MarinaL10n.common("card", defaultValue: "Card", comment: "Common label for card.")
        case "Category":
            return MarinaL10n.common("category", defaultValue: "Category", comment: "Common label for category.")
        case "Categories":
            return MarinaL10n.common("categories", defaultValue: "Categories", comment: "Common label for categories.")
        case "Date":
            return MarinaL10n.common("date", defaultValue: "Date", comment: "Common label for a date field.")
        case "Days left in period":
            return MarinaL10n.string("marina.homeAnswer.daysLeftInPeriod", defaultValue: "Days left in period", comment: "Home answer row label reused by Marina.")
        case "Expense":
            return MarinaL10n.common("expense", defaultValue: "Expense", comment: "Common label for expense.")
        case "Gap to projected":
            return MarinaL10n.string("marina.homeAnswer.gapToProjected", defaultValue: "Gap to projected", comment: "Home answer row label reused by Marina.")
        case "Period":
            return MarinaL10n.common("period", defaultValue: "Period", comment: "Common label for a date period.")
        case "Period remaining room":
            return MarinaL10n.string("marina.homeAnswer.periodRemainingRoom", defaultValue: "Period remaining room", comment: "Home answer row label reused by Marina.")
        case "Planned":
            return MarinaL10n.common("planned", defaultValue: "Planned", comment: "Common label for planned values.")
        case "Progress":
            return MarinaL10n.string("marina.homeAnswer.progress", defaultValue: "Progress", comment: "Home answer row label reused by Marina.")
        case "Projected savings":
            return MarinaL10n.string("marina.homeAnswer.projectedSavings", defaultValue: "Projected savings", comment: "Home answer row label reused by Marina.")
        case "Status":
            return MarinaL10n.common("status", defaultValue: "Status", comment: "Common label for status.")
        case "Top category":
            return MarinaL10n.string("marina.homeAnswer.topCategory", defaultValue: "Top category", comment: "Home answer row label reused by Marina.")
        default:
            return value
        }
    }

    private static func localizedValue(_ value: String) -> String {
        switch value {
        case "Current actual savings are negative.":
            return MarinaL10n.string("marina.homeAnswer.status.actualSavingsNegative", defaultValue: "Current actual savings are negative.", comment: "Forecast savings status reused by Marina.")
        case "Forecast is currently on track.":
            return MarinaL10n.string("marina.homeAnswer.status.forecastOnTrack", defaultValue: "Forecast is currently on track.", comment: "Forecast savings status reused by Marina.")
        case "No change":
            return MarinaL10n.string("marina.answer.delta.noChange", defaultValue: "No change", comment: "Delta summary when there is no change.")
        case "Overspending forecast for this period.":
            return MarinaL10n.string("marina.homeAnswer.status.overspendingForecast", defaultValue: "Overspending forecast for this period.", comment: "Forecast savings status reused by Marina.")
        default:
            if value.hasPrefix("Up ") {
                return MarinaL10n.format("marina.answer.delta.up", defaultValue: "Up %@", comment: "Delta summary for an increase.", String(value.dropFirst(3)))
            }
            if value.hasPrefix("Down ") {
                return MarinaL10n.format("marina.answer.delta.down", defaultValue: "Down %@", comment: "Delta summary for a decrease.", String(value.dropFirst(5)))
            }
            return value
        }
    }

    private static func parentheticalTarget(in value: String, base: String) -> String? {
        guard value.hasPrefix("\(base) ("),
              value.hasSuffix(")") else { return nil }
        let start = value.index(value.startIndex, offsetBy: base.count + 2)
        return String(value[start..<value.index(before: value.endIndex)])
    }

    private static func suffixTarget(in value: String, suffix: String) -> String? {
        guard value.hasSuffix(suffix), value.count > suffix.count else { return nil }
        return String(value.dropLast(suffix.count))
    }
}
