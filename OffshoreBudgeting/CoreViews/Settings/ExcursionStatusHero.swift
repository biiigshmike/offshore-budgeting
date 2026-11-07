import SwiftUI

#if !targetEnvironment(macCatalyst)
struct ExcursionStatusHero: View {
    let status: ShoppingModeStatus
    let locationCapability: ExcursionLocationCapability

    private var statusTitle: LocalizedStringKey {
        if !status.isActive { return "Inactive" }
        return locationCapability.canMonitor ? "Active" : "Paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "sailboat.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(statusTitle)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("excursionStatus")

            if status.isActive, let expiresAt = status.expiresAt {
                let startsAt = min(status.startedAt ?? .now, expiresAt)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Time remaining")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(timerInterval: startsAt...expiresAt, countsDown: true)
                        .font(.largeTitle.monospacedDigit().bold())
                }
                .accessibilityElement(children: .combine)

                LabeledContent("Ends") {
                    Text(expiresAt, format: .dateTime.hour().minute())
                }
                .font(.subheadline)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.accentColor.opacity(0.14).gradient,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}
#endif
