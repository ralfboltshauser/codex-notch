import CodexNotchCore
import Foundation

struct ActiveTask: Equatable {
    let threadID: String
    let title: String
    let sourceID: String
    let sourceLabel: String
    let state: ActiveTaskState
    let updatedAt: Date

    var url: URL? { CompletedTask.codexURL(threadID: threadID) }
}

final class ActiveTaskPreferences {
    static let shared = ActiveTaskPreferences()
    static let visibilityKey = "showActiveTasks.v1"
    static let didChangeNotification = Notification.Name("ActiveTaskPreferencesDidChange")

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Self.visibilityKey: true])
    }

    var isVisible: Bool {
        get { defaults.bool(forKey: Self.visibilityKey) }
        set {
            guard newValue != isVisible else { return }
            defaults.set(newValue, forKey: Self.visibilityKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }

    @discardableResult
    func toggle() -> Bool {
        isVisible.toggle()
        return isVisible
    }
}

final class ActiveTaskStore {
    private struct SourceState {
        var generation: String
        var sequence: UInt64
        var receivedAt: Date
        var tasks: [ActiveTask]
    }

    static let unavailableAfter: TimeInterval = 45
    static let removeAfter: TimeInterval = 120

    private var sources: [String: SourceState] = [:]
    private var completionSuppressions: [String: Date] = [:]
    private var retiredGenerations: [String: Set<String>] = [:]
    private let now: () -> Date
    var onChange: (([ActiveTask]) -> Void)?

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    var tasks: [ActiveTask] { visibleTasks(at: now()) }

    @discardableResult
    func replace(
        sourceID: String,
        sourceLabel: String,
        snapshot: ActiveTaskSnapshot,
        receivedAt: Date? = nil
    ) -> Bool {
        guard snapshot.isValid else { return false }
        if let current = sources[sourceID] {
            if current.generation == snapshot.generation {
                guard snapshot.sequence > current.sequence else { return false }
            } else {
                guard retiredGenerations[sourceID]?.contains(snapshot.generation) != true else {
                    return false
                }
                retiredGenerations[sourceID, default: []].insert(current.generation)
            }
        }
        let receivedAt = receivedAt ?? now()
        completionSuppressions = completionSuppressions.filter { $0.value > receivedAt }
        let mapped = snapshot.tasks.compactMap { event -> ActiveTask? in
            let suppressionKey = key(sourceID: sourceID, threadID: event.threadID)
            guard completionSuppressions[suppressionKey] == nil else { return nil }
            return ActiveTask(
                threadID: event.threadID.lowercased(),
                title: CompletionEvent.cleanTitle(event.title),
                sourceID: sourceID,
                sourceLabel: sourceLabel,
                state: event.state,
                updatedAt: event.updatedAt
            )
        }
        sources[sourceID] = SourceState(
            generation: snapshot.generation,
            sequence: snapshot.sequence,
            receivedAt: receivedAt,
            tasks: mapped
        )
        notify()
        return true
    }

    func remove(threadID: String, sourceID: String) {
        completionSuppressions[key(sourceID: sourceID, threadID: threadID)] = now().addingTimeInterval(0.5)
        guard var source = sources[sourceID] else { return }
        let count = source.tasks.count
        source.tasks.removeAll { $0.threadID.caseInsensitiveCompare(threadID) == .orderedSame }
        guard source.tasks.count != count else { return }
        sources[sourceID] = source
        notify()
    }

    func removeSource(_ sourceID: String) {
        guard sources.removeValue(forKey: sourceID) != nil else { return }
        retiredGenerations.removeValue(forKey: sourceID)
        notify()
    }

    func reapStaleSources() {
        let timestamp = now()
        sources = sources.filter { timestamp.timeIntervalSince($0.value.receivedAt) < Self.removeAfter }
        retiredGenerations = retiredGenerations.filter { sources[$0.key] != nil }
        onChange?(visibleTasks(at: timestamp))
    }

    private func visibleTasks(at timestamp: Date) -> [ActiveTask] {
        sources.values.flatMap { source -> [ActiveTask] in
            let age = timestamp.timeIntervalSince(source.receivedAt)
            guard age < Self.removeAfter else { return [] }
            if age >= Self.unavailableAfter {
                return source.tasks.map {
                    ActiveTask(
                        threadID: $0.threadID,
                        title: $0.title,
                        sourceID: $0.sourceID,
                        sourceLabel: $0.sourceLabel,
                        state: .unavailable,
                        updatedAt: $0.updatedAt
                    )
                }
            }
            return source.tasks
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.threadID < $1.threadID
        }
    }

    private func notify() { onChange?(tasks) }

    private func key(sourceID: String, threadID: String) -> String {
        "\(sourceID)\u{0}\(threadID.lowercased())"
    }
}
