import AppIntents
import Foundation
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import AppKit
#endif

// MARK: - ImportScreenshotIntent

struct ImportScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Import Screenshot"
    static var description = IntentDescription("Parse a screenshot image and return an import preview summary.")
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Screenshot",
        supportedContentTypes: [.image],
        requestValueDialog: IntentDialog("Select or pass in an image to import.")
    )
    var screenshot: IntentFile?

    @Parameter(title: "Open in Offshore")
    var openInOffshore: Bool

    init() {
        self.screenshot = nil
        self.openInOffshore = false
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> & OpensIntent {
        let sourceURL: URL
        do {
            sourceURL = try await MainActor.run {
                try resolveScreenshotURL()
            }
        } catch ShortcutImportPreviewError.imageFileUnavailable {
            throw $screenshot.needsValueError(
                "No image was provided. Pass an image into Screenshot (for example from Select Photos or Get Latest Screenshot)."
            )
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not read the image."
            return .result(
                value: message,
                dialog: IntentDialog(stringLiteral: message)
            )
        }
        let shouldRemoveTempFile = sourceURL.lastPathComponent.contains("offshore-shortcuts-screenshot-")
        defer {
            if shouldRemoveTempFile {
                try? FileManager.default.removeItem(at: sourceURL)
            }
        }

        let preview: ShortcutImportPreview
        do {
            preview = try await MainActor.run {
                try ShortcutImportPreviewService.shared.previewFromImage(url: sourceURL)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Could not parse the image into transactions."
            return .result(
                value: message,
                dialog: IntentDialog(stringLiteral: message)
            )
        }

        if openInOffshore {
            await MainActor.run {
                UserDefaults.standard.set(
                    AppSection.income.rawValue,
                    forKey: AppShortcutNavigationStore.pendingSectionKey
                )
                UserDefaults.standard.set(
                    AppShortcutNavigationStore.PendingAction.openIncomeImportReview.rawValue,
                    forKey: AppShortcutNavigationStore.pendingActionKey
                )
            }

            return .result(
                value: preview.summaryText,
                opensIntent: OpenOffshoreForImportIntent(),
                dialog: IntentDialog(stringLiteral: preview.summaryText)
            )
        }

        return .result(
            value: preview.summaryText,
            dialog: IntentDialog(stringLiteral: preview.summaryText)
        )
    }

    private func resolveScreenshotURL() throws -> URL {
        if let screenshot {
            let data = screenshot.data
            if !data.isEmpty {
                return try writeTempImageData(data, fileExtension: "jpg")
            }

            if let fileURL = screenshot.fileURL {
                if let copiedData = try? Data(contentsOf: fileURL), !copiedData.isEmpty {
                    let ext = fileURL.pathExtension.isEmpty ? "jpg" : fileURL.pathExtension
                    return try writeTempImageData(copiedData, fileExtension: ext)
                }
                return fileURL
            }
        }

        #if canImport(UIKit)
        if let image = UIPasteboard.general.image,
           let data = image.jpegData(compressionQuality: 0.95),
           !data.isEmpty {
            return try writeTempImageData(data, fileExtension: "jpg")
        }
        #endif

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        if let data = NSPasteboard.general.data(forType: .tiff),
           !data.isEmpty {
            return try writeTempImageData(data, fileExtension: "tiff")
        }
        #endif

        throw ShortcutImportPreviewError.imageFileUnavailable
    }

    private func writeTempImageData(_ data: Data, fileExtension: String) throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("offshore-shortcuts-screenshot-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}
