import SwiftUI

// MARK: - QuickActionsInstallView

struct QuickActionsInstallView: View {
    
    let isOnboarding: Bool
    
    @Environment(\.openURL) private var openURL
    @State private var openedItemIDs: Set<String> = []
    
    init(isOnboarding: Bool = false) {
        self.isOnboarding = isOnboarding
    }
    
    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        let base = VStack(alignment: .leading, spacing: 14) {
            if isOnboarding {
                header
            }
            
            List {
                shortcutsSection
                automationTemplatesSection
                helpSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 300)
            
            if isOnboarding {
                Text("This step is optional. You can install these later from Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        
        if isOnboarding {
            base
        } else {
            base
                .navigationTitle("Quick Actions")
        }
    }
    
    // MARK: - Sections
    
    private var shortcutsSection: some View {
        Section("Install Shortcuts") {
            ForEach(ShortcutLinkCatalog.shortcuts) { item in
                linkButton(for: item)
            }
        }
    }
    
    private var automationTemplatesSection: some View {
        Section("Install Automation Templates") {
            ForEach(ShortcutLinkCatalog.automationTemplates) { item in
                linkButton(for: item)
            }
        }
    }
    
    private var helpSection: some View {
        Section("How Automation Setup Works") {
            Text("After importing each template, open Shortcuts > Automation and confirm the trigger and run settings on this device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
            Text("Personal automations are device-specific, so setup is needed on each device you use.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Components
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick Actions")
                .font(.title2.weight(.bold))
            Text("Install your Offshore shortcuts and automation templates for faster access from Control Center and Lock Screen.")
                .foregroundStyle(.secondary)
        }
    }
    
    private func linkButton(for item: ShortcutLinkItem) -> some View {
        Button {
            openURL(item.url)
            openedItemIDs.insert(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.systemImageName)
                    .foregroundStyle(.tint)
                    .font(.system(size: 18))
                    .frame(width: 24, alignment: .center)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .foregroundStyle(.primary)
                    Text(item.subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(.secondary)
                
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }
}

#Preview("Quick Actions") {
    NavigationStack {
        QuickActionsInstallView()
    }
}
