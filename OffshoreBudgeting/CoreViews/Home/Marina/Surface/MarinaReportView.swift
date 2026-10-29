import SwiftUI

/// Supporting report facts are available without expanding every breakdown into the chat.
struct MarinaReportView: View {
    let report: MarinaReport
    let purpose: MarinaDataRequest.Purpose?

    static func hasContent(_ report: MarinaReport) -> Bool {
        report.groups?.isEmpty == false || report.merchants?.isEmpty == false
            || report.frequentMerchants?.isEmpty == false || report.peak?.contributors?.isEmpty == false
    }

    var body: some View {
        if Self.hasContent(report) {
            DisclosureGroup("Breakdown details") {
                VStack(alignment: .leading, spacing: 18) {
                    if let contributors = report.peak?.contributors, !contributors.isEmpty {
                        MarinaGroupBreakdownView(title: "Peak period categories", groups: contributors, showsDetails: true)
                    }
                    if let groups = report.groups, !groups.isEmpty {
                        MarinaGroupBreakdownView(title: purpose == .spendingPatterns ? "Leading categories" : nil,
                                                 groups: groups, showsDetails: true)
                    }
                    if let merchants = report.merchants, !merchants.isEmpty {
                        MarinaGroupBreakdownView(title: "Merchant spending", groups: merchants, showsDetails: true)
                    }
                    if let merchants = report.frequentMerchants, !merchants.isEmpty {
                        MarinaGroupBreakdownView(title: "Frequent merchants", groups: merchants, showsDetails: true)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}
