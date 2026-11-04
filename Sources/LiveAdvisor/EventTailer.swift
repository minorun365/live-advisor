import Foundation

/// Reads events.jsonl from where it last stopped.
///
/// The file reaches about 190MB in a 50-minute meeting because every partial result is logged,
/// so only complete lines carrying a final result or a stop event are decoded.
final class EventTailer {
    struct Batch {
        var lines: [TranscriptLine] = []
        var stopped = false
        var grew = false
    }

    private static let finalMarker = Data("\"final\":\"true\"".utf8)
    private static let stopMarker = Data("\"session_stopped\"".utf8)
    private static let newline: UInt8 = 0x0A

    private let url: URL
    private var offset: UInt64 = 0
    private var remainder = Data()
    private let formatter = ISO8601DateFormatter()

    init(url: URL) {
        self.url = url
    }

    func poll() -> Batch {
        var batch = Batch()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return batch }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(), !chunk.isEmpty else { return batch }
        offset += UInt64(chunk.count)
        batch.grew = true

        var data = remainder
        data.append(chunk)
        guard let lastNewline = data.lastIndex(of: Self.newline) else {
            remainder = data
            return batch
        }
        remainder = Data(data[data.index(after: lastNewline)...])

        var start = data.startIndex
        while start <= lastNewline {
            let end = data[start...lastNewline].firstIndex(of: Self.newline) ?? lastNewline
            let line = data[start..<end]
            start = end + 1
            if line.range(of: Self.stopMarker) != nil {
                batch.stopped = true
            } else if line.range(of: Self.finalMarker) != nil, let parsed = parse(Data(line)) {
                batch.lines.append(parsed)
            }
        }
        return batch
    }

    private func parse(_ line: Data) -> TranscriptLine? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "recognition",
              let payload = object["payload"] as? [String: String],
              payload["final"] == "true",
              let raw = payload["text"] else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let at = (object["timestamp"] as? String).flatMap { formatter.date(from: $0) } ?? Date()
        let speaker = payload["speaker"].flatMap(TranscriptLine.Speaker.init(rawValue:)) ?? .unknown
        return TranscriptLine(at: at, speaker: speaker, text: text)
    }
}
