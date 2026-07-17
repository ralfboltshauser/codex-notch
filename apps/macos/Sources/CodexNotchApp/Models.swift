import CodexNotchCore
import Foundation

struct CompletedTask: Codable, Equatable {
    let eventID: String
    let threadID: String
    let title: String
    let outcome: String?
    let sourceID: String
    let sourceLabel: String
    let url: URL
    let receivedAt: Date

    enum CodingKeys: String, CodingKey {
        case eventID, threadID, title, outcome, sourceID, sourceLabel, url, receivedAt
    }

    init(
        eventID: String,
        threadID: String? = nil,
        title: String,
        sourceID: String = "local",
        sourceLabel: String = "This Mac",
        url: URL,
        receivedAt: Date,
        outcome: String? = nil
    ) {
        self.eventID = eventID
        self.threadID = threadID ?? url.lastPathComponent
        self.title = title
        self.outcome = outcome.flatMap(CompletionOutcomeFormatter.format)
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel
        self.url = url
        self.receivedAt = receivedAt
    }

    init?(event: CompletionEvent) {
        guard event.isValid,
              let url = Self.codexURL(threadID: event.threadID) else { return nil }
        self.init(
            eventID: event.eventID,
            threadID: event.threadID,
            title: event.title,
            sourceID: event.sourceID,
            sourceLabel: event.sourceLabel,
            url: url,
            receivedAt: event.completedAt,
            outcome: event.outcome
        )
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try values.decode(String.self, forKey: .eventID)
        threadID = try values.decode(String.self, forKey: .threadID)
        title = try values.decode(String.self, forKey: .title)
        outcome = try values.decodeIfPresent(String.self, forKey: .outcome)
            .flatMap(CompletionOutcomeFormatter.format)
        sourceID = try values.decodeIfPresent(String.self, forKey: .sourceID) ?? "local"
        sourceLabel = try values.decodeIfPresent(String.self, forKey: .sourceLabel) ?? "This Mac"
        url = try values.decode(URL.self, forKey: .url)
        receivedAt = try values.decode(Date.self, forKey: .receivedAt)
    }

    static func codexURL(threadID: String) -> URL? {
        guard let id = UUID(uuidString: threadID) else { return nil }
        return URL(string: "codex://threads/\(id.uuidString.lowercased())")
    }
}

final class TaskStore {
    static let maximumTaskCount = 10

    private let fileURL: URL
    private(set) var tasks: [CompletedTask]
    var onChange: (([CompletedTask]) -> Void)?

    init(fileURL: URL = AppPaths.tasksFile) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.codexNotch.decode([CompletedTask].self, from: data) {
            tasks = Array(decoded.prefix(Self.maximumTaskCount))
        } else {
            tasks = []
        }
    }

    @discardableResult
    func add(_ task: CompletedTask) throws -> Bool {
        guard !tasks.contains(where: { $0.eventID == task.eventID }) else { return false }
        var updated = tasks.filter { $0.threadID != task.threadID }
        updated.insert(task, at: 0)
        updated = Array(updated.prefix(Self.maximumTaskCount))
        try persist(updated)
        tasks = updated
        onChange?(tasks)
        return true
    }

    @discardableResult
    func remove(at index: Int) -> CompletedTask? {
        guard tasks.indices.contains(index) else { return nil }
        var updated = tasks
        let removed = updated.remove(at: index)
        do { try persist(updated) }
        catch { return nil }
        tasks = updated
        onChange?(tasks)
        return removed
    }

    func removeAll() {
        guard !tasks.isEmpty else { return }
        do { try persist([]) }
        catch { return }
        tasks.removeAll()
        onChange?(tasks)
    }

    private func persist(_ value: [CompletedTask]) throws {
        try AppPaths.prepareDirectory(fileURL.deletingLastPathComponent())
        let data = try JSONEncoder.codexNotch.encode(value)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
