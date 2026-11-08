import SwiftUI

struct PresetDetailNavigationHeader: ViewModifier {
    let title: String
    let subtitle: String
    let startDate: Date
    let endDate: Date

    private func intervalText(style: DateIntervalFormatter.Style) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = style
        formatter.timeStyle = .none
        return formatter.string(from: startDate, to: endDate)
    }

    private var compactSubtitle: some View {
        ViewThatFits(in: .horizontal) {
            // Historical windows often cross years. Prefer numeric dates there,
            // including in older toolbars that measure their title at ideal width.
            Text(intervalText(style: Calendar.current.isDate(startDate, equalTo: endDate, toGranularity: .year)
                              ? .medium : .short)).fixedSize()
            Text(intervalText(style: .short)).fixedSize()
            Text(intervalText(style: .short))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(subtitle)
    }

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        // The native window owns both lines on Catalyst. A navigation title
        // here would replace that heading and hide its subtitle.
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .background {
                PresetMacWindowSubtitle(title: title, subtitle: subtitle)
                    .frame(width: 0, height: 0)
            }
        #else
        if #available(iOS 26.0, *) {
            content
                .navigationTitle(title)
                .navigationSubtitle(intervalText(style: .medium))
                .navigationBarTitleDisplayMode(.large)
                .toolbarRole(.navigationStack)
                .toolbar {
                    ToolbarItem(placement: .largeSubtitle) {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ToolbarItem(placement: .subtitle) { compactSubtitle }
                }
        } else {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 2) {
                            Text(title).font(.headline)
                            compactSubtitle
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
        }
        #endif
    }
}
