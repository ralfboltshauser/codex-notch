import Foundation

struct CompletedTask: Codable, Equatable {
    let eventID: String
    let title: String
    let url: URL
    let receivedAt: Date
}

enum NtfyEventParser {
    private struct Event: Decodable {
        struct Action: Decodable {
            let action: String?
            let url: String?
        }

        let id: String?
        let time: TimeInterval?
        let event: String?
        let title: String?
        let message: String?
        let click: String?
        let actions: [Action]?
    }

    static func messageID(from data: Data) -> String? {
        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.event == "message" else { return nil }
        return event.id
    }

    static func task(from data: Data) -> CompletedTask? {
        guard let event = try? JSONDecoder().decode(Event.self, from: data),
              event.event == "message",
              let eventID = event.id,
              let url = candidateURLs(event).compactMap(validCodexThreadURL).first
        else { return nil }

        return CompletedTask(
            eventID: eventID,
            title: cleanTitle(event.title, message: event.message),
            url: url,
            receivedAt: Date(timeIntervalSince1970: event.time ?? Date().timeIntervalSince1970)
        )
    }

    static func validCodexThreadURL(_ value: String) -> URL? {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "codex",
              components.host?.lowercased() == "threads",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil else { return nil }

        let identifier = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard identifier == "new" || UUID(uuidString: identifier) != nil,
              !identifier.contains("/") else { return nil }
        return components.url
    }

    static func cleanTitle(_ title: String?, message: String?) -> String {
        let prefixes = ["Codex finished:", "Codex goblin:"]
        if var value = title?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            for prefix in prefixes where value.lowercased().hasPrefix(prefix.lowercased()) {
                value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? "Codex task finished" : value
        }

        if let asked = message?
            .components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("Asked: ") }) {
            let value = String(asked.dropFirst("Asked: ".count)).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return "Codex task finished"
    }

    private static func candidateURLs(_ event: Event) -> [String] {
        var values: [String] = []
        if let click = event.click { values.append(click) }
        values.append(contentsOf: event.actions?.compactMap {
            $0.action == "view" ? $0.url : nil
        } ?? [])
        return values
    }
}

final class TaskStore {
    private static let key = "completedTasks.v1"
    private let defaults: UserDefaults
    private(set) var tasks: [CompletedTask]
    var onChange: (([CompletedTask]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([CompletedTask].self, from: data) {
            tasks = Array(decoded.prefix(9))
        } else {
            tasks = []
        }
    }

    func add(_ task: CompletedTask) {
        guard !tasks.contains(where: { $0.eventID == task.eventID }) else { return }
        tasks.removeAll { $0.url == task.url }
        tasks.insert(task, at: 0)
        tasks = Array(tasks.prefix(9))
        commit()
    }

    @discardableResult
    func remove(at index: Int) -> CompletedTask? {
        guard tasks.indices.contains(index) else { return nil }
        let task = tasks.remove(at: index)
        commit()
        return task
    }

    func removeAll() {
        guard !tasks.isEmpty else { return }
        tasks.removeAll()
        commit()
    }

    private func commit() {
        if let data = try? JSONEncoder().encode(tasks) {
            defaults.set(data, forKey: Self.key)
        }
        onChange?(tasks)
    }
}
