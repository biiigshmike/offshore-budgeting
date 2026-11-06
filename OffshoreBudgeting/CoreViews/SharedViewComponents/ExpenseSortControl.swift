import SwiftUI

struct ExpenseSortControl<Mode: Hashable>: View {
    @Binding var selection: Mode
    let name: (ascending: Mode, descending: Mode)
    let amount: (ascending: Mode, descending: Mode)
    let date: (ascending: Mode, descending: Mode)

    var body: some View {
        HStack(spacing: 0) {
            segment(
                title: "Name",
                first: name.ascending, reverse: name.descending,
                firstLabel: "A–Z", reverseLabel: "Z–A"
            ) { isReversed in
                Image(systemName: isReversed ? "z.circle.fill" : "a.circle.fill")
                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
            }

            segment(
                title: "Amount",
                first: amount.ascending, reverse: amount.descending,
                firstLabel: "Lowest first", reverseLabel: "Highest first"
            ) { isReversed in
                if let symbol = currencySystemImage {
                    Image(systemName: symbol)
                } else {
                    Text(verbatim: CurrencyFormatter.currencySymbol)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Image(systemName: isReversed ? "arrow.down" : "arrow.up")
            }

            segment(
                title: "Date",
                first: date.descending, reverse: date.ascending,
                firstLabel: "Newest first", reverseLabel: "Oldest first"
            ) { isReversed in
                Image(systemName: "calendar")
                Image(systemName: isReversed ? "arrow.up" : "arrow.down")
            }
        }
        .background {
            // Let the system draw the segmented track and selection. The buttons
            // above it also handle activation of the already-selected segment.
            Picker("Sort", selection: .constant(displayedSelection)) {
                Text(verbatim: " ").tag(name.ascending)
                Text(verbatim: " ").tag(amount.ascending)
                Text(verbatim: " ").tag(date.descending)
            }
            .pickerStyle(.segmented)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }

    private var displayedSelection: Mode {
        if selection == name.ascending || selection == name.descending {
            return name.ascending
        }
        if selection == amount.ascending || selection == amount.descending {
            return amount.ascending
        }
        return date.descending
    }

    private var currencySystemImage: String? {
        // Language and currency are independent. Keep the formatted text for
        // currencies without an exact SF Symbol, such as MXN, SAR, and AED.
        switch CurrencyFormatter.currencyCode {
        case "AUD": "australiandollarsign"
        case "BRL": "brazilianrealsign"
        case "CNY": "chineseyuanrenminbisign"
        case "CRC": "coloncurrencysign"
        case "DKK": "danishkronesign"
        case "EUR": "eurosign"
        case "GBP": "sterlingsign"
        case "GEL": "larisign"
        case "GHS": "cedisign"
        case "ILS": "shekelsign"
        case "INR": "indianrupeesign"
        case "JPY": "yensign"
        case "KRW": "wonsign"
        case "KZT": "tengesign"
        case "LAK": "kipsign"
        case "MNT": "tugriksign"
        case "MYR": "malaysianringgitsign"
        case "NGN": "nairasign"
        case "NOK": "norwegiankronesign"
        case "PEN": "peruviansolessign"
        case "PHP": "pesosign"
        case "PLN": "polishzlotysign"
        case "PYG": "guaranisign"
        case "RUB": "rublesign"
        case "SEK": "swedishkronasign"
        case "SGD": "singaporedollarsign"
        case "THB": "bahtsign"
        case "TRY": "turkishlirasign"
        case "UAH": "hryvniasign"
        case "USD": "dollarsign"
        case "VND": "dongsign"
        default: nil
        }
    }

    private func segment<Label: View>(
        title: LocalizedStringKey,
        first: Mode,
        reverse: Mode,
        firstLabel: LocalizedStringKey,
        reverseLabel: LocalizedStringKey,
        @ViewBuilder label: (Bool) -> Label
    ) -> some View {
        let isReversed = selection == reverse
        let isSelected = selection == first || isReversed

        return Button {
            selection = selection == first ? reverse : first
        } label: {
            HStack(spacing: 4) {
                label(isReversed)
            }
            .font(.subheadline.weight(.semibold))
            .dynamicTypeSize(...DynamicTypeSize.large)
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isReversed ? reverseLabel : firstLabel))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? Text("Activate again to reverse the order.") : Text(""))
    }
}
