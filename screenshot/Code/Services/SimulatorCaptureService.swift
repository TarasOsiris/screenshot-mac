import AppKit
import Foundation
import UniformTypeIdentifiers

#if DEBUG
/// Captures screenshots from the running iOS Simulator via a user-installed helper
/// script that wraps `xcrun simctl`. The host app is sandboxed and `xcrun` deliberately
/// refuses to run inside a sandboxed process — the only sanctioned escape hatch is
/// `NSUserUnixTask`, which can only execute scripts that the user has dropped into
/// `~/Library/Application Scripts/<bundle-id>/`. The first time the user invokes the
/// capture flow we present an `NSSavePanel` so they can install the helper themselves;
/// after that, the script is executed via `NSUserUnixTask` for every capture.
enum SimulatorCaptureService {
    enum Error: Swift.Error, LocalizedError {
        case helperNotInstalled
        case helperInstallCancelled
        case helperInstallFailed(String)
        case noBootedDevice
        case commandFailed(stderr: String)
        case decodeFailed

        var errorDescription: String? {
            switch self {
            case .helperNotInstalled:
                return String(localized: "iOS Simulator capture isn't set up yet.")
            case .helperInstallCancelled:
                return nil
            case .helperInstallFailed(let detail):
                return String(localized: "Couldn't install the script: \(detail)")
            case .noBootedDevice:
                return String(localized: "No iOS Simulator is running. Open a device in the Simulator app and try again.")
            case .commandFailed(let stderr):
                let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                if detail.isEmpty {
                    return String(localized: "iOS Simulator capture failed.")
                }
                return String(localized: "iOS Simulator capture failed: \(detail)")
            case .decodeFailed:
                return String(localized: "Could not read the captured screenshot.")
            }
        }
    }

    struct CaptureResult {
        let image: NSImage
        let deviceTypeIdentifier: String?
    }

    static let helperScriptName = "capture-simulator.sh"
    static let helperScriptVersion = 4

    private static var helperScriptVersionMarker: String {
        "# Screenshot Bro simulator helper, version \(helperScriptVersion)"
    }

    /// `~/Library/Application Scripts/<bundle-id>/`. Created on demand — sandboxed apps
    /// are allowed to create their own application scripts directory but cannot write
    /// arbitrary files into it; only the user can do that via an NSSavePanel save.
    static var applicationScriptsURL: URL {
        if let url = try? FileManager.default.url(
            for: .applicationScriptsDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return url
        }
        let bundleId = Bundle.main.bundleIdentifier ?? "screenshot"
        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Scripts")
            .appendingPathComponent(bundleId)
    }

    static var helperScriptURL: URL {
        applicationScriptsURL.appendingPathComponent(helperScriptName)
    }

    /// True only when the script is present, executable, and matches the current
    /// `helperScriptVersion`. An outdated helper trips the install prompt again so
    /// users picking up a new build of the app get an updated script.
    static var isHelperInstalled: Bool {
        guard FileManager.default.isExecutableFile(atPath: helperScriptURL.path),
              let installed = try? String(contentsOf: helperScriptURL, encoding: .utf8) else {
            return false
        }
        return installed.contains(helperScriptVersionMarker)
    }

    static let helperScriptContent = """
    #!/bin/bash
    \(helperScriptVersionMarker)
    # Wraps xcrun simctl so the sandboxed app can talk to the iOS Simulator via
    # NSUserUnixTask.
    set -eu
    case "${1:-}" in
      capture)
        output="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/simbro.XXXXXX.png")"
        trap 'rm -f "$output"' EXIT
        /usr/bin/xcrun simctl io booted screenshot --type=png "$output"
        /bin/cat "$output"
        ;;
      list)
        exec /usr/bin/xcrun simctl list devices booted -j
        ;;
      *)
        echo "Usage: $0 {capture | list}" >&2
        exit 64
        ;;
    esac
    """

    /// Shows an `NSSavePanel` pointed at the application scripts folder, writes the
    /// helper bytes once the user picks a location, then chmods the result executable.
    /// Rejects saves with a different filename or outside the canonical folder —
    /// `NSUserUnixTask` will only run scripts that live in that exact directory.
    @MainActor
    static func presentInstallPanel() -> Result<URL, Error> {
        let panel = NSSavePanel()
        panel.title = String(localized: "Save iOS Simulator Capture Script")
        panel.message = String(localized: "Save the script in this folder. Screenshot Bro will use it to ask the iOS Simulator for screenshots.")
        panel.nameFieldStringValue = helperScriptName
        panel.directoryURL = applicationScriptsURL
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let scriptType = UTType(filenameExtension: "sh") {
            panel.allowedContentTypes = [scriptType]
        }

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else {
            return .failure(.helperInstallCancelled)
        }

        if canonicalPath(url.deletingLastPathComponent()) != canonicalPath(applicationScriptsURL)
            || url.lastPathComponent != helperScriptName {
            return .failure(.helperInstallFailed(String(
                localized: "Keep the script's name (\(helperScriptName)) and save it inside the Application Scripts folder."
            )))
        }

        do {
            try Data(helperScriptContent.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            return .success(url)
        } catch {
            return .failure(.helperInstallFailed(error.localizedDescription))
        }
    }

    static func captureBooted() async throws -> CaptureResult {
        async let identifierTask: String? = (try? await bootedDeviceTypeIdentifier()) ?? nil

        let imageData: Data
        do {
            imageData = try await runHelper(arguments: ["capture"])
        } catch let error as Error {
            if case .commandFailed(let stderr) = error,
               stderr.range(of: "no.+booted", options: [.regularExpression, .caseInsensitive]) != nil {
                throw Error.noBootedDevice
            }
            throw error
        }

        guard let image = NSImage(data: imageData) else { throw Error.decodeFailed }
        return CaptureResult(image: image, deviceTypeIdentifier: await identifierTask)
    }

    /// Maps a simctl device-type identifier (e.g. `com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro`)
    /// to a `DeviceFrameCatalog` group id. Returns `nil` if the device isn't represented in the catalog.
    static func deviceFrameGroupId(for deviceTypeIdentifier: String) -> String? {
        let suffix = deviceTypeIdentifier
            .components(separatedBy: ".")
            .last?
            .lowercased() ?? deviceTypeIdentifier.lowercased()

        let mapping: [(needle: String, groupId: String)] = [
            ("iphone-17-pro-max", "iphone17promax"),
            ("iphone-17-pro", "iphone17pro"),
            ("iphone-17-air", "iphoneair"),
            ("iphone-air", "iphoneair"),
            ("iphone-17", "iphone17"),
            ("ipad-pro-13", "ipadpro13"),
            ("ipad-pro-12-9", "ipadpro13"),
            ("ipad-pro-11", "ipadpro11"),
        ]
        return mapping.first(where: { suffix.contains($0.needle) })?.groupId
    }

    // MARK: - Private

    private struct SimctlListResponse: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    private struct SimctlDevice: Decodable {
        let state: String
        let deviceTypeIdentifier: String?
    }

    private static func bootedDeviceTypeIdentifier() async throws -> String? {
        let data = try await runHelper(arguments: ["list"])
        let response = try JSONDecoder().decode(SimctlListResponse.self, from: data)
        for list in response.devices.values {
            if let device = list.first(where: { $0.state == "Booted" }),
               let identifier = device.deviceTypeIdentifier {
                return identifier
            }
        }
        return nil
    }

    private static func runHelper(arguments: [String]) async throws -> Data {
        let task: NSUserUnixTask
        do {
            task = try NSUserUnixTask(url: helperScriptURL)
        } catch {
            throw Error.helperNotInstalled
        }

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout.fileHandleForWriting
        task.standardError = stderr.fileHandleForWriting

        // Drain pipes concurrently with the process. PNG screenshots blow past the
        // ~64 KB pipe buffer, so without a concurrent reader the child blocks on
        // write while we wait for `execute` to return.
        let outTask = Task.detached { (try? stdout.fileHandleForReading.readToEnd()) ?? Data() }
        let errTask = Task.detached { (try? stderr.fileHandleForReading.readToEnd()) ?? Data() }

        let executionError: Swift.Error?
        do {
            try await task.execute(withArguments: arguments)
            executionError = nil
        } catch {
            executionError = error
        }

        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()

        let outData = await outTask.value
        let errData = await errTask.value

        if let executionError {
            let stderrString = String(data: errData, encoding: .utf8) ?? ""
            let detail = stderrString.isEmpty ? executionError.localizedDescription : stderrString
            throw Error.commandFailed(stderr: detail)
        }
        return outData
    }

    private static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
#endif
