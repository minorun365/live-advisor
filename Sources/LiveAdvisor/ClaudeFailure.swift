import Foundation

/// Why a headless Claude Code call returned no answer.
enum ClaudeFailure: Equatable {
    case notFound, timeout, notLoggedIn, limitReached, budget, unavailable, other

    /// Claude Code's JSON always carries counters such as `"refused":{"budget":0}`, so searching the
    /// whole output for a word mislabels every error. Only the fields that describe the error are read.
    static func classify(json: [String: Any]?, stdout: String, stderr: String, timedOut: Bool) -> ClaudeFailure {
        if timedOut { return .timeout }
        let subtype = json?["subtype"] as? String ?? ""
        if subtype == "error_max_budget_usd" { return .budget }
        let status = (json?["api_error_status"] as? NSNumber)?.intValue
        // Without JSON the CLI failed before the call, and its own words are the only clue.
        let message = ((json?["result"] as? String) ?? (json == nil ? stdout : "")) + "\n" + stderr
        let lowered = message.lowercased()
        if status == 401 || lowered.contains("not logged in") || lowered.contains("/login") { return .notLoggedIn }
        if status == 429 || lowered.contains("usage limit") || lowered.contains("hit your limit") || lowered.contains("rate limit") {
            return .limitReached
        }
        if let status, status >= 500 { return .unavailable }
        if lowered.contains("overloaded") || lowered.contains("connection") || lowered.contains("network") { return .unavailable }
        return .other
    }

    /// Worth one quick retry: the service hiccuped, not the request.
    var isTransient: Bool { self == .unavailable }
}
