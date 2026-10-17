import SwiftUI

// MARK: - X Axis Labels (manual)

struct SpendTrendsXAxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

