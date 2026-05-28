//
//  HomeSpendTrendsMetricsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

struct HomeSpendTrendsMetricsView: View {

    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date
    let initialPeriod: HomeSpendTrendsAggregator.Period

    @State private var selectedPeriod: HomeSpendTrendsAggregator.Period
    @State private var selectedCardID: UUID? = nil
    @State private var selectedBucketID: HomeSpendTrendsAggregator.Bucket.ID? = nil

    private let selectableBucketEpsilon: Double = 1.00

    init(
        workspace: Workspace,
        cards: [Card],
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        startDate: Date,
        endDate: Date,
        initialPeriod: HomeSpendTrendsAggregator.Period = .period
    ) {
        self.workspace = workspace
        self.cards = cards
        self.categories = categories
        self.plannedExpenses = plannedExpenses
        self.variableExpenses = variableExpenses
        self.startDate = startDate
        self.endDate = endDate
        self.initialPeriod = initialPeriod
        _selectedPeriod = State(initialValue: initialPeriod)
    }

    var body: some View {
        let selectedCard = selectedCardID.flatMap { id in cards.first(where: { $0.id == id }) }

        let result = HomeSpendTrendsAggregator.calculate(
            period: selectedPeriod,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate,
            cardFilter: selectedCard,
            topN: 3
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerSummary(
                    totalSpent: result.totalSpent,
                    selectedCard: selectedCard
                )

                periodPicker

                cardCarousel

                chartCard(result: result, showsCardName: selectedCard == nil)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("") // render a custom title + subtitle in the navigation area
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(
                        String(
                            localized: "homeWidget.spendTrends.title",
                            defaultValue: "Spend Trends",
                            comment: "Widget title for the spend trends experience."
                        )
                    )
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(formattedDate(result.resolvedStart)) - \(formattedDate(result.resolvedEnd))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: selectedPeriod) { _, _ in
            selectedBucketID = nil
        }
    }

    // MARK: - Header

    private func headerSummary(
        totalSpent: Double,
        selectedCard: Card?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                String(
                    localized: "homeWidget.spendTrends.totalSpending",
                    defaultValue: "Total Spending",
                    comment: "Summary metric label for total spending."
                )
            )
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalSpent, format: CurrencyFormatter.currencyStyle())
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Picker

    private var periodPicker: some View {
        Picker(
            String(
                localized: "homeWidget.spendTrends.period",
                defaultValue: "Period",
                comment: "Picker label for spend trends period."
            ),
            selection: $selectedPeriod
        ) {
            ForEach(HomeSpendTrendsAggregator.Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(
            String(
                localized: "homeWidget.spendTrends.period",
                defaultValue: "Period",
                comment: "Accessibility label for spend trends period picker."
            )
        )
    }

    // MARK: - Card carousel (replaces Menu)

    private var cardCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(
                    selectedCardID
                        .flatMap { id in cards.first(where: { $0.id == id })?.name }
                    ?? String(
                        localized: "homeWidget.spendTrends.allCards",
                        defaultValue: "All Cards",
                        comment: "Filter value indicating spend trends includes all cards."
                    )
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {

                    ForEach(cards) { card in
                        SpendTrendsCardTile(
                            title: card.name,
                            themeRaw: card.theme,
                            effectRaw: card.effect,
                            isSelected: selectedCardID == card.id
                        ) {
                            toggleCardSelection(card)
                        }
                        .accessibilityLabel(selectedCardID == card.id ? "\(card.name), selected" : card.name)
                        .accessibilityHint(
                            String(
                                localized: "homeWidget.spendTrends.cardHint",
                                defaultValue: "Double tap to filter spend trends to this card. Tap again to clear and return to period P.",
                                comment: "Accessibility hint for selecting a card in spend trends."
                            )
                        )
                    }
                }
                .padding(6)
            }
            Text(
                String(
                    localized: "homeWidget.spendTrends.cardInstruction",
                    defaultValue: "Press a card to view spending by category for the selected card. Press it again to clear your selection.",
                    comment: "Instruction text for using card filter in spend trends."
                )
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleCardSelection(_ card: Card) {
        selectedBucketID = nil

        if selectedCardID == card.id {
            // Tap again: clear selection and return to "P"
            selectedCardID = nil
            selectedPeriod = .period
        } else {
            selectedCardID = card.id
        }
    }

    // MARK: - Chart

    private func chartCard(
        result: HomeSpendTrendsAggregator.Result,
        showsCardName: Bool
    ) -> some View {
        let selectedBucket = selectedBucket(in: result)

        return VStack(alignment: .leading, spacing: 10) {
            Text(
                String(
                    localized: "homeWidget.spendTrends.spending",
                    defaultValue: "Spending",
                    comment: "Section title for spend chart."
                )
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if result.buckets.allSatisfy({ $0.total <= 0 }) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        String(
                            localized: "homeWidget.spendTrends.noDataInRange",
                            defaultValue: "No spending data found in this range.",
                            comment: "Message shown when there is no spending data for the selected range."
                        )
                    )
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .padding(.vertical, 18)
            } else {
                Chart {
                    // Invisible marks: these define x buckets + y scale for the chart.
                    ForEach(result.buckets) { bucket in
                        PointMark(
                            x: .value("Bucket", bucket.label),
                            y: .value("Amount", max(bucket.total, 0.000_001))
                        )
                        .symbolSize(0)
                        .foregroundStyle(.clear)
                        .opacity(0.001)
                        .accessibilityHidden(true)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.22))
                        AxisTick().foregroundStyle(.secondary.opacity(0.28))
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                            .foregroundStyle(Color.secondary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisTick().foregroundStyle(.secondary.opacity(0.26))
                        AxisValueLabel()
                            .foregroundStyle(Color.secondary)
                    }
                }
                .frame(height: 240)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if let plotAnchor = proxy.plotFrame {
                            let plotFrame = geo[plotAnchor]
                            let barSlotWidth = plotFrame.width / CGFloat(max(5, result.buckets.count))
                            let hitSlotWidth = plotFrame.width / CGFloat(max(1, result.buckets.count))
                            let barWidth = min(84, barSlotWidth * 0.78)
                            let hitWidth = max(44, min(96, hitSlotWidth))

                            ZStack(alignment: .topLeading) {
                                ForEach(result.buckets) { bucket in
                                    HeatMapBucketBar(
                                        bucket: bucket,
                                        proxy: proxy,
                                        plotFrame: plotFrame,
                                        height: plotFrame.height,
                                        barWidth: barWidth,
                                        isSelected: bucket.id == selectedBucketID,
                                        colorForSlice: color(for:)
                                    )
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                                }

                                ForEach(result.buckets) { bucket in
                                    HeatMapBucketSelectionButton(
                                        bucket: bucket,
                                        proxy: proxy,
                                        plotFrame: plotFrame,
                                        hitWidth: hitWidth,
                                        isSelected: bucket.id == selectedBucketID
                                    ) {
                                        toggleBucketSelection(bucket)
                                    }
                                }
                            }
                            .frame(width: plotFrame.width, height: plotFrame.height)
                            .position(x: plotFrame.midX, y: plotFrame.midY)
                        }
                    }
                }

                highestCallout(result: result)
                    .padding(.top, 6)

                Text(
                    String(
                        localized: "homeWidget.spendTrends.bucketInstruction",
                        defaultValue: "Press a bar to view the expenses in that spending bucket. Press it again to hide the breakdown.",
                        comment: "Instruction text explaining that spend trends chart bars are actionable."
                    )
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                if let selectedBucket {
                    SpendTrendsBucketBreakdownView(
                        bucket: selectedBucket,
                        showsCardName: showsCardName
                    )
                    .padding(.top, 8)
                }
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func selectedBucket(
        in result: HomeSpendTrendsAggregator.Result
    ) -> HomeSpendTrendsAggregator.Bucket? {
        guard let selectedBucketID else { return nil }
        return result.buckets.first { bucket in
            bucket.id == selectedBucketID && bucket.total > selectableBucketEpsilon
        }
    }

    private func toggleBucketSelection(_ bucket: HomeSpendTrendsAggregator.Bucket) {
        guard bucket.total > selectableBucketEpsilon else { return }

        if selectedBucketID == bucket.id {
            selectedBucketID = nil
        } else {
            selectedBucketID = bucket.id
        }
    }

    private func highestCallout(result: HomeSpendTrendsAggregator.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            if let highest = result.highestBucket {
                Text(
                    String(
                        format: String(
                            localized: "homeWidget.spendTrends.highestSummaryFormat",
                            defaultValue: "Highest: %1$@ • %2$@",
                            comment: "Summary line showing highest spending bucket and amount."
                        ),
                        locale: .current,
                        highest.label,
                        highest.total.formatted(CurrencyFormatter.currencyStyle())
                    )
                )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let top = result.topCategoryInHighestBucket {
                Text(
                    String(
                        format: String(
                            localized: "homeWidget.spendTrends.topSummaryFormat",
                            defaultValue: "Top: %1$@ • %2$@",
                            comment: "Summary line showing the top category and amount in the highest bucket."
                        ),
                        locale: .current,
                        top.name,
                        top.amount.formatted(CurrencyFormatter.currencyStyle())
                    )
                )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Color mapping

    private func color(for slice: HomeSpendTrendsAggregator.Slice) -> Color {
        if let hex = slice.hexColor, let c = Color(hex: hex) {
            return c
        }

        if slice.name == "Other" {
            return .secondary.opacity(0.58)
        }

        if slice.name == "Uncategorized" {
            return .secondary.opacity(0.48)
        }

        return .secondary.opacity(0.6)
    }

    // MARK: - Date helpers

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }
}

// MARK: - Card tiles (local)

private struct SpendTrendsCardTile: View {
    let title: String
    let themeRaw: String
    let effectRaw: String
    let isSelected: Bool
    let onTap: () -> Void

    private let tileWidth: CGFloat = 160

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {

                CardVisualView(
                    title: title,
                    theme: themeOption(from: themeRaw),
                    effect: effectOption(from: effectRaw),
                    minHeight: nil,
                    showsShadow: false,
                    titleFont: .headline,
                    titlePadding: 12,
                    titleOpacity: 0.82
                )
                .frame(width: tileWidth)

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func themeOption(from raw: String) -> CardThemeOption {
        CardThemeOption(rawValue: raw) ?? .charcoal
    }

    private func effectOption(from raw: String) -> CardEffectOption {
        CardEffectOption(rawValue: raw) ?? .plastic
    }
}

// MARK: - Bucket breakdown

private struct SpendTrendsBucketBreakdownView: View {
    let bucket: HomeSpendTrendsAggregator.Bucket
    let showsCardName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .padding(.bottom, 2)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(bucket.label)
                        .font(.headline.weight(.semibold))

                    Text("\(formattedDate(bucket.start)) - \(formattedDate(bucket.end))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(bucket.total, format: CurrencyFormatter.currencyStyle())
                        .font(.headline.weight(.semibold))

                    Text(itemCountText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 0) {
                ForEach(Array(bucket.expenseItems.enumerated()), id: \.element.id) { index, item in
                    row(for: item)

                    if index < bucket.expenseItems.count - 1 {
                        Divider()
                            .padding(.leading, 24)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func row(for item: HomeSpendTrendsAggregator.ExpenseItem) -> some View {
        switch item {
        case .planned(let expense):
            SharedPlannedExpenseRow(expense: expense, showsCardName: showsCardName)
        case .variable(let expense):
            SharedVariableExpenseRow(expense: expense, showsCardName: showsCardName)
        }
    }

    private var itemCountText: String {
        if bucket.expenseItems.count == 1 {
            return String(
                localized: "homeWidget.spendTrends.bucketExpenseCountOne",
                defaultValue: "1 expense",
                comment: "Singular count of expense rows shown for a selected spend trends bucket."
            )
        }

        return String(
            format: String(
                localized: "homeWidget.spendTrends.bucketExpenseCountFormat",
                defaultValue: "%@ expenses",
                comment: "Count of expense rows shown for a selected spend trends bucket."
            ),
            locale: .current,
            bucket.expenseItems.count.formatted()
        )
    }

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }
}

// MARK: - Bucket hit target

private struct HeatMapBucketSelectionButton: View {
    let bucket: HomeSpendTrendsAggregator.Bucket
    let proxy: ChartProxy
    let plotFrame: CGRect
    let hitWidth: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    private let displayEpsilon: Double = 1.00

    var body: some View {
        guard bucket.total > displayEpsilon else {
            return AnyView(EmptyView())
        }

        guard let x = proxy.position(forX: bucket.label) else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Button(action: onTap) {
                Rectangle()
                    .fill(.clear)
                    .frame(width: hitWidth, height: plotFrame.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: x, y: plotFrame.height / 2)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSelected ? selectedText : "")
            .accessibilityHint(accessibilityHint)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        )
    }

    private var accessibilityLabel: String {
        String(
            format: String(
                localized: "homeWidget.spendTrends.bucketAccessibilityFormat",
                defaultValue: "%1$@, %2$@",
                comment: "Accessibility label for a selectable spend trends chart bucket."
            ),
            locale: .current,
            bucket.label,
            CurrencyFormatter.string(from: bucket.total)
        )
    }

    private var accessibilityHint: String {
        if isSelected {
            return String(
                localized: "homeWidget.spendTrends.bucketHideHint",
                defaultValue: "Double tap to hide expenses in this bucket.",
                comment: "Accessibility hint for hiding selected spend trends bucket expenses."
            )
        }

        return String(
            localized: "homeWidget.spendTrends.bucketShowHint",
            defaultValue: "Double tap to show expenses in this bucket.",
            comment: "Accessibility hint for showing spend trends bucket expenses."
        )
    }

    private var selectedText: String {
        String(
            localized: "common.selected",
            defaultValue: "Selected",
            comment: "Accessibility value for selected controls."
        )
    }
}

// MARK: - Overlay Bar (HeatMap-style)

private struct HeatMapBucketBar: View {

    let bucket: HomeSpendTrendsAggregator.Bucket
    let proxy: ChartProxy
    let plotFrame: CGRect
    let height: CGFloat
    let barWidth: CGFloat
    let isSelected: Bool
    let colorForSlice: (HomeSpendTrendsAggregator.Slice) -> Color
    private let displayEpsilon: Double = 1.00


    var body: some View {
        guard bucket.total > displayEpsilon else {
            return AnyView(EmptyView())
        }

        // X position for the bucket (centered on the category)
        guard let x = proxy.position(forX: bucket.label) else {
            return AnyView(EmptyView())
        }

        // Y position for the bucket total
        guard let yTop = proxy.position(forY: bucket.total) else {
            return AnyView(EmptyView())
        }

        let barHeight = max(2, plotFrame.height - yTop)

        let gradient = bucketMeltGradient(bucket: bucket)

        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let barSize = CGSize(width: barWidth, height: barHeight)

        return AnyView(
            ZStack {
                shape
                    .fill(gradient)

                if isSelected {
                    shape
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                }
            }
                .frame(width: barSize.width, height: barSize.height)
                .position(x: x, y: yTop + (barHeight / 2))
                .compositingGroup()
        )
    }

    /// - Full-opacity stops (no transparency)
    /// - Close paired stops around boundaries for soft transitions after blur
    private func bucketMeltGradient(bucket: HomeSpendTrendsAggregator.Bucket) -> LinearGradient {
        let slices = bucket.slices
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }

        let total = max(bucket.total, 0.000_1)

        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

        // This is the one knob that controls “blendiness”.
        // Smaller = crisper boundaries, bigger = more melt.
        let feather: Double = 0.045

        // Colors in order
        let colors = slices.map { colorForSlice($0) }
        guard let firstColor = colors.first else {
            return LinearGradient(colors: [.secondary], startPoint: .bottom, endPoint: .top)
        }

        // Boundary positions (end of each slice, except the last)
        var boundaries: [Double] = []
        var running: Double = 0
        for s in slices.dropLast() {
            running += s.amount
            boundaries.append(running / total)
        }

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(2 + boundaries.count * 2)

        // Start
        stops.append(.init(color: firstColor, location: 0))

        // For each boundary, create a “feather zone” where it transitions to the next color.
        for (i, pRaw) in boundaries.enumerated() {
            let p = clamp(pRaw)
            let left = clamp(p - feather)
            let right = clamp(p + feather)

            let a = colors[i]
            let b = colors[i + 1]

            stops.append(.init(color: a, location: left))
            stops.append(.init(color: b, location: right))
        }

        // End
        stops.append(.init(color: colors.last ?? firstColor, location: 1))

        // Ensure stops are ordered by location (monotonic non-decreasing)
        var ordered = stops.sorted { $0.location < $1.location }
        let epsilon: Double = 1e-6
        if !ordered.isEmpty {
            var last = ordered[0].location
            for i in 1..<ordered.count {
                var loc = ordered[i].location
                if loc < last { loc = last }
                if abs(loc - last) < epsilon { loc = last + epsilon }
                ordered[i].location = loc
                last = loc
            }
        }

        return LinearGradient(
            gradient: Gradient(stops: ordered),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
