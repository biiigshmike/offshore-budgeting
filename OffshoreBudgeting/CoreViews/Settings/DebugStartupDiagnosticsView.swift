import SwiftUI
import SwiftData

#if DEBUG
struct DebugStartupDiagnosticsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var logURLs: [URL] = []
    @State private var selectedLogURL: URL?
    @State private var logText = ""
    @State private var validationResult = String(localized: "Not checked")
    @State private var persistenceError: String?

    private var modeDescription: String {
        if DebugScreenshotMode.isCompiledBuild {
            String(localized: "Screenshots (compiled)")
        } else {
            String(localized: "Normal Debug")
        }
    }

    private var storeDescription: String {
        modelContext.container.configurations
            .map { "\($0.name): \($0.url.path)" }
            .sorted()
            .joined(separator: "\n")
    }

    var body: some View {
        List {
            Section("Current Session") {
                LabeledContent("Mode", value: modeDescription)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("screenshotDiagnosticsMode")
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? String(localized: "Unknown"))
                LabeledContent("Process", value: String(ProcessInfo.processInfo.processIdentifier))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Displayed Store")
                        .font(.headline)
                    Text(storeDescription)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("screenshotDiagnosticsStore")
                LabeledContent("Screenshot Validation", value: validationResult)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("screenshotDiagnosticsValidation")
            }

            Section {
                if logURLs.isEmpty {
                    Text("No saved startup logs are available.")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Launch Log", selection: $selectedLogURL) {
                        ForEach(logURLs, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .tag(Optional(url))
                        }
                    }
                    .pickerStyle(.menu)

                    if let selectedLogURL {
                        ShareLink(item: selectedLogURL) {
                            Label("Share Startup Log", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("shareStartupDiagnostics")
                    }
                }

                if let persistenceError {
                    Text("Log storage error: \(persistenceError)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Saved Startup Logs")
            } footer: {
                Text("The five most recent launches are retained in this app’s sandbox. Each log is limited to 1 MB and remains available when Xcode’s console is disconnected.")
            }

            if !logText.isEmpty {
                Section("Log Contents") {
                    Text(logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Startup Diagnostics")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
        }
        .onAppear(perform: refresh)
        .onChange(of: selectedLogURL) { _, newValue in
            logText = newValue.map { StartupDiagnostics.contents(of: $0) } ?? ""
        }
    }

    private func refresh() {
        if DebugScreenshotMode.isEnabled {
            do {
                let workspaceID = try ScreenshotStartupCoordinator.validate(container: modelContext.container)
                validationResult = String(localized: "Valid (\(workspaceID.uuidString))")
            } catch {
                validationResult = String(localized: "Failed: \(error.localizedDescription)")
            }
        } else {
            validationResult = String(localized: "Not applicable")
        }

        StartupDiagnostics.log("debug inspector mode=\(modeDescription) screenshotValidation=\(validationResult)")
        StartupDiagnostics.logContainer(modelContext.container)
        logURLs = StartupDiagnostics.savedLogURLs()
        if selectedLogURL == nil || !logURLs.contains(where: { $0 == selectedLogURL }) {
            selectedLogURL = logURLs.first
        }
        logText = selectedLogURL.map { StartupDiagnostics.contents(of: $0) } ?? ""
        persistenceError = StartupDiagnostics.persistenceError
    }
}
#endif
