#if os(macOS)
import AppKit
import Foundation
import UniformTypeIdentifiers

/// Zips the whole project store into a file the user picks. macOS only — iPad has no
/// `/usr/bin/zip` and no save panel.
enum BackupService {
    enum BackupError: LocalizedError {
        case zipFailed(status: Int32)

        var errorDescription: String? {
            switch self {
            case .zipFailed(let status):
                return String(localized: "Backup failed (zip exited with status \(status)).")
            }
        }
    }

    static func suggestedFileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "screenshot-backup-\(formatter.string(from: date)).zip"
    }

    /// Presents the save panel and returns the chosen destination, or nil if cancelled.
    @MainActor
    static func chooseDestination(now: Date = Date()) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName(for: now)
        panel.allowedContentTypes = [.zip]
        guard CrashReportingService.withAppHangTrackingPaused({ panel.runModal() }) == .OK else { return nil }
        return panel.url
    }

    /// Zips `sourceURL` into a temp file first, so a failure part-way through can't leave a
    /// truncated archive where the user's previous backup was.
    static func createBackup(
        of sourceURL: URL = PersistenceService.rootURL,
        to destURL: URL
    ) async throws {
        let tempZip = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", tempZip.path, "."]
        process.currentDirectoryURL = sourceURL

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempZip)
            throw BackupError.zipFailed(status: process.terminationStatus)
        }

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempZip, to: destURL)
    }
}
#endif
