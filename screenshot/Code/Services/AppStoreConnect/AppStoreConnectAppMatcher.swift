import Foundation

/// Guesses which App Store Connect app a project is for, so the wizard can preselect it.
///
/// Edit distance over alphanumerics-only names, with a bonus when one name contains the other —
/// "Screenshot Bro" should match "Screenshot Bro: App Store Kit" even though the raw distance is
/// large. Below the threshold nothing is preselected: a wrong guess is worse than none, because
/// the next screen uploads to whatever is selected.
enum AppStoreConnectAppMatcher {
    static let matchThreshold: Double = 0.6
    static let containmentBonus: Double = 0.2

    static func closestApp(projectName: String, in apps: [ASCApp]) -> ASCApp? {
        let targetString = normalizedName(projectName)
        let target = Array(targetString)
        guard !target.isEmpty else { return nil }

        var bestApp: ASCApp?
        var bestScore = -Double.infinity
        for app in apps {
            let candidateString = normalizedName(app.attributes.name)
            let candidate = Array(candidateString)
            guard !candidate.isEmpty else { continue }
            let distance = levenshtein(candidate, target)
            let similarity = 1.0 - Double(distance) / Double(max(candidate.count, target.count))
            let isContained = candidateString.contains(targetString) || targetString.contains(candidateString)
            let score = similarity + (isContained ? containmentBonus : 0)
            if score > bestScore {
                bestScore = score
                bestApp = app
            }
        }
        return bestScore >= matchThreshold ? bestApp : nil
    }

    static func normalizedName(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        var curr = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            curr[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[b.count]
    }
}
