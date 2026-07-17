import CodexNotchCore
import Foundation

/// Read-only observer of Codex App Server runtime state. It never resumes,
/// starts, steers, or mutates a task.
final class AppServerObserver {
    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.app-server")
    private let sourceID: String
    private let sourceLabel: String
    private let socketCandidatesProvider: () -> [String]
    private let pathExists: (String) -> Bool
    private let clientFactory: (String, DispatchQueue) -> AppServerSocketClient
    private var client: AppServerSocketClient?
    private var reconnect: DispatchWorkItem?
    private var pollTimer: DispatchSourceTimer?
    private var generation = UUID().uuidString.lowercased()
    private var sequence: UInt64 = 0
    private var nextRequestID = 2
    private var initialized = false
    private var stopped = true
    private var pendingUsageRequestID: Int?
    private var pendingUsageTimeout: DispatchWorkItem?
    private var usageRefreshRequested = true

    var onSnapshot: ((String, String, ActiveTaskSnapshot) -> Void)?
    var onRateLimits: ((Data) -> Void)?

    init(
        sourceID: String = "local",
        sourceLabel: String = "This Mac",
        socketCandidates: @escaping () -> [String] = {
            AppServerObserver.socketCandidates()
        },
        pathExists: @escaping (String) -> Bool = {
            FileManager.default.fileExists(atPath: $0)
        },
        clientFactory: @escaping (String, DispatchQueue) -> AppServerSocketClient = {
            UnixWebSocketClient(path: $0, queue: $1)
        }
    ) {
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel
        socketCandidatesProvider = socketCandidates
        self.pathExists = pathExists
        self.clientFactory = clientFactory
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.stopped else { return }
            self.stopped = false
            self.connect()
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            reconnect?.cancel()
            reconnect = nil
            pollTimer?.cancel()
            pollTimer = nil
            client?.close()
            client = nil
            pendingUsageRequestID = nil
            pendingUsageTimeout?.cancel()
            pendingUsageTimeout = nil
            usageRefreshRequested = true
        }
    }

    func requestUsage() {
        queue.async { [weak self] in
            guard let self else { return }
            guard self.pendingUsageRequestID == nil else { return }
            self.usageRefreshRequested = true
            self.sendUsageRequestIfPossible()
        }
    }

    private func connect() {
        guard !stopped else { return }
        let sockets = socketCandidatesProvider().filter(pathExists)
        for socket in sockets {
            let candidate = clientFactory(socket, queue)
            let candidateID = ObjectIdentifier(candidate)
            candidate.onText = { [weak self] data in self?.handle(data) }
            candidate.onClose = { [weak self] in
                self?.queue.async {
                    guard let self,
                          let client = self.client,
                          ObjectIdentifier(client) == candidateID else { return }
                    self.client = nil
                    self.initialized = false
                    self.pendingUsageRequestID = nil
                    self.pendingUsageTimeout?.cancel()
                    self.pendingUsageTimeout = nil
                    self.usageRefreshRequested = true
                    self.pollTimer?.cancel()
                    self.pollTimer = nil
                    self.scheduleReconnect()
                }
            }
            do {
                try candidate.start()
                client = candidate
                generation = UUID().uuidString.lowercased()
                sequence = 0
                initialized = false
                pendingUsageRequestID = nil
                pendingUsageTimeout?.cancel()
                pendingUsageTimeout = nil
                usageRefreshRequested = true
                try candidate.send(json: [
                    "id": 1,
                    "method": "initialize",
                    "params": [
                        "clientInfo": ["name": "codex-notch", "title": "Codex Notch", "version": appVersion],
                        "capabilities": ["experimentalApi": false],
                    ],
                ])
                return
            } catch {
                client = nil
                candidate.close()
            }
        }
        scheduleReconnect()
    }

    private func handle(_ data: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        if (value["id"] as? NSNumber)?.intValue == 1, value["result"] != nil, !initialized {
            initialized = true
            try? client?.send(json: ["method": "initialized"])
            requestSnapshot()
            sendUsageRequestIfPossible()
            startPolling()
            return
        }
        if let id = (value["id"] as? NSNumber)?.intValue,
           id == pendingUsageRequestID {
            pendingUsageRequestID = nil
            pendingUsageTimeout?.cancel()
            pendingUsageTimeout = nil
            if value["result"] != nil { onRateLimits?(data) }
            sendUsageRequestIfPossible()
            return
        }
        if let result = value["result"] as? [String: Any], let rows = result["data"] as? [[String: Any]] {
            publish(rows)
            return
        }
        guard let method = value["method"] as? String else { return }
        if method == "thread/status/changed" || method == "thread/name/updated"
            || method == "thread/started" || method == "thread/closed" {
            requestSnapshot()
        }
    }

    private func requestSnapshot() {
        guard initialized, let client else { return }
        let id = nextRequestID
        nextRequestID &+= 1
        try? client.send(json: [
            "id": id,
            "method": "thread/list",
            "params": [
                "archived": false,
                "limit": 100,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "useStateDbOnly": true,
            ],
        ])
    }

    private func sendUsageRequestIfPossible() {
        guard initialized,
              usageRefreshRequested,
              pendingUsageRequestID == nil,
              let client else { return }
        let id = nextRequestID
        nextRequestID &+= 1
        usageRefreshRequested = false
        pendingUsageRequestID = id
        do {
            try client.send(json: [
                "id": id,
                "method": "account/rateLimits/read",
                "params": NSNull(),
            ])
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.pendingUsageRequestID == id else { return }
                self.pendingUsageRequestID = nil
                self.pendingUsageTimeout = nil
                self.sendUsageRequestIfPossible()
            }
            pendingUsageTimeout = timeout
            queue.asyncAfter(deadline: .now() + 6, execute: timeout)
        } catch {
            pendingUsageRequestID = nil
            pendingUsageTimeout = nil
            usageRefreshRequested = true
        }
    }

    private func publish(_ rows: [[String: Any]]) {
        let timestamp = Date()
        let active = AppServerThreadProjection.activeEvents(from: rows, observedAt: timestamp)
        sequence &+= 1
        let snapshot = ActiveTaskSnapshot(
            generation: generation,
            sequence: sequence,
            generatedAt: timestamp,
            tasks: Array(active.prefix(ActiveTaskSnapshot.maximumTaskCount))
        )
        guard snapshot.isValid else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onSnapshot?(self.sourceID, self.sourceLabel, snapshot)
        }
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10, repeating: 10, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in self?.requestSnapshot() }
        timer.resume()
        pollTimer = timer
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        reconnect?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnect = work
        queue.asyncAfter(deadline: .now() + 2, execute: work)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
    }

    static func socketCandidates(
        codexHome: URL = AppPaths.codexHome,
        temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory())
    ) -> [String] {
        var paths = [codexHome.appendingPathComponent("app-server-control/app-server-control.sock").path]
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            paths.append(contentsOf: contents
                .filter { $0.lastPathComponent.hasPrefix("codex-rc-") }
                .map { $0.appendingPathComponent("rc.sock").path })
        }
        let systemTemporary = URL(fileURLWithPath: "/tmp")
        if systemTemporary.standardizedFileURL != temporaryDirectory.standardizedFileURL,
           let contents = try? FileManager.default.contentsOfDirectory(
               at: systemTemporary,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            paths.append(contentsOf: contents
                .filter { $0.lastPathComponent.hasPrefix("codex-rc-") }
                .map { $0.appendingPathComponent("rc.sock").path })
        }
        return paths
    }
}
