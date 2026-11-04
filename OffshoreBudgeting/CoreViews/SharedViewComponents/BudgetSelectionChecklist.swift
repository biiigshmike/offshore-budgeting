#if targetEnvironment(macCatalyst)
import SwiftUI

/// Mac menus dismiss after selection. Keep budget choices inline until the
/// user collapses the row, without changing the budget's draft bindings.
struct BudgetSelectionChecklist<Item: Identifiable, ItemLabel: View>: View {
    @Environment(\.appearanceTheme) private var theme

    let title: LocalizedStringKey
    let items: [Item]
    let selectedCount: Int
    let accessibilityID: String
    let selection: (Item) -> Binding<Bool>
    let onToggleAll: () -> Void
    @ViewBuilder let itemLabel: (Item) -> ItemLabel

    @State private var isExpanded = false

    var body: some View {
        Button {
            withAnimation {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Group {
                    if selectedCount == 0 {
                        Text("None selected")
                    } else {
                        Text("\(selectedCount) selected")
                    }
                }
                .foregroundStyle(.secondary)
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(items.isEmpty)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

        if isExpanded {
            Button(selectedCount == items.count ? "Clear All" : "Select All", action: onToggleAll)
                .buttonStyle(.borderless)
                .font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("\(accessibilityID).all")

            ForEach(items) { item in
                let binding = selection(item)
                Button {
                    binding.wrappedValue.toggle()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: binding.wrappedValue ? "checkmark.square.fill" : "square")
                            .foregroundStyle(binding.wrappedValue ? theme.accent : Color.secondary)
                            .accessibilityHidden(true)
                        itemLabel(item)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(binding.wrappedValue ? .isSelected : [])
            }
        }
    }
}
#endif
