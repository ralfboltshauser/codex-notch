import Foundation
@testable import CodexNotchApp

final class ScriptedAppServerSocketClient: AppServerSocketClient {
    var onText: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var callbackQueue: DispatchQueue?
    var onLoadedListRequest: ((Int) -> Void)?
    var onThreadListRequest: ((Int) -> Void)?

    private let lock = NSLock()
    private var messages: [[String: Any]] = []
    private let listRows: [[String: Any]]
    private let loadedThreadIDs: [String]
    private let threads: [String: [String: Any]]
    private let listRowCycles: [[[String: Any]]]?
    private let loadedThreadIDCycles: [[String]]?
    private let loadedNextCursorByCycle: [Int: Any]
    private let loadedErrorByCycle: [Int: [String: Any]]
    private let loadedListUnavailable: Bool
    private let loadedPageSize: Int
    private let retryDelay: TimeInterval?
    private let responseDelay: TimeInterval
    private let loadedListRefreshDelays: [TimeInterval]
    private var loadedListTransientFailureCount: Int
    private var loadedListDroppedResponseCount: Int
    private var threadReadSendFailureCount: Int
    private var snapshotCycleIndex = 0
    private var threadListRequestCount = 0

    init(
        listRows: [[String: Any]] = [],
        loadedThreadIDs: [String] = [],
        threads: [String: [String: Any]] = [:],
        loadedListUnavailable: Bool = false,
        loadedPageSize: Int = 1,
        loadedListTransientFailureCount: Int = 0,
        loadedListDroppedResponseCount: Int = 0,
        threadReadSendFailureCount: Int = 0,
        retryDelay: TimeInterval? = nil,
        responseDelay: TimeInterval = 0,
        loadedListRefreshDelays: [TimeInterval] = [],
        listRowCycles: [[[String: Any]]]? = nil,
        loadedThreadIDCycles: [[String]]? = nil,
        loadedNextCursorByCycle: [Int: Any] = [:],
        loadedErrorByCycle: [Int: [String: Any]] = [:]
    ) {
        self.listRows = listRows
        self.loadedThreadIDs = loadedThreadIDs
        self.threads = threads
        self.listRowCycles = listRowCycles
        self.loadedThreadIDCycles = loadedThreadIDCycles
        self.loadedNextCursorByCycle = loadedNextCursorByCycle
        self.loadedErrorByCycle = loadedErrorByCycle
        self.loadedListUnavailable = loadedListUnavailable
        self.loadedPageSize = max(1, loadedPageSize)
        self.loadedListTransientFailureCount = loadedListTransientFailureCount
        self.loadedListDroppedResponseCount = loadedListDroppedResponseCount
        self.threadReadSendFailureCount = threadReadSendFailureCount
        self.retryDelay = retryDelay
        self.responseDelay = max(0, responseDelay)
        self.loadedListRefreshDelays = loadedListRefreshDelays
    }

    var sentMethods: [String] {
        recordedMessages.compactMap { $0["method"] as? String }
    }

    var threadReadIDs: [String] {
        threadReadParams.compactMap { $0["threadId"] as? String }
    }

    var threadReadParams: [[String: Any]] {
        recordedMessages.compactMap { message in
            guard message["method"] as? String == "thread/read" else { return nil }
            return message["params"] as? [String: Any]
        }
    }

    var loadedListLimits: [Int] {
        recordedMessages.compactMap { message in
            guard message["method"] as? String == "thread/loaded/list",
                  let params = message["params"] as? [String: Any] else { return nil }
            return params["limit"] as? Int
        }
    }

    func methodCount(_ method: String) -> Int {
        sentMethods.filter { $0 == method }.count
    }

    func start() throws {}

    func send(json: [String: Any]) throws {
        lock.lock()
        messages.append(json)
        lock.unlock()

        guard let method = json["method"] as? String,
              let id = json["id"] as? Int else { return }
        switch method {
        case "initialize":
            respond(["id": id, "result": [:]])
        case "thread/list":
            onThreadListRequest?(methodCount("thread/list"))
            snapshotCycleIndex = threadListRequestCount
            threadListRequestCount += 1
            let rows: [[String: Any]]
            if let listRowCycles, !listRowCycles.isEmpty {
                rows = listRowCycles[min(snapshotCycleIndex, listRowCycles.count - 1)]
            } else {
                rows = listRows
            }
            respond(["id": id, "result": ["data": rows, "nextCursor": NSNull()]])
        case "thread/loaded/list":
            let requestCount = methodCount("thread/loaded/list")
            onLoadedListRequest?(requestCount)
            if requestCount == 1 {
                for delay in loadedListRefreshDelays {
                    respond(["method": "thread/status/changed", "params": [:]], after: delay)
                }
            }
            if loadedListUnavailable {
                respond(["id": id, "error": ["code": -32601, "message": "Method not found"]])
                return
            }
            if loadedListTransientFailureCount > 0 {
                loadedListTransientFailureCount -= 1
                respond(["id": id, "error": ["code": -32_000, "message": "Temporarily unavailable"]])
                scheduleRefreshIfRequested()
                return
            }
            if loadedListDroppedResponseCount > 0 {
                loadedListDroppedResponseCount -= 1
                scheduleRefreshIfRequested()
                return
            }
            let cycleLoadedThreadIDs: [String]
            if let loadedThreadIDCycles, !loadedThreadIDCycles.isEmpty {
                cycleLoadedThreadIDs = loadedThreadIDCycles[
                    min(snapshotCycleIndex, loadedThreadIDCycles.count - 1)
                ]
            } else {
                cycleLoadedThreadIDs = loadedThreadIDs
            }
            let params = json["params"] as? [String: Any]
            let cursor = params?["cursor"] as? String
            let start = cursor.flatMap {
                cycleLoadedThreadIDs.firstIndex(of: $0).map { $0 + 1 }
            } ?? 0
            let end = min(start + loadedPageSize, cycleLoadedThreadIDs.count)
            let page = start < end ? Array(cycleLoadedThreadIDs[start ..< end]) : []
            let next = start + page.count < cycleLoadedThreadIDs.count ? page.last : nil
            let nextCursor: Any = loadedNextCursorByCycle[snapshotCycleIndex]
                ?? next.map { $0 as Any }
                ?? NSNull()
            var response: [String: Any] = [
                "id": id,
                "result": ["data": page, "nextCursor": nextCursor],
            ]
            if let error = loadedErrorByCycle[snapshotCycleIndex] {
                response["error"] = error
            }
            respond(response)
        case "thread/read":
            let params = json["params"] as? [String: Any]
            if threadReadSendFailureCount > 0 {
                threadReadSendFailureCount -= 1
                scheduleRefreshIfRequested()
                throw ScriptedClientError.sendFailed
            }
            if let threadID = params?["threadId"] as? String,
               let thread = threads[threadID] {
                respond(["id": id, "result": ["thread": thread]])
            } else {
                respond(["id": id, "error": ["code": -32602, "message": "Thread not found"]])
            }
        default:
            break
        }
    }

    func emit(method: String) {
        respond(["method": method, "params": [:]])
    }

    func close() {}

    private func scheduleRefreshIfRequested() {
        guard let retryDelay else { return }
        respond(["method": "thread/status/changed", "params": [:]], after: retryDelay)
    }

    private var recordedMessages: [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    private func respond(_ value: [String: Any], after delay: TimeInterval? = nil) {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        callbackQueue?.asyncAfter(deadline: .now() + (delay ?? responseDelay)) { [weak self] in
            self?.onText?(data)
        }
    }
}

private enum ScriptedClientError: Error {
    case sendFailed
}
