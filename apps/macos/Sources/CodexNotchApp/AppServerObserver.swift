import CodexNotchCore
import Foundation

/// Read-only observer of Codex App Server runtime state. It never resumes,
/// starts, steers, or mutates a task.
final class AppServerObserver {
    private enum SnapshotCapability {
        case unknown
        case loadedThreadReads
        case listOnly
    }

    private enum SnapshotRequest {
        case threadList
        case loadedList
        case threadRead(String)
    }

    /// A snapshot can publish at most 50 tasks. Enumerate a bounded 1,000
    /// loaded IDs so the App Server's ascending UUID order does not bias reads
    /// toward old sessions, then read 50 recent candidates plus 50 ancestors.
    private static let maximumCandidateThreadReadCount = ActiveTaskSnapshot.maximumTaskCount
    private static let maximumAncestorThreadReadCount = ActiveTaskSnapshot.maximumTaskCount
    private static let loadedThreadPageSize = 100
    private static let maximumLoadedListPageCount = 10
    private static let maximumEnumeratedLoadedThreadCount = loadedThreadPageSize
        * maximumLoadedListPageCount
    private static let maximumConcurrentThreadReads = 8

    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.app-server")
    private let sourceID: String
    private let sourceLabel: String
    private let socketCandidatesProvider: () -> [String]
    private let pathExists: (String) -> Bool
    private let clientFactory: (String, DispatchQueue) -> AppServerSocketClient
    private let snapshotInactivityTimeout: TimeInterval
    private let snapshotCycleTimeout: TimeInterval
    private let snapshotFailureBackoff: TimeInterval
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
    private var snapshotCapability = SnapshotCapability.unknown
    private var snapshotCycleActive = false
    private var snapshotRefreshRequested = false
    private var snapshotRequests: [Int: SnapshotRequest] = [:]
    private var pendingSnapshotTimeout: DispatchWorkItem?
    private var pendingSnapshotCycleTimeout: DispatchWorkItem?
    private var snapshotCycleIdentifier: UInt64 = 0
    private var snapshotInactivityIdentifier: UInt64 = 0
    private var snapshotRetryNotBefore: DispatchTime?
    private var listedRowsByID: [String: [String: Any]] = [:]
    private var listedThreadIDs: [String] = []
    private var snapshotRowsByID: [String: [String: Any]] = [:]
    private var loadedThreadIDs: [String] = []
    private var loadedThreadIDSet: Set<String> = []
    private var loadedListCursors: Set<String> = []
    private var loadedListPageCount = 0
    private var requiredThreadIDs: [String] = []
    private var scheduledThreadIDs: Set<String> = []
    private var scheduledAncestorThreadReadCount = 0
    private var nextRequiredThreadIndex = 0

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
        },
        snapshotTimeout: TimeInterval = 6,
        snapshotCycleTimeout: TimeInterval = 8,
        snapshotFailureBackoff: TimeInterval = 2
    ) {
        self.sourceID = sourceID
        self.sourceLabel = sourceLabel
        socketCandidatesProvider = socketCandidates
        self.pathExists = pathExists
        self.clientFactory = clientFactory
        snapshotInactivityTimeout = max(0.01, snapshotTimeout)
        self.snapshotCycleTimeout = max(0.01, snapshotCycleTimeout)
        self.snapshotFailureBackoff = max(0.01, snapshotFailureBackoff)
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
            resetSnapshotCycle()
            snapshotCapability = .unknown
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
                    self.resetSnapshotCycle()
                    self.snapshotCapability = .unknown
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
                resetSnapshotCycle()
                snapshotCapability = .unknown
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
           let request = snapshotRequests.removeValue(forKey: id) {
            handleSnapshotResponse(request, value: value)
            return
        }
        if let id = (value["id"] as? NSNumber)?.intValue, id == pendingUsageRequestID {
            pendingUsageRequestID = nil
            pendingUsageTimeout?.cancel()
            pendingUsageTimeout = nil
            if value["result"] != nil { onRateLimits?(data) }
            sendUsageRequestIfPossible()
            return
        }
        guard let method = value["method"] as? String else { return }
        if method == "thread/status/changed" || method == "thread/name/updated"
            || method == "thread/started" || method == "thread/closed"
            || method == "thread/archived" || method == "thread/unarchived"
            || method == "thread/deleted" {
            requestSnapshot()
        }
    }

    private func requestSnapshot() {
        guard initialized, let client else { return }
        if let retryNotBefore = snapshotRetryNotBefore {
            guard DispatchTime.now() >= retryNotBefore else { return }
            snapshotRetryNotBefore = nil
        }
        if snapshotCycleActive {
            snapshotRefreshRequested = true
            return
        }
        snapshotCycleActive = true
        snapshotCycleIdentifier &+= 1
        snapshotRefreshRequested = false
        listedRowsByID = [:]
        listedThreadIDs = []
        snapshotRowsByID = [:]
        loadedThreadIDs = []
        loadedThreadIDSet = []
        loadedListCursors = []
        loadedListPageCount = 0
        requiredThreadIDs = []
        scheduledThreadIDs = []
        scheduledAncestorThreadReadCount = 0
        nextRequiredThreadIndex = 0
        armSnapshotCycleDeadline()
        let id = nextRequestID
        nextRequestID &+= 1
        snapshotRequests[id] = .threadList
        do {
            try client.send(json: [
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
            armSnapshotTimeout()
        } catch {
            snapshotRequests.removeValue(forKey: id)
            abortSnapshotCycleAfterFailure()
        }
    }

    private func handleSnapshotResponse(
        _ request: SnapshotRequest,
        value: [String: Any]
    ) {
        guard snapshotCycleActive else { return }
        pendingSnapshotTimeout?.cancel()
        pendingSnapshotTimeout = nil

        switch request {
        case .threadList:
            if let error = value["error"], !(error is NSNull) {
                abortSnapshotCycleAfterFailure()
                return
            }
            guard let result = value["result"] as? [String: Any],
                  let rows = result["data"] as? [[String: Any]] else {
                abortSnapshotCycleAfterFailure()
                return
            }
            for row in rows {
                guard let safe = AppServerThreadProjection.reconciliationRow(from: row),
                      let id = safe["id"] as? String else {
                    abortSnapshotCycleAfterFailure()
                    return
                }
                if listedRowsByID[id] == nil { listedThreadIDs.append(id) }
                listedRowsByID[id] = safe
            }
            snapshotRowsByID = listedRowsByID
            if snapshotCapability == .listOnly {
                publishAndFinish(Array(listedRowsByID.values))
            } else {
                sendLoadedThreadPage(cursor: nil)
            }

        case .loadedList:
            if let error = value["error"], !(error is NSNull) {
                if isMethodUnavailable(error) {
                    snapshotCapability = .listOnly
                    publishAndFinish(Array(listedRowsByID.values))
                } else {
                    abortSnapshotCycleAfterFailure()
                }
                return
            }
            guard let result = value["result"] as? [String: Any],
                  let ids = result["data"] as? [String] else {
                // A transient/protocol failure says nothing about method
                // support. Preserve the last published snapshot and retry.
                abortSnapshotCycleAfterFailure()
                return
            }
            snapshotCapability = .loadedThreadReads
            for rawID in ids {
                guard let id = canonicalThreadID(rawID) else {
                    abortSnapshotCycleAfterFailure()
                    return
                }
                guard loadedThreadIDSet.insert(id).inserted else { continue }
                guard loadedThreadIDs.count < Self.maximumEnumeratedLoadedThreadCount else {
                    abortSnapshotCycleAfterFailure()
                    return
                }
                loadedThreadIDs.append(id)
            }
            let rawCursor = result["nextCursor"]
            if let cursor = rawCursor as? String, !cursor.isEmpty {
                // An incomplete ascending enumeration would systematically
                // exclude newer UUIDv7 sessions. Fail closed at the work bound.
                guard loadedListPageCount < Self.maximumLoadedListPageCount,
                      loadedThreadIDs.count < Self.maximumEnumeratedLoadedThreadCount else {
                    abortSnapshotCycleAfterFailure()
                    return
                }
                guard loadedListCursors.insert(cursor).inserted else {
                    abortSnapshotCycleAfterFailure()
                    return
                }
                sendLoadedThreadPage(cursor: cursor)
            } else if rawCursor == nil || rawCursor is NSNull
                        || (rawCursor as? String)?.isEmpty == true {
                beginLoadedThreadReads()
            } else {
                abortSnapshotCycleAfterFailure()
            }

        case .threadRead(let requestedID):
            if let error = value["error"], !(error is NSNull) {
                if isMethodUnavailable(error) {
                    snapshotCapability = .listOnly
                    snapshotRequests = snapshotRequests.filter {
                        if case .threadRead = $0.value { return false }
                        return true
                    }
                    publishAndFinish(Array(listedRowsByID.values))
                } else {
                    abortSnapshotCycleAfterFailure()
                }
                return
            }
            guard let result = value["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let safe = AppServerThreadProjection.reconciliationRow(from: thread),
                  safe["id"] as? String == requestedID else {
                // A failed read would otherwise demote an active thread using
                // the baseline list row. Abort rather than publish partial state.
                abortSnapshotCycleAfterFailure()
                return
            }
            snapshotRowsByID[requestedID] = safe
            if let parentID = safe["parentThreadId"] as? String,
               snapshotRowsByID[parentID] == nil,
               scheduledAncestorThreadReadCount < Self.maximumAncestorThreadReadCount,
               scheduledThreadIDs.insert(parentID).inserted {
                scheduledAncestorThreadReadCount += 1
                requiredThreadIDs.append(parentID)
            }
            pumpLoadedThreadReads()
        }
    }

    private func sendLoadedThreadPage(cursor: String?) {
        guard snapshotCycleActive, let client else {
            abortSnapshotCycleAfterFailure()
            return
        }
        guard loadedListPageCount < Self.maximumLoadedListPageCount else {
            abortSnapshotCycleAfterFailure()
            return
        }
        loadedListPageCount += 1
        let id = nextRequestID
        nextRequestID &+= 1
        var params: [String: Any] = ["limit": Self.loadedThreadPageSize]
        if let cursor { params["cursor"] = cursor }
        snapshotRequests[id] = .loadedList
        do {
            try client.send(json: [
                "id": id,
                "method": "thread/loaded/list",
                "params": params,
            ])
            armSnapshotTimeout()
        } catch {
            snapshotRequests.removeValue(forKey: id)
            abortSnapshotCycleAfterFailure()
        }
    }

    private func beginLoadedThreadReads() {
        for id in snapshotRowsByID.keys {
            guard var row = snapshotRowsByID[id],
                  (row["status"] as? [String: Any])?["type"] as? String == "active" else {
                continue
            }
            row["status"] = ["type": "notLoaded"]
            snapshotRowsByID[id] = row
        }
        var candidates: [String] = []
        var candidateSet: Set<String> = []
        // thread/list is explicitly requested in updated-descending order, so
        // loaded IDs present there are the strongest recency signal (including
        // old, long-running UUIDs). Fill remaining capacity from the newest end
        // of thread/loaded/list's ascending UUID order.
        for id in listedThreadIDs where loadedThreadIDSet.contains(id) {
            guard candidates.count < Self.maximumCandidateThreadReadCount else { break }
            guard candidateSet.insert(id).inserted else { continue }
            candidates.append(id)
        }
        if candidates.count < Self.maximumCandidateThreadReadCount {
            for id in loadedThreadIDs.reversed() {
                guard candidates.count < Self.maximumCandidateThreadReadCount else { break }
                guard candidateSet.insert(id).inserted else { continue }
                candidates.append(id)
            }
        }
        requiredThreadIDs = candidates
        scheduledThreadIDs = candidateSet
        nextRequiredThreadIndex = 0
        pumpLoadedThreadReads()
    }

    private func pumpLoadedThreadReads() {
        guard snapshotCycleActive, snapshotCapability == .loadedThreadReads,
              let client else { return }
        while snapshotCycleActive,
              pendingThreadReadCount < Self.maximumConcurrentThreadReads,
              nextRequiredThreadIndex < requiredThreadIDs.count {
            let threadID = requiredThreadIDs[nextRequiredThreadIndex]
            nextRequiredThreadIndex += 1
            let id = nextRequestID
            nextRequestID &+= 1
            snapshotRequests[id] = .threadRead(threadID)
            do {
                try client.send(json: [
                    "id": id,
                    "method": "thread/read",
                    "params": [
                        "threadId": threadID,
                        "includeTurns": false,
                    ],
                ])
                armSnapshotTimeout()
            } catch {
                snapshotRequests.removeValue(forKey: id)
                // A write can fail after other reads have succeeded. Publishing
                // here would turn the missing row into a false completion.
                abortSnapshotCycleAfterFailure()
                return
            }
        }
        if pendingThreadReadCount > 0 { armSnapshotTimeout() }
        guard snapshotCycleActive,
              nextRequiredThreadIndex >= requiredThreadIDs.count,
              pendingThreadReadCount == 0 else { return }
        publishAndFinish(Array(snapshotRowsByID.values))
    }

    private var pendingThreadReadCount: Int {
        snapshotRequests.values.reduce(into: 0) { count, request in
            if case .threadRead = request { count += 1 }
        }
    }

    private func armSnapshotTimeout() {
        guard snapshotCycleActive, !snapshotRequests.isEmpty else { return }
        pendingSnapshotTimeout?.cancel()
        snapshotInactivityIdentifier &+= 1
        let identifier = snapshotInactivityIdentifier
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.snapshotCycleActive,
                  self.snapshotInactivityIdentifier == identifier else { return }
            self.abortSnapshotCycleAfterFailure()
        }
        pendingSnapshotTimeout = timeout
        queue.asyncAfter(deadline: .now() + snapshotInactivityTimeout, execute: timeout)
    }

    private func armSnapshotCycleDeadline() {
        pendingSnapshotCycleTimeout?.cancel()
        let identifier = snapshotCycleIdentifier
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.snapshotCycleActive,
                  self.snapshotCycleIdentifier == identifier else { return }
            self.abortSnapshotCycleAfterFailure()
        }
        pendingSnapshotCycleTimeout = timeout
        queue.asyncAfter(deadline: .now() + snapshotCycleTimeout, execute: timeout)
    }

    private func abortSnapshotCycleAfterFailure() {
        // A failed read says nothing about optional-method support. Preserve the
        // last complete snapshot, drop coalesced refreshes, and apply a short
        // monotonic backoff so malformed, slow, or unavailable servers cannot
        // create continuous reconciliation load.
        snapshotRetryNotBefore = .now() + snapshotFailureBackoff
        finishSnapshotCycle(honorRefresh: false)
    }

    private func publishAndFinish(_ rows: [[String: Any]]) {
        publish(rows)
        finishSnapshotCycle()
    }

    private func finishSnapshotCycle(honorRefresh: Bool = true) {
        pendingSnapshotTimeout?.cancel()
        pendingSnapshotTimeout = nil
        snapshotInactivityIdentifier &+= 1
        pendingSnapshotCycleTimeout?.cancel()
        pendingSnapshotCycleTimeout = nil
        snapshotRequests.removeAll()
        snapshotCycleActive = false
        listedRowsByID = [:]
        listedThreadIDs = []
        snapshotRowsByID = [:]
        loadedThreadIDs = []
        loadedThreadIDSet = []
        loadedListCursors = []
        loadedListPageCount = 0
        requiredThreadIDs = []
        scheduledThreadIDs = []
        scheduledAncestorThreadReadCount = 0
        nextRequiredThreadIndex = 0
        let refresh = honorRefresh && snapshotRefreshRequested
        snapshotRefreshRequested = false
        if refresh { requestSnapshot() }
    }

    private func resetSnapshotCycle() {
        snapshotRetryNotBefore = nil
        snapshotRefreshRequested = false
        finishSnapshotCycle()
    }

    private func isMethodUnavailable(_ error: Any?) -> Bool {
        guard let error = error as? [String: Any] else { return false }
        // JSON-RPC reserves -32601 for Method not found. Human-readable error
        // text is not a stable capability signal and may describe a transient.
        return (error["code"] as? NSNumber)?.intValue == -32601
    }

    private func canonicalThreadID(_ value: String) -> String? {
        UUID(uuidString: value)?.uuidString.lowercased()
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
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.threadID < $1.threadID
            }
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
