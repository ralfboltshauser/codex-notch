import Darwin
import Foundation

struct CodexWeeklyLimit: Equatable {
    static let weeklyWindowMinutes = 7 * 24 * 60

    let remainingPercent: Int
    let resetsAt: Date?
}

struct CodexRateLimitWindow: Equatable {
    let durationMinutes: Int
    let remainingPercent: Int
    let resetsAt: Date?

    var durationLabel: String {
        if durationMinutes.isMultiple(of: 24 * 60) {
            return "\(durationMinutes / (24 * 60))d"
        }
        if durationMinutes.isMultiple(of: 60) {
            return "\(durationMinutes / 60)h"
        }
        return "\(durationMinutes)m"
    }

    var isReached: Bool { remainingPercent == 0 }
    var isWeekly: Bool { durationMinutes == CodexWeeklyLimit.weeklyWindowMinutes }
}

struct CodexAccountRateLimits: Equatable {
    let windows: [CodexRateLimitWindow]

    var weeklyLimit: CodexWeeklyLimit? {
        guard let window = windows.first(where: \.isWeekly) else { return nil }
        return CodexWeeklyLimit(
            remainingPercent: window.remainingPercent,
            resetsAt: window.resetsAt
        )
    }
}

enum CodexUsageState: Equatable {
    case idle
    case loading
    case available(CodexUsageOverview)
    case availableWindows([CodexRateLimitWindow])
    case stale(windows: [CodexRateLimitWindow], observedAt: Date, message: String)
    case unavailable(message: String)

    var overview: CodexUsageOverview? {
        if case .available(let overview) = self { return overview }
        return nil
    }

    var isVisible: Bool {
        if case .idle = self { return false }
        return true
    }
}

enum CodexRateLimitParser {
    static func accountLimits(from response: Data) -> CodexAccountRateLimits? {
        guard let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = root["result"] as? [String: Any]
        else { return nil }

        var snapshots: [[String: Any]] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any],
           isCodexAccountSnapshot(codex) {
            snapshots.append(codex)
        }
        if let historical = result["rateLimits"] as? [String: Any],
           isCodexAccountSnapshot(historical) {
            snapshots.append(historical)
        }

        for snapshot in snapshots {
            let windows = ["primary", "secondary"].compactMap { key -> CodexRateLimitWindow? in
                guard let window = snapshot[key] as? [String: Any],
                      let durationMinutes = integer(window["windowDurationMins"]),
                      durationMinutes > 0,
                      let usedPercent = integer(window["usedPercent"])
                else { return nil }

                let clampedUsage = min(100, max(0, usedPercent))
                let resetsAt = integer(window["resetsAt"]).map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                }
                return CodexRateLimitWindow(
                    durationMinutes: durationMinutes,
                    remainingPercent: 100 - clampedUsage,
                    resetsAt: resetsAt
                )
            }
            if !windows.isEmpty { return CodexAccountRateLimits(windows: windows) }
        }
        return nil
    }

    static func weeklyLimit(from response: Data) -> CodexWeeklyLimit? {
        accountLimits(from: response)?.weeklyLimit
    }

    private static func isCodexAccountSnapshot(_ snapshot: [String: Any]) -> Bool {
        guard let limitID = snapshot["limitId"] as? String else {
            // Older app-server responses did not identify the single account bucket.
            return true
        }
        return limitID == "codex"
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber {
            let double = value.doubleValue
            guard double.isFinite, double.rounded() == double else { return nil }
            return value.intValue
        }
        return nil
    }
}

struct CodexExecutableLocator {
    static func candidates(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        let fixed = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            homeDirectory.appendingPathComponent(
                "Applications/Codex.app/Contents/Resources/codex"
            ).path,
            homeDirectory.appendingPathComponent(
                "Applications/ChatGPT.app/Contents/Resources/codex"
            ).path,
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
            homeDirectory.appendingPathComponent(".npm-global/bin/codex").path,
            homeDirectory.appendingPathComponent(".bun/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]
        let fromPath = environment["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }

        var seen: Set<String> = []
        return (fixed + fromPath).compactMap { path in
            let standardized = URL(fileURLWithPath: path).standardizedFileURL
            return seen.insert(standardized.path).inserted ? standardized : nil
        }
    }

    static func availableExecutables(
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var seen: Set<String> = []
        return candidates(homeDirectory: homeDirectory, environment: environment).compactMap {
            let resolved = $0.resolvingSymlinksInPath().standardizedFileURL
            guard fileManager.isExecutableFile(atPath: resolved.path),
                  seen.insert(resolved.path).inserted else { return nil }
            return resolved
        }
    }
}

enum CodexAppServerError: LocalizedError {
    case timedOut
    case rejected(String)
    case exited

    var errorDescription: String? {
        switch self {
        case .timedOut: return "Codex did not return usage information in time"
        case .rejected(let message): return message
        case .exited: return "Codex exited before returning usage information"
        }
    }
}

struct CodexAppServerClient {
    var timeout: TimeInterval = 8

    func readRateLimits(executable: URL) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning { process.terminate() }
        }

        let messages: [[String: Any]] = [
            [
                "method": "initialize",
                "id": 1,
                "params": [
                    "clientInfo": [
                        "name": "codex_notch",
                        "title": "Codex Notch",
                        "version": Bundle.main.object(
                            forInfoDictionaryKey: "CFBundleShortVersionString"
                        ) as? String ?? "unknown",
                    ],
                ],
            ],
            ["method": "initialized", "params": [:]],
            ["method": "account/rateLimits/read", "id": 2, "params": NSNull()],
        ]
        for message in messages {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(0x0A)
            input.fileHandleForWriting.write(data)
        }

        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)
        let descriptor = output.fileHandleForReading.fileDescriptor
        while Date() < deadline {
            let remaining = max(1, Int(deadline.timeIntervalSinceNow * 1_000))
            var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            let status = Darwin.poll(&pollDescriptor, 1, Int32(min(remaining, 500)))
            if status < 0 {
                if errno == EINTR { continue }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if status == 0 { continue }
            if pollDescriptor.revents & Int16(POLLIN) != 0,
               let chunk = try output.fileHandleForReading.read(upToCount: 64 * 1_024),
               !chunk.isEmpty {
                buffer.append(chunk)
                if let response = try rateLimitResponse(in: buffer) { return response }
            }
            if pollDescriptor.revents & Int16(POLLHUP) != 0,
               !process.isRunning {
                throw CodexAppServerError.exited
            }
        }
        throw CodexAppServerError.timedOut
    }

    private func rateLimitResponse(in buffer: Data) throws -> Data? {
        for rawLine in buffer.split(separator: 0x0A) {
            let line = Data(rawLine)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let id = object["id"] as? NSNumber,
                  id.intValue == 2
            else { continue }
            if let error = object["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Codex rejected the usage request"
                throw CodexAppServerError.rejected(message)
            }
            return line
        }
        return nil
    }
}

final class CodexUsageMonitor {
    static let refreshInterval: TimeInterval = 15 * 60
    static let maximumFallbackDuration: TimeInterval = 12
    // The live App Server reader has a six-second request timeout but no failure
    // callback. Give that independent path time to supersede a fast fallback error.
    static let alternateReadGraceInterval: TimeInterval = 6.25

    var onChange: ((CodexUsageState) -> Void)?
    var onRefreshRequested: (() -> Void)?

    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.usage", qos: .utility)
    private let workerQueue = DispatchQueue(
        label: "com.ralfbuilds.codex-notch.usage-worker",
        qos: .utility
    )
    private let client: CodexAppServerClient
    private let historyStore: CodexUsageHistoryStore
    private let now: () -> Date
    private let availableExecutables: () -> [URL]
    private let failureGraceInterval: TimeInterval
    private var timer: DispatchSourceTimer?
    private var pendingFailure: DispatchWorkItem?
    private var pendingFailureID: UUID?
    private var isRefreshing = false
    private var successfulReadGeneration: UInt64 = 0
    private var lastAvailableWindows: [CodexRateLimitWindow]?
    private var lastAvailableAt: Date?

    private enum RefreshResult {
        case available(CodexAccountRateLimits)
        case unavailable(String)
    }

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        historyStore: CodexUsageHistoryStore = CodexUsageHistoryStore(),
        now: @escaping () -> Date = Date.init,
        availableExecutables: @escaping () -> [URL] = {
            CodexExecutableLocator.availableExecutables()
        },
        failureGraceInterval: TimeInterval = CodexUsageMonitor.alternateReadGraceInterval
    ) {
        self.client = client
        self.historyStore = historyStore
        self.now = now
        self.availableExecutables = availableExecutables
        self.failureGraceInterval = max(0, failureGraceInterval)
    }

    func start() {
        publish(.loading)
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            self.beginRefresh()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now() + Self.refreshInterval,
                repeating: Self.refreshInterval,
                leeway: .seconds(15)
            )
            timer.setEventHandler { [weak self] in self?.beginRefresh() }
            self.timer = timer
            timer.resume()
        }
    }

    func refresh() {
        queue.async { [weak self] in
            self?.beginRefresh()
        }
    }

    func acceptRateLimitResponse(_ response: Data) {
        guard let limits = CodexRateLimitParser.accountLimits(from: response) else { return }
        queue.async { [weak self] in self?.publish(limits) }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
            self?.pendingFailure?.cancel()
            self?.pendingFailure = nil
            self?.pendingFailureID = nil
        }
    }

    private func beginRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        pendingFailure?.cancel()
        pendingFailure = nil
        pendingFailureID = nil
        let generationAtStart = successfulReadGeneration
        let alternateReadDeadline = DispatchTime.now() + failureGraceInterval
        DispatchQueue.main.async { [weak self] in self?.onRefreshRequested?() }
        workerQueue.async { [weak self] in
            guard let self else { return }
            let result = self.fetchUsage()
            self.queue.async { [weak self] in
                guard let self else { return }
                self.isRefreshing = false
                switch result {
                case .available(let limit): self.publish(limit)
                case .unavailable(let message):
                    self.publishUnavailable(
                        message,
                        unlessSucceededAfter: generationAtStart,
                        notBefore: alternateReadDeadline
                    )
                }
            }
        }
    }

    private func fetchUsage() -> RefreshResult {
        let executables = availableExecutables()
        guard !executables.isEmpty else {
            return .unavailable("Codex app or CLI was not found")
        }

        var errors: [String] = []
        var receivedResponse = false
        let fallbackDeadline = Date().addingTimeInterval(Self.maximumFallbackDuration)
        for executable in executables {
            let remainingTime = fallbackDeadline.timeIntervalSinceNow
            guard remainingTime > 0 else { break }
            let response: Data
            do {
                var boundedClient = client
                boundedClient.timeout = min(client.timeout, remainingTime)
                response = try boundedClient.readRateLimits(executable: executable)
            } catch {
                errors.append(error.localizedDescription)
                continue
            }
            receivedResponse = true
            if let limits = CodexRateLimitParser.accountLimits(from: response) {
                return .available(limits)
            }
        }
        if receivedResponse {
            return .unavailable("Codex returned no account usage windows")
        }
        return .unavailable(errors.first ?? "Codex usage could not be read")
    }

    private func publish(_ limits: CodexAccountRateLimits) {
        pendingFailure?.cancel()
        pendingFailure = nil
        pendingFailureID = nil
        successfulReadGeneration &+= 1
        let observedAt = now()
        lastAvailableWindows = limits.windows
        lastAvailableAt = observedAt
        guard let limit = limits.weeklyLimit else {
            publish(.availableWindows(limits.windows))
            return
        }
        let samples = (try? historyStore.observe(limit, at: observedAt))
            ?? historyStore.currentWindowSamples(for: limit)
        let overview = CodexUsageEstimator.overview(
            limit: limit,
            samples: samples,
            windows: limits.windows,
            now: observedAt
        )
        publish(.available(overview))
    }

    private func publishUnavailable(
        _ message: String,
        unlessSucceededAfter generationAtStart: UInt64,
        notBefore alternateReadDeadline: DispatchTime
    ) {
        guard successfulReadGeneration == generationAtStart else { return }
        let concise = message.split(whereSeparator: \.isNewline).first.map(String.init)
            ?? "Codex usage could not be read"
        let boundedMessage = String(concise.prefix(180))
        let failureState: CodexUsageState
        if let windows = lastAvailableWindows, let observedAt = lastAvailableAt {
            failureState = .stale(
                windows: windows,
                observedAt: observedAt,
                message: boundedMessage
            )
        } else {
            failureState = .unavailable(message: boundedMessage)
        }

        let failureID = UUID()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingFailureID == failureID,
                  self.successfulReadGeneration == generationAtStart
            else { return }
            self.pendingFailure = nil
            self.pendingFailureID = nil
            self.publish(failureState)
        }
        pendingFailure = work
        pendingFailureID = failureID
        queue.asyncAfter(deadline: alternateReadDeadline, execute: work)
    }

    private func publish(_ state: CodexUsageState) {
        DispatchQueue.main.async { [weak self] in self?.onChange?(state) }
    }
}
