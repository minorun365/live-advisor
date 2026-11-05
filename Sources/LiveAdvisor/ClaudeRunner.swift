import Foundation

struct ClaudeCall {
    enum Job: String { case judge, research, direction, tighten, history }

    let job: Job
    let model: String
    let effort: String
    let system: String
    let schema: String
    var tools: [String] = []
    var budgetUSD: Double?
    /// Folders the call may read. The first is also where it runs. Empty keeps the empty workspace.
    var folders: [String] = []
    let timeout: TimeInterval
    let prompt: String
}

struct ClaudeResult {
    enum Failure: Equatable { case notFound, timeout, notLoggedIn, limitReached, budget, other }

    var structured: Data?
    var failure: Failure?
}

/// Runs Claude Code headless.
///
/// Settings, skills, MCP and tools are all left out, so a call carries only its own prompt.
/// Only the background stage gets folders, and only read-only tools to look at them.
/// Each call starts fresh so the conversation can never grow.
enum ClaudeRunner {
    static let command = AppConfig.load().claudeCommand

    static func arguments(for call: ClaudeCall) -> [String] {
        var arguments = [
            "-p",
            "--model", call.model,
            "--effort", call.effort,
            "--system-prompt", call.system,
            "--json-schema", call.schema,
            "--tools", call.tools.joined(separator: ","),
            "--setting-sources", "",
            "--strict-mcp-config",
            "--disable-slash-commands",
            "--no-session-persistence",
            "--output-format", "json",
        ]
        if !call.tools.isEmpty {
            arguments += ["--allowedTools", call.tools.joined(separator: ",")]
        }
        for folder in call.folders.dropFirst() {
            arguments += ["--add-dir", folder]
        }
        if let budget = call.budgetUSD {
            arguments += ["--max-budget-usd", String(budget)]
        }
        return arguments
    }

    static func run(_ call: ClaudeCall) async -> ClaudeResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(call))
            }
        }
    }

    private static func runBlocking(_ call: ClaudeCall) -> ClaudeResult {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let searchPath = AppConfig.searchPath(home: home.path)
        guard let executable = AppConfig.resolve(command: command, searchPath: searchPath, home: home.path) else {
            UsageLog.write(call: call, seconds: 0, json: nil, status: "not_found")
            return ClaudeResult(structured: nil, failure: .notFound)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments(for: call)
        // Variables inherited from another Claude Code can point at a different login, so pass only these.
        process.environment = [
            "HOME": home.path,
            "USER": NSUserName(),
            "LANG": "ja_JP.UTF-8",
            "PATH": searchPath.joined(separator: ":"),
        ]
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("live-advisor-empty", isDirectory: true)
        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        process.currentDirectoryURL = call.folders.first.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? workspace

        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let started = Date()
        do {
            try process.run()
        } catch {
            UsageLog.write(call: call, seconds: 0, json: nil, status: "launch_failed")
            return ClaudeResult(structured: nil, failure: .other)
        }
        input.fileHandleForWriting.write(Data(call.prompt.utf8))
        try? input.fileHandleForWriting.close()

        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + call.timeout, execute: deadline)

        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = output.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errors.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        process.waitUntilExit()
        group.wait()
        deadline.cancel()

        let seconds = Date().timeIntervalSince(started)
        let json = (try? JSONSerialization.jsonObject(with: outData)) as? [String: Any]
        let timedOut = process.terminationReason == .uncaughtSignal || seconds >= call.timeout

        var result = ClaudeResult()
        if let structured = json?["structured_output"], !(structured is NSNull),
           let data = try? JSONSerialization.data(withJSONObject: structured) {
            result.structured = data
        }
        if result.structured == nil {
            let combined = (String(data: outData, encoding: .utf8) ?? "") + (String(data: errData, encoding: .utf8) ?? "")
            if timedOut {
                result.failure = .timeout
            } else if combined.localizedCaseInsensitiveContains("not logged in") || combined.contains("/login") {
                result.failure = .notLoggedIn
            } else if combined.localizedCaseInsensitiveContains("budget") {
                result.failure = .budget
            } else if combined.localizedCaseInsensitiveContains("limit") {
                result.failure = .limitReached
            } else {
                result.failure = .other
            }
        }
        UsageLog.write(call: call, seconds: seconds, json: json, status: result.failure.map { "\($0)" } ?? "ok")
        return result
    }
}

/// Numbers only. Meeting text stays in the meeting folder.
enum UsageLog {
    static func write(call: ClaudeCall, seconds: TimeInterval, json: [String: Any]?, status: String) {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/LiveAdvisor", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let usage = json?["usage"] as? [String: Any]
        let record: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "job": call.job.rawValue,
            "model": call.model,
            "seconds": (seconds * 10).rounded() / 10,
            "cost_usd": json?["total_cost_usd"] ?? NSNull(),
            "input_tokens": usage?["input_tokens"] ?? NSNull(),
            "cache_read_tokens": usage?["cache_read_input_tokens"] ?? NSNull(),
            "cache_write_tokens": usage?["cache_creation_input_tokens"] ?? NSNull(),
            "output_tokens": usage?["output_tokens"] ?? NSNull(),
            "status": status,
        ]
        guard var line = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        let file = directory.appendingPathComponent("live-advisor.log")
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            try? handle.close()
        } else {
            try? line.write(to: file)
        }
    }
}
