import Foundation

/// Both store APIs answer demo-mode calls from canned data after the same short pause.
protocol StoreDemoPacing {}

extension StoreDemoPacing {
    /// Short pause so the upload wizard's progress UI animates believably in demo mode.
    /// Kept small because real upload flows make ~6 sequential calls per (template × locale).
    func demoDelay() async {
        try? await Task.sleep(for: .milliseconds(80))
    }
}
