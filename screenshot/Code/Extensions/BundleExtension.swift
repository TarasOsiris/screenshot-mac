import Foundation

extension Bundle {
    nonisolated var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    nonisolated var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? ""
    }
}
