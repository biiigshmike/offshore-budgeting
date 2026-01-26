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
            topN: 4
        )

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerSummary(
                    totalSpent: result.totalSpent,
                    selectedCard: selectedCard
                )

                periodPicker

                cardCarousel

                chartCard(result: result)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("") // we render a custom title + subtitle in the navigation area
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Spend Trends")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(formattedDate(result.resolvedStart)) - \(formattedDate(result.resolvedEnd))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Header

    private func headerSummary(
        totalSpent: Double,
        selectedCard: Card?
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            Text("Total Spending")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(totalSpent, format: CurrencyFormatter.currencyStyle())
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    // MARK: - Picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(HomeSpendTrendsAggregator.Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Period")
    }

    // MARK: - Card carousel (replaces Menu)

    private var cardCarousel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(
                    selectedCardID
                        .flatMap { id in cards.first(where: { $0.id == id })?.name }
                    ?? "All Cards"
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
                        .accessibilityHint("Double tap to filter spend trends to this card. Tap again to clear and return to period P.")
                    }
                }
                .padding(6)
            }
            Text("Press a card to view spending by category for the selected card. Press it again to clear your selection.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func toggleCardSelection(_ card: Card) {
        if selectedCardID == card.id {
            // Tap again: clear selection and return to "P"
            selectedCardID = nil
            selectedPeriod = .period
        } else {
            selectedCardID = card.id
        }
    }

    // MARK: - Chart

    private func chartCard(result: HomeSpendTrendsAggregator.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Spending")
                .font(.headline.weight(.semibold))

            if result.buckets.allSatisfy({ $0.total <= 0 }) {
                Text("No spending data in this range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart {
                    // Invisible marks: these define x buckets + y scale for the chart.
                    ForEach(result.buckets) { bucket in
                        BarMark(
                            x: .value("Bucket", bucket.label),
                            y: .value("Amount", max(bucket.total, 0.000_001))
                        )
                        .foregroundStyle(.clear)
                        .opacity(0.001)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.22))
                        AxisTick().foregroundStyle(.secondary.opacity(0.28))
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                            .foregroundStyle(.primary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.18))
                        AxisTick().foregroundStyle(.secondary.opacity(0.26))
                        AxisValueLabel()
                            .foregroundStyle(.primary)
                    }
                }
                .frame(height: 240)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        if let plotAnchor = proxy.plotFrame {
                            let plotFrame = geo[plotAnchor]

                            ZStack(alignment: .topLeading) {
                                ForEach(result.buckets) { bucket in
                                    HeatMapBucketBar(
                                        bucket: bucket,
                                        proxy: proxy,
                                        plotFrame: plotFrame,
                                        height: plotFrame.height,
                                        barWidth: min(
                                            84,
                                            plotFrame.width / CGFloat(max(5, result.buckets.count)) * 0.78
                                        ),
                                        colorForSlice: color(for:)
                                    )
                                }
                            }
                            .frame(width: plotFrame.width, height: plotFrame.height)
                            .position(x: plotFrame.midX, y: plotFrame.midY)
                            .allowsHitTesting(false)
                        }
                    }
                }

                highestCallout(result: result)
                    .padding(.top, 6)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func highestCallout(result: HomeSpendTrendsAggregator.Result) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            if let highest = result.highestBucket {
                Text("Highest: \(highest.label) • \(highest.total, format: CurrencyFormatter.currencyStyle())")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let top = result.topCategoryInHighestBucket {
                Text("Top: \(top.name) • \(top.amount, format: CurrencyFormatter.currencyStyle())")
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
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
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
        CardThemeOption(rawValue: raw) ?? .graphite
    }

    private func effectOption(from raw: String) -> CardEffectOption {
        CardEffectOption(rawValue: raw) ?? .plastic
    }
}

// MARK: - Overlay Bar (HeatMap-style)

private struct HeatMapBucketBar: View {

    let bucket: HomeSpendTrendsAggregator.Bucket
    let proxy: ChartProxy
    let plotFrame: CGRect
    let height: CGFloat
    let barWidth: CGFloat
    let colorForSlice: (HomeSpendTrendsAggregator.Slice) -> Color

    var body: some View {
        guard bucket.total > 0 else { return AnyView(EmptyView()) }

        // X position for the bucket (centered on the category)
        guard let x = proxy.position(forX: bucket.label) else {
            return AnyView(EmptyView())
        }

        // Y position for the bucket total
        guard let yTop = proxy.position(forY: bucket.total) else {
            return AnyView(EmptyView())
        }

        let xInPlot = plotFrame.minX + x
        let topInPlot = plotFrame.minY + yTop
        let barHeight = max(2, plotFrame.maxY - topInPlot)

        let gradient = bucketMeltGradient(bucket: bucket)

        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let barSize = CGSize(width: barWidth, height: barHeight)

        return AnyView(
            shape
                .fill(gradient)
                .frame(width: barSize.width, height: barSize.height)
                .position(x: xInPlot, y: topInPlot + (barHeight / 2))
                .compositingGroup()
        )
    }

    /// Wallet-y “melt” gradient:
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

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
