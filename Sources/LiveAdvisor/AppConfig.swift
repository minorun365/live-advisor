import Foundation

/// Optional settings in ~/Library/Application Support/LiveAdvisor/config.json.
/// A file rather than environment variables, because an app started at login receives none.
struct AppConfig: Decodable {
    static let defaultCommand = "claude"

    var claudeCommand: String

    private enum CodingKeys: String, CodingKey { case claudeCommand }

    init(claudeCommand: String = AppConfig.defaultCommand) {
        self.claudeCommand = claudeCommand
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let command = try container.decodeIfPresent(String.self, forKey: .claudeCommand) ?? ""
        claudeCommand = command.isEmpty ? AppConfig.defaultCommand : command
    }

    static func load() -> AppConfig {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/LiveAdvisor/config.json")
        guard let data = try? Data(contentsOf: file) else { return AppConfig() }
        return parse(data)
    }

    /// A broken file falls back to the default, so a typo cannot silently stop every meeting.
    static func parse(_ data: Data) -> AppConfig {
        (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    /// Where the usual installers put claude. An app started at login does not get the shell's PATH.
    static func searchPath(home: String) -> [String] {
        [
            "\(home)/.local/bin",
            "\(home)/.claude/local",
            "\(home)/.npm-global/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    /// A command with a slash is a path. A bare name is looked up in the search path.
    static func resolve(
        command: String,
        searchPath: [String],
        home: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let expanded = command.hasPrefix("~/") ? home + command.dropFirst(1) : command
        if expanded.contains("/") {
            return isExecutable(expanded) ? expanded : nil
        }
        return searchPath.map { "\($0)/\(expanded)" }.first(where: isExecutable)
    }
}
