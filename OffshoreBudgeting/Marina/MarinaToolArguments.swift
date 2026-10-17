import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaToolPeriodKind: String, Codable, Sendable { case home, day, week, month, quarter, year, range }

@available(iOS 26.0, macOS 26.0, *)
struct MarinaToolPeriod: Codable, Sendable {
    var kind: MarinaToolPeriodKind
    var startOrAnchor: String? = nil
    var end: String? = nil

    func dates(calendar: Calendar) throws -> (String?, String?) {
        if kind == .home {
            return (nil, nil)
        }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        func parse(_ value: String?) throws -> Date {
            guard let value, let date = formatter.date(from: value), formatter.string(from: date) == value else { throw MarinaQueryError.invalid("Which dates did you mean? Please give a start and end date.") }
            return date
        }
        let anchor = try parse(startOrAnchor)
        if kind == .range {
            let last = try parse(end)
            guard anchor <= last else { throw MarinaQueryError.invalid("The period start must precede its end.") }
            return (formatter.string(from: anchor), formatter.string(from: last))
        }
        let period: BudgetingPeriod
        switch kind {
        case .day: period = .daily
        case .week: period = .weekly
        case .month: period = .monthly
        case .quarter: period = .quarterly
        case .year: period = .yearly
        case .home, .range: throw MarinaQueryError.invalid("Invalid calendar period.")
        }
        let range = period.defaultRange(containing: anchor, calendar: calendar)
        return (formatter.string(from: range.start), formatter.string(from: range.end))
    }
}

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaToolRecordState: String, Codable, Sendable { case any, recorded, expectedOnly }

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaToolAmountScope: String, Codable, Sendable { case unrestricted, range, around }

/// Flat model arguments; Swift resolves periods and validates all financial query inputs.
@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaToolQuery: Codable, Sendable {
    @Guide(description: "expenses = card transactions; plannedExpenses = all planned costs; income = received or expected income; budgets = periods/outlook; savings and reconciliation are separate ledgers.")
    var domain: MarinaDomain = .expenses
    @Guide(description: "total/count/average for statistics; timeTrend/categoryBreakdown for charts; balance for account balances; projectedSavings/actualSurplus for budget outlook. Use total for record lists.")
    var metric: MarinaMetric = .total
    @Guide(description: "range with no dates uses Home; week/month/quarter/year uses startDate as anchor, with boundaries calculated by Swift.")
    var periodKind: MarinaToolPeriodKind = .range
    @Guide(description: "Gregorian yyyy-MM-dd start date or calendar-period anchor; otherwise nil.")
    var startDate: String? = nil
    @Guide(description: "Inclusive Gregorian yyyy-MM-dd end date; otherwise nil.")
    var endDate: String? = nil
    @Guide(description: "Exact name or resolved UUID only when explicitly requested; otherwise nil.")
    var card: String? = nil
    @Guide(description: "Category explicitly requested by the user, otherwise nil. Use Unclassified for records with no category. Never infer a category from an amount or date.")
    var category: String? = nil
    @Guide(description: "Savings/reconciliation account explicitly requested, otherwise nil. Exact name only, without words like account unless part of the stored name.")
    var account: String? = nil
    @Guide(description: "Existing budget explicitly named by the user, otherwise nil. A week or month belongs in dates, never here.")
    var budget: String? = nil
    @Guide(description: "Only explicitly requested merchant/description text. Never amounts, dates, or words like around. Otherwise nil.")
    var descriptionText: String? = nil
    @Guide(description: "unrestricted for all records in a period, even when an amount is remembered. range only for explicitly requested amount limits. around only when the requested search is for a particular approximate amount.")
    var amountScope: MarinaToolAmountScope = .unrestricted
    @Guide(description: "Lower limit for range; remembered target for around; ignored for unrestricted.")
    var minAmount: Double? = nil
    @Guide(description: "Upper limit for range; target for around if minAmount is nil; ignored for unrestricted.")
    var maxAmount: Double? = nil
    @Guide(description: "Default any, including recorded and unrecorded planned expenses. recorded or expectedOnly only when explicitly requested.")
    var state: MarinaToolRecordState = .any
    var includeFuture: Bool? = nil
    @Guide(description: "Second comparison period start, otherwise nil.")
    var comparisonStartDate: String? = nil
    @Guide(description: "Second comparison period end, otherwise nil.")
    var comparisonEndDate: String? = nil

    init() {}
    init(query: MarinaQueryRequest) {
        domain = query.domain; metric = query.metric; startDate = query.startDate; endDate = query.endDate
        card = query.cardID ?? query.cardName; category = query.categoryID ?? query.categoryName
        account = query.accountID ?? query.accountName; budget = query.budgetID ?? query.budgetName
        descriptionText = query.text; minAmount = query.minAmount; maxAmount = query.maxAmount
        amountScope = query.minAmount == nil && query.maxAmount == nil ? .unrestricted : .range
        state = query.state == .all ? .any : query.state == .actual ? .recorded : .expectedOnly
        includeFuture = query.includeFuture; comparisonStartDate = query.comparisonStartDate; comparisonEndDate = query.comparisonEndDate
    }

    func request(calendar: Calendar = .current) throws -> MarinaQueryRequest {
        var result = MarinaQueryRequest(); result.domain = domain; result.metric = metric
        result.state = state == .any ? .all : state == .recorded ? .actual : .planned
        result.includeFuture = includeFuture
        if periodKind != .range || startDate != nil || endDate != nil {
            (result.startDate, result.endDate) = try MarinaToolPeriod(kind: periodKind, startOrAnchor: startDate, end: endDate).dates(calendar: calendar)
        }
        if comparisonStartDate != nil || comparisonEndDate != nil {
            guard metric == .comparison else { throw MarinaQueryError.invalid("A comparison period requires the comparison metric.") }
            (result.comparisonStartDate, result.comparisonEndDate) = try MarinaToolPeriod(kind: .range, startOrAnchor: comparisonStartDate, end: comparisonEndDate).dates(calendar: calendar)
        }
        func entity(_ value: String?) throws -> (name: String?, id: String?) {
            guard let value else { return (nil, nil) }
            let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw MarinaQueryError.invalid("Entity filters need a name or resolved ID.") }
            return UUID(uuidString: clean) != nil ? (nil, clean) : (clean, nil)
        }
        (result.cardName, result.cardID) = try entity(card)
        (result.categoryName, result.categoryID) = try entity(category)
        (result.accountName, result.accountID) = try entity(account)
        (result.budgetName, result.budgetID) = try entity(budget)
        if let descriptionText {
            let clean = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { throw MarinaQueryError.invalid("Description filter needs text.") }
            result.text = clean
        }
        if amountScope == .unrestricted { return result }
        for amount in [minAmount, maxAmount].compactMap({ $0 }) {
            guard amount.isFinite, amount >= 0 else { throw MarinaQueryError.invalid("Amount filters must be finite and nonnegative.") }
        }
        if amountScope == .around {
            guard let target = minAmount ?? maxAmount else { throw MarinaQueryError.invalid("What approximate amount did you mean?") }
            result.minAmount = target * 0.9; result.maxAmount = target * 1.1
            return result
        }
        if let minAmount, let maxAmount, minAmount > maxAmount { throw MarinaQueryError.invalid("Minimum amount exceeds maximum.") }
        result.minAmount = minAmount; result.maxAmount = maxAmount
        return result
    }
}
