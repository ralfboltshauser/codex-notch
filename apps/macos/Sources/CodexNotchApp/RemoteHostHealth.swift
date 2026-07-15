import Foundation

enum RemoteHostHealth: Equatable {
    case checking
    case working(checkedAt: Date)
    case unreachable(message: String, checkedAt: Date)
    case needsAttention(message: String, checkedAt: Date)

    var checkedAt: Date? {
        switch self {
        case .checking:
            return nil
        case .working(let checkedAt),
             .unreachable(_, let checkedAt),
             .needsAttention(_, let checkedAt):
            return checkedAt
        }
    }

    var statusText: String {
        switch self {
        case .checking: return "Checking…"
        case .working: return "Working"
        case .unreachable: return "Offline"
        case .needsAttention: return "Needs attention"
        }
    }

    var detailText: String? {
        switch self {
        case .checking, .working:
            return nil
        case .unreachable(let message, _), .needsAttention(let message, _):
            return message
        }
    }

    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }

    var isProblem: Bool {
        switch self {
        case .unreachable, .needsAttention: return true
        case .checking, .working: return false
        }
    }
}

struct RemoteHostHealthSnapshot: Equatable {
    static let empty = RemoteHostHealthSnapshot(hosts: [], healthByHostID: [:])

    let hosts: [RemoteHost]
    let healthByHostID: [String: RemoteHostHealth]
    var isRefreshing = false

    func health(for host: RemoteHost) -> RemoteHostHealth {
        healthByHostID[host.id] ?? .checking
    }

    var workingCount: Int {
        hosts.filter { health(for: $0).isWorking }.count
    }

    var problemCount: Int {
        hosts.filter { health(for: $0).isProblem }.count
    }

    var checkingCount: Int {
        hosts.count - workingCount - problemCount
    }

    var summaryText: String {
        let total = hosts.count
        guard total > 0 else { return "No remote hosts" }
        if checkingCount == total {
            return total == 1 ? "Checking host…" : "Checking \(total) hosts…"
        }
        if problemCount == 0, checkingCount == 0 {
            return total == 1 ? "Host working" : "\(total) hosts working"
        }
        if total == 1 {
            return health(for: hosts[0]).statusText
        }
        return "\(workingCount) of \(total) working"
    }
}

final class RemoteHostHealthMonitor {
    static let refreshInterval: TimeInterval = 300
    static let automaticRefreshCooldown: TimeInterval = 15

    private let pairings: PairingStore
    private let pairer: RemoteHostPairer
    private let probeQueue: OperationQueue
    private var timer: Timer?
    private var generation = 0
    private var refreshQueued = false
    private var lastRefreshStartedAt: Date?
    private(set) var snapshot = RemoteHostHealthSnapshot.empty

    var onChange: ((RemoteHostHealthSnapshot) -> Void)?

    init(pairings: PairingStore, pairer: RemoteHostPairer) {
        self.pairings = pairings
        self.pairer = pairer
        probeQueue = OperationQueue()
        probeQueue.name = "com.ralfbuilds.codex-notch.remote-health"
        probeQueue.qualityOfService = .utility
        probeQueue.maxConcurrentOperationCount = 4
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard timer == nil else { return }
        refresh(force: true)
        let timer = Timer(
            timeInterval: Self.refreshInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        generation &+= 1
        snapshot = RemoteHostHealthSnapshot.empty
    }

    func refresh(force: Bool = false) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.refresh(force: force) }
            return
        }
        if snapshot.isRefreshing {
            refreshQueued = refreshQueued || force
            return
        }
        if !force,
           let lastRefreshStartedAt,
           Date().timeIntervalSince(lastRefreshStartedAt) < Self.automaticRefreshCooldown {
            return
        }

        let hosts = pairings.hosts.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        let startingHealth: [String: RemoteHostHealth] = Dictionary(
            uniqueKeysWithValues: hosts.map { host in
                (host.id, snapshot.healthByHostID[host.id] ?? .checking)
            }
        )

        generation &+= 1
        let refreshGeneration = generation
        lastRefreshStartedAt = Date()
        snapshot = RemoteHostHealthSnapshot(
            hosts: hosts,
            healthByHostID: startingHealth,
            isRefreshing: !hosts.isEmpty
        )
        onChange?(snapshot)
        guard !hosts.isEmpty else { return }

        let group = DispatchGroup()
        for host in hosts {
            group.enter()
            probeQueue.addOperation { [weak self] in
                guard let self else { group.leave(); return }
                let result = self.pairer.checkHealth(host)
                DispatchQueue.main.async { [weak self] in
                    defer { group.leave() }
                    guard let self, self.generation == refreshGeneration else { return }
                    var updated = self.snapshot.healthByHostID
                    updated[host.id] = result
                    self.snapshot = RemoteHostHealthSnapshot(
                        hosts: hosts,
                        healthByHostID: updated,
                        isRefreshing: true
                    )
                    self.onChange?(self.snapshot)
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.generation == refreshGeneration else { return }
            self.snapshot = RemoteHostHealthSnapshot(
                hosts: hosts,
                healthByHostID: self.snapshot.healthByHostID,
                isRefreshing: false
            )
            self.onChange?(self.snapshot)
            if self.refreshQueued {
                self.refreshQueued = false
                self.refresh(force: true)
            }
        }
    }
}
