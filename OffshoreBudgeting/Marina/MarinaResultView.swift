import SwiftUI
import Charts

@available(iOS 26.0, macOS 26.0, *)
struct MarinaResultView: View {
    let result: MarinaResult
    let openRecord: (MarinaRecord) -> Void
    @State private var page = 0
    private let pageSize = 20

    private var visiblePoints: [MarinaChartPoint] { Array(result.points.prefix(60)) }
    private var pageCount: Int { max(1, (result.records.count + pageSize - 1) / pageSize) }
    private var visibleRecords: [MarinaRecord] { Array(result.records.dropFirst(page * pageSize).prefix(pageSize)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.title).font(.headline)
            Text(result.detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
            if let total = result.total {
                Text(formattedValue(total)).font(.title2).bold()
            }
            Text("\(result.count) records • Snapshot \(result.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if !result.points.isEmpty {
                chart
                if result.points.count > visiblePoints.count {
                    Text("Chart shows the first \(visiblePoints.count) of \(result.points.count) groups. The full record list remains available below.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(visibleRecords) { record in
                Button {
                    openRecord(record)
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.title).foregroundStyle(.primary)
                            Text(record.date, format: .dateTime.month().day().year()).font(.caption).foregroundStyle(.secondary)
                            Text(record.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if record.domain != .budgets {
                            Text(record.amount, format: CurrencyFormatter.currencyStyle()).foregroundStyle(.primary)
                        }
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the current record")
                Divider()
            }
            if pageCount > 1 {
                HStack {
                    Button("Previous", systemImage: "chevron.left") { page -= 1 }.disabled(page == 0)
                    Spacer()
                    Text("Page \(page + 1) of \(pageCount)").font(.caption)
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { page += 1 }.disabled(page + 1 >= pageCount)
                }
            }
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .onChange(of: result.id) { page = 0 }
    }

    private func formattedValue(_ value: Double) -> String {
        result.valueKind == "count" ? value.formatted(.number.precision(.fractionLength(0))) : CurrencyFormatter.string(from: value)
    }

    private var chart: some View {
        Chart(visiblePoints) { point in
            if let date = point.date, result.chartKind != "comparison" {
                LineMark(x: .value("Date", date), y: .value("Amount", point.value))
                PointMark(x: .value("Date", date), y: .value("Amount", point.value))
                    .accessibilityLabel(point.label)
                    .accessibilityValue(formattedValue(point.value))
            } else {
                BarMark(x: .value("Amount", point.value), y: .value("Category", point.label))
                    .accessibilityLabel(point.label)
                    .accessibilityValue(formattedValue(point.value))
            }
        }
        .frame(height: max(180, min(480, CGFloat(visiblePoints.count) * 30)))
        .accessibilityLabel(result.title)
    }
}
