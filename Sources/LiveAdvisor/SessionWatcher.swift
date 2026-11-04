import Foundation

/// Waits for a recording to appear, then follows it. Between recordings only a directory watch exists.
final class SessionWatcher {
    var onStart: ((URL, Date) -> Void)?
    var onLines: (([TranscriptLine]) -> Void)?
    var onEnd: (() -> Void)?

    static let recordingIdleLimit: TimeInterval = 5 * 60
    private static let pollInterval: TimeInterval = 5

    private let root: URL
    private let queue = DispatchQueue(label: "com.minorun365.LiveAdvisor.watcher")
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var tailer: EventTailer?
    private var current: URL?
    private var lastGrowth = Date()
    private var finished = Set<String>()

    init(root: URL) {
        self.root = root
    }

    func start() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let descriptor = open(root.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in self?.lookForRecording() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        directorySource = source
        queue.async { self.lookForRecording() }
    }

    private func lookForRecording() {
        guard current == nil,
              let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { return }
        let candidates = names.filter { $0.first?.isNumber == true && !finished.contains($0) }.sorted(by: >)
        guard let newest = candidates.first else { return }
        let folder = root.appendingPathComponent(newest, isDirectory: true)
        let events = folder.appendingPathComponent("events.jsonl")

        // A new folder appears a moment before its events file does. Look again shortly.
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: events.path),
              let modified = attributes[.modificationDate] as? Date else {
            queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.lookForRecording() }
            return
        }
        guard Date().timeIntervalSince(modified) < Self.recordingIdleLimit else { return }

        let tailer = EventTailer(url: events)
        let backlog = tailer.poll()
        if backlog.stopped {
            finished.insert(newest)
            return
        }
        self.tailer = tailer
        current = folder
        lastGrowth = Date()
        onStart?(folder, Self.startDate(fromFolderName: newest) ?? Date())
        if !backlog.lines.isEmpty { onLines?(backlog.lines) }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.pollRecording() }
        timer.resume()
        pollTimer = timer
    }

    private func pollRecording() {
        guard let tailer, let current else { return }
        let batch = tailer.poll()
        if batch.grew { lastGrowth = Date() }
        if !batch.lines.isEmpty { onLines?(batch.lines) }
        guard batch.stopped || Date().timeIntervalSince(lastGrowth) > Self.recordingIdleLimit else { return }
        pollTimer?.cancel()
        pollTimer = nil
        self.tailer = nil
        self.current = nil
        finished.insert(current.lastPathComponent)
        onEnd?()
        lookForRecording()
    }

    static func startDate(fromFolderName name: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.date(from: name)
    }
}
