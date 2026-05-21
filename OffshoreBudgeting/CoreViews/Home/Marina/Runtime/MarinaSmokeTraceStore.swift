import Foundation

enum MarinaSmokeTraceStore {
    static func exportIfEnabled(_ trace: MarinaExecutionTrace) {
        #if DEBUG
        let settings = MarinaRuntimeSettings.resolve()
        guard settings.realDeviceSmoke.isEnabled else { return }

        let url = exportURL(settings: settings)
        let snapshot = MarinaExecutionTraceSnapshot(trace)
        do {
            let data = try JSONEncoder().encode(snapshot)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n".utf8))
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            MarinaDebugLogger.log("[MarinaSmokeTraceStore] failed path='\(url.path)' error='\(error)'")
        }
        #endif
    }

    static var currentExportURL: URL? {
        #if DEBUG
        let settings = MarinaRuntimeSettings.resolve()
        guard settings.realDeviceSmoke.isEnabled else { return nil }
        return exportURL(settings: settings)
        #else
        return nil
        #endif
    }

    private static func exportURL(settings: MarinaRuntimeSettings) -> URL {
        if let outputPath = settings.realDeviceSmokeOutputPath {
            return URL(fileURLWithPath: outputPath)
        }
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return directory.appendingPathComponent("MarinaRealDeviceSmokeTrace.jsonl")
    }
}
