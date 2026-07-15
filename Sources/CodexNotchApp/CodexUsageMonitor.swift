import Darwin
import Foundation

struct CodexWeeklyLimit: Equatable {
    static let weeklyWindowMinutes = 7 * 24 * 60

    let remainingPercent: Int
    let resetsAt: Date?
}

enum CodexRateLimitParser {
    static func weeklyLimit(from response: Data) -> CodexWeeklyLimit? {
        guard let root = try? JSONSerialization.jsonObject(with: response) as? [String: Any],
              let result = root["result"] as? [String: Any]
        else { return nil }

        var snapshots: [[String: Any]] = []
        if let byID = result["rateLimitsByLimitId"] as? [String: Any],
           let codex = byID["codex"] as? [String: Any] {
            snapshots.append(codex)
        }
        if let historical = result["rateLimits"] as? [String: Any],
           snapshots.isEmpty || historical["limitId"] as? String == "codex" {
            snapshots.append(historical)
        }

        for snapshot in snapshots {
            for key in ["primary", "secondary"] {
                guard let window = snapshot[key] as? [String: Any],
                      integer(window["windowDurationMins"]) == CodexWeeklyLimit.weeklyWindowMinutes,
                      let usedPercent = integer(window["usedPercent"])
                else { continue }

                let clampedUsage = min(100, max(0, usedPercent))
                let resetsAt = integer(window["resetsAt"]).map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                }
                return CodexWeeklyLimit(
                    remainingPercent: 100 - clampedUsage,
                    resetsAt: resetsAt
                )
            }
        }
        return nil
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
        candidates(homeDirectory: homeDirectory, environment: environment).filter {
            fileManager.isExecutableFile(atPath: $0.path)
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

    var onChange: ((CodexUsageOverview?) -> Void)?

    private let queue = DispatchQueue(label: "com.ralfbuilds.codex-notch.usage", qos: .utility)
    private let client: CodexAppServerClient
    private let historyStore: CodexUsageHistoryStore
    private let now: () -> Date
    private var timer: DispatchSourceTimer?
    private var isRefreshing = false

    init(
        client: CodexAppServerClient = CodexAppServerClient(),
        historyStore: CodexUsageHistoryStore = CodexUsageHistoryStore(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.historyStore = historyStore
        self.now = now
    }

    func start() {
        queue.async { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(
                deadline: .now(),
                repeating: Self.refreshInterval,
                leeway: .seconds(15)
            )
            timer.setEventHandler { [weak self] in self?.performRefresh() }
            self.timer = timer
            timer.resume()
        }
    }

    func refresh() {
        queue.async { [weak self] in self?.performRefresh() }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    private func performRefresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var receivedResponse = false
        for executable in CodexExecutableLocator.availableExecutables() {
            guard let response = try? client.readRateLimits(executable: executable) else { continue }
            receivedResponse = true
            if let limit = CodexRateLimitParser.weeklyLimit(from: response) {
                let observedAt = now()
                let samples = (try? historyStore.observe(limit, at: observedAt))
                    ?? historyStore.currentWindowSamples(for: limit)
                publish(CodexUsageEstimator.overview(
                    limit: limit,
                    samples: samples,
                    now: observedAt
                ))
                return
            }
        }
        if receivedResponse { publish(nil) }
    }

    private func publish(_ overview: CodexUsageOverview?) {
        DispatchQueue.main.async { [weak self] in self?.onChange?(overview) }
    }
}
