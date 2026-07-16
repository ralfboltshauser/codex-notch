import AppKit
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class CodexUsageTests: CodexNotchTestCase {
    func testRateLimitParserReadsMainSevenDayWindowAsRemainingUsage() throws {
        let response = Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex",
          "primary":{"usedPercent":37,"windowDurationMins":10080,"resetsAt":1784487540},
          "secondary":null
        },"rateLimitsByLimitId":null}}
        """.utf8)

        let limit = try XCTUnwrap(CodexRateLimitParser.weeklyLimit(from: response))

        XCTAssertEqual(limit.remainingPercent, 63)
        XCTAssertEqual(limit.resetsAt, Date(timeIntervalSince1970: 1_784_487_540))
    }

    func testRateLimitParserFindsWeeklyWindowByDurationNotFieldName() throws {
        let response = Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex",
          "primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1784000000},
          "secondary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":1784600000}
        }}}
        """.utf8)

        XCTAssertEqual(
            try XCTUnwrap(CodexRateLimitParser.weeklyLimit(from: response)).remainingPercent,
            54
        )
    }

    func testRateLimitParserPrefersMainCodexBucketOverModelSpecificBuckets() throws {
        let response = Data("""
        {"id":2,"result":{
          "rateLimits":{"limitId":"codex","primary":{"usedPercent":40,"windowDurationMins":10080}},
          "rateLimitsByLimitId":{
            "codex_bengalfox":{"limitId":"codex_bengalfox","primary":{"usedPercent":90,"windowDurationMins":10080}},
            "codex":{"limitId":"codex","primary":{"usedPercent":40,"windowDurationMins":10080}}
          }
        }}
        """.utf8)

        XCTAssertEqual(
            try XCTUnwrap(CodexRateLimitParser.weeklyLimit(from: response)).remainingPercent,
            60
        )
    }

    func testRateLimitParserNeverTreatsAContextBucketAsTheWeeklyAccountLimit() {
        let response = Data("""
        {"id":2,"result":{
          "rateLimits":{
            "limitId":"context","limitName":"Current task context",
            "primary":{"usedPercent":91,"windowDurationMins":10080,"resetsAt":1784600000}
          },
          "rateLimitsByLimitId":{
            "context":{
              "limitId":"context","limitName":"Current task context",
              "primary":{"usedPercent":91,"windowDurationMins":10080,"resetsAt":1784600000}
            }
          }
        }}
        """.utf8)

        XCTAssertNil(CodexRateLimitParser.weeklyLimit(from: response))
    }

    func testRateLimitParserSelectsAccountWeeklyLimitAlongsideContextData() throws {
        let response = Data("""
        {"id":2,"result":{
          "contextWindow":{"remainingPercent":9},
          "rateLimits":{"limitId":"context","primary":{"usedPercent":91,"windowDurationMins":10080}},
          "rateLimitsByLimitId":{
            "context":{"limitId":"context","primary":{"usedPercent":91,"windowDurationMins":10080}},
            "codex":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":10080}}
          }
        }}
        """.utf8)

        XCTAssertEqual(
            try XCTUnwrap(CodexRateLimitParser.weeklyLimit(from: response)).remainingPercent,
            88
        )
    }

    func testRateLimitParserDoesNotMislabelShortWindowAsWeekly() {
        let response = Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300}
        }}}
        """.utf8)

        XCTAssertNil(CodexRateLimitParser.weeklyLimit(from: response))
    }

    func testRateLimitParserDoesNotSilentlyTruncateAChangedPrecisionContract() {
        let response = Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex","primary":{"usedPercent":20.5,"windowDurationMins":10080}
        }}}
        """.utf8)

        XCTAssertNil(CodexRateLimitParser.weeklyLimit(from: response))
    }

    func testCodexExecutableCandidatesCoverMacAppAndUserCLIInstalls() {
        let paths = CodexExecutableLocator.candidates(
            homeDirectory: URL(fileURLWithPath: "/Users/ralf"),
            environment: ["PATH": "/custom/bin:/opt/homebrew/bin"]
        ).map(\.path)

        XCTAssertTrue(paths.contains("/Applications/Codex.app/Contents/Resources/codex"))
        XCTAssertTrue(paths.contains("/Applications/ChatGPT.app/Contents/Resources/codex"))
        XCTAssertTrue(paths.contains(
            "/Users/ralf/Applications/Codex.app/Contents/Resources/codex"
        ))
        XCTAssertTrue(paths.contains(
            "/Users/ralf/Applications/ChatGPT.app/Contents/Resources/codex"
        ))
        XCTAssertTrue(paths.contains("/Users/ralf/.local/bin/codex"))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(paths.contains("/custom/bin/codex"))
        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/bin/codex" }.count, 1)
    }

    func testAvailableExecutablesDeduplicateSymlinksToTheSameCodexBinary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("real-codex")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )
        let firstBin = directory.appendingPathComponent("first/bin")
        let secondBin = directory.appendingPathComponent("second/bin")
        try FileManager.default.createDirectory(
            at: firstBin,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondBin,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: firstBin.appendingPathComponent("codex"),
            withDestinationURL: executable
        )
        try FileManager.default.createSymbolicLink(
            at: secondBin.appendingPathComponent("codex"),
            withDestinationURL: executable
        )

        let available = CodexExecutableLocator.availableExecutables(
            homeDirectory: directory,
            environment: ["PATH": "\(firstBin.path):\(secondBin.path)"]
        )

        XCTAssertEqual(available.filter { $0 == executable }.count, 1)
    }

    func testUsageMonitorReportsWhyUsageCannotLoadInsteadOfPublishingNothing() {
        let monitor = CodexUsageMonitor(availableExecutables: { [] })
        let unavailable = expectation(description: "Usage failure is visible")
        var state: CodexUsageState?
        monitor.onChange = { update in
            guard case .unavailable = update else { return }
            state = update
            unavailable.fulfill()
        }

        monitor.refresh()
        wait(for: [unavailable], timeout: 2)
        monitor.stop()

        XCTAssertEqual(state, .unavailable(message: "Codex app or CLI was not found"))
    }

    func testRefreshKeepsFailureVisibleInsteadOfReturningToLoadingDots() {
        let monitor = CodexUsageMonitor(availableExecutables: { [] })
        var states: [CodexUsageState] = []
        var unavailableCount = 0
        let first = expectation(description: "First usage failure")
        let second = expectation(description: "Second usage failure")
        monitor.onChange = { state in
            states.append(state)
            guard case .unavailable = state else { return }
            unavailableCount += 1
            (unavailableCount == 1 ? first : second).fulfill()
        }

        monitor.refresh()
        wait(for: [first], timeout: 2)
        let secondRefreshStart = states.count
        monitor.refresh()
        wait(for: [second], timeout: 2)
        monitor.stop()

        XCTAssertFalse(states.dropFirst(secondRefreshStart).contains(.loading))
    }

    func testUsageMonitorReadsWeeklyLimitFromRunningAppServerSocket() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fakeClient = FakeAppServerSocketClient()
        let observer = AppServerObserver(
            socketCandidates: { ["/tmp/fake-codex.sock"] },
            pathExists: { _ in true },
            clientFactory: { _, _ in fakeClient }
        )
        let monitor = CodexUsageMonitor(
            historyStore: CodexUsageHistoryStore(
                fileURL: directory.appendingPathComponent("usage-history.json")
            ),
            availableExecutables: { [] }
        )
        monitor.onRefreshRequested = { observer.requestUsage() }
        observer.onRateLimits = { monitor.acceptRateLimitResponse($0) }
        let available = expectation(description: "Live app-server usage is available")
        var remainingPercent: Int?
        monitor.onChange = { state in
            guard case .available(let overview) = state else { return }
            remainingPercent = overview.limit.remainingPercent
            available.fulfill()
        }

        observer.start()
        monitor.refresh()
        wait(for: [available], timeout: 2)
        observer.stop()
        monitor.stop()

        XCTAssertEqual(remainingPercent, 63)
        XCTAssertTrue(fakeClient.sentMethods.contains("account/rateLimits/read"))
    }

    func testAppServerClientCompletesHandshakeWithoutClosingStandardInput() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        try Data("""
        #!/bin/sh
        while IFS= read -r line; do
          case "$line" in
            *rateLimits*)
              printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":37,"windowDurationMins":10080}}}}'
              exit 0
              ;;
          esac
        done
        """.utf8).write(to: executable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: executable.path
        )

        let response = try CodexAppServerClient(timeout: 2).readRateLimits(executable: executable)

        XCTAssertEqual(
            try XCTUnwrap(CodexRateLimitParser.weeklyLimit(from: response)).remainingPercent,
            63
        )
    }

    func testUsageForecastWaitsForAnHourAndTwoPointChange() {
        XCTAssertEqual(CodexUsageMonitor.refreshInterval, 15 * 60)
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let reset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let limit = CodexWeeklyLimit(remainingPercent: 50, resetsAt: reset)

        let shortObservation = CodexUsageEstimator.overview(
            limit: limit,
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-30 * 60),
                remainingPercent: 53,
                resetsAt: reset
            )],
            now: now
        )
        let quantizedObservation = CodexUsageEstimator.overview(
            limit: limit,
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-2 * 60 * 60),
                remainingPercent: 51,
                resetsAt: reset
            )],
            now: now
        )

        guard case .learning = shortObservation.forecast else {
            return XCTFail("A short observation must not produce an ETA")
        }
        guard case .learning = quantizedObservation.forecast else {
            return XCTFail("A one-point change is within the source's integer uncertainty")
        }
    }

    func testUsageForecastProjectsExhaustionFromMeaningfulRecentTrend() throws {
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let reset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let overview = CodexUsageEstimator.overview(
            limit: CodexWeeklyLimit(remainingPercent: 20, resetsAt: reset),
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-4 * 60 * 60),
                remainingPercent: 30,
                resetsAt: reset
            )],
            now: now
        )

        guard case let .exhausts(estimatedAt, pacePerDay) = overview.forecast else {
            return XCTFail("Expected an exhaustion forecast")
        }
        XCTAssertEqual(estimatedAt.timeIntervalSince(now), 8 * 60 * 60, accuracy: 0.1)
        XCTAssertEqual(pacePerDay, 60, accuracy: 0.01)
        XCTAssertEqual(overview.recentTrend?.usedPercent, 10)
        XCTAssertEqual(overview.recentTrend?.observedFor, 4 * 60 * 60)
    }

    func testUsageForecastDistinguishesSafeAndUncertainResetCrossings() {
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let safeReset = now.addingTimeInterval(48 * 60 * 60)
        let safe = CodexUsageEstimator.overview(
            limit: CodexWeeklyLimit(remainingPercent: 80, resetsAt: safeReset),
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-4 * 60 * 60),
                remainingPercent: 82,
                resetsAt: safeReset
            )],
            now: now
        )
        guard case .lastsThroughReset = safe.forecast else {
            return XCTFail("Even the fastest plausible pace lasts beyond the reset")
        }

        let uncertainReset = now.addingTimeInterval(24 * 60 * 60)
        let uncertain = CodexUsageEstimator.overview(
            limit: CodexWeeklyLimit(remainingPercent: 10, resetsAt: uncertainReset),
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-4 * 60 * 60),
                remainingPercent: 12,
                resetsAt: uncertainReset
            )],
            now: now
        )
        guard case .nearReset = uncertain.forecast else {
            return XCTFail("A reset inside the integer uncertainty range must stay qualified")
        }
    }

    func testUsageForecastReportsQuietAndRestartsAfterCapacityIncrease() {
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let reset = now.addingTimeInterval(7 * 24 * 60 * 60)
        let quiet = CodexUsageEstimator.overview(
            limit: CodexWeeklyLimit(remainingPercent: 80, resetsAt: reset),
            samples: [CodexUsageSample(
                recordedAt: now.addingTimeInterval(-4 * 60 * 60),
                remainingPercent: 80,
                resetsAt: reset
            )],
            now: now
        )
        guard case .quiet = quiet.forecast else {
            return XCTFail("An unchanged multi-hour observation should report quiet usage")
        }

        let resetWithoutTimestampChange = CodexUsageEstimator.overview(
            limit: CodexWeeklyLimit(remainingPercent: 80, resetsAt: reset),
            samples: [
                CodexUsageSample(
                    recordedAt: now.addingTimeInterval(-4 * 60 * 60),
                    remainingPercent: 70,
                    resetsAt: reset
                ),
                CodexUsageSample(
                    recordedAt: now.addingTimeInterval(-2 * 60 * 60),
                    remainingPercent: 60,
                    resetsAt: reset
                ),
            ],
            now: now
        )
        guard case .learning = resetWithoutTimestampChange.forecast else {
            return XCTFail("A capacity increase must discard the stale downward trend")
        }
    }

    func testUsageHistoryPersistsChangesAndHourlyFlatCheckpoints() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("usage-history.json")
        let reset = Date(timeIntervalSince1970: 1_785_000_000)
        let start = Date(timeIntervalSince1970: 1_784_500_000)
        let store = CodexUsageHistoryStore(fileURL: file)

        try store.observe(CodexWeeklyLimit(remainingPercent: 90, resetsAt: reset), at: start)
        let transient = try store.observe(
            CodexWeeklyLimit(remainingPercent: 90, resetsAt: reset),
            at: start.addingTimeInterval(15 * 60)
        )
        try store.observe(
            CodexWeeklyLimit(remainingPercent: 89, resetsAt: reset),
            at: start.addingTimeInterval(30 * 60)
        )
        try store.observe(
            CodexWeeklyLimit(remainingPercent: 89, resetsAt: reset),
            at: start.addingTimeInterval(91 * 60)
        )

        XCTAssertEqual(transient.count, 2, "Fresh checks feed the forecast without bloating disk history")
        XCTAssertEqual(store.storedSamples.map(\.remainingPercent), [90, 89, 89])
        XCTAssertEqual(CodexUsageHistoryStore(fileURL: file).storedSamples, store.storedSamples)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testUsageHistoryPrunesSamplesOutsideEightWeekRetention() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CodexUsageHistoryStore(
            fileURL: directory.appendingPathComponent("usage-history.json")
        )
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        let later = start.addingTimeInterval(CodexUsageHistoryStore.retentionInterval + 60)

        try store.observe(
            CodexWeeklyLimit(remainingPercent: 90, resetsAt: start.addingTimeInterval(86_400)),
            at: start
        )
        try store.observe(
            CodexWeeklyLimit(remainingPercent: 100, resetsAt: later.addingTimeInterval(86_400)),
            at: later
        )

        XCTAssertEqual(store.storedSamples.count, 1)
        XCTAssertEqual(store.storedSamples.first?.recordedAt, later)
    }
}

private final class FakeAppServerSocketClient: AppServerSocketClient {
    var onText: ((Data) -> Void)?
    var onClose: (() -> Void)?

    private let lock = NSLock()
    private var messages: [[String: Any]] = []

    var sentMethods: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages.compactMap { $0["method"] as? String }
    }

    func start() throws {}

    func send(json: [String: Any]) throws {
        lock.lock()
        messages.append(json)
        lock.unlock()

        guard let method = json["method"] as? String else { return }
        if method == "initialize" {
            onText?(Data("{\"id\":1,\"result\":{}}".utf8))
        } else if method == "account/rateLimits/read",
                  let id = json["id"] as? Int {
            onText?(Data("""
            {"id":\(id),"result":{"rateLimits":{
              "limitId":"codex",
              "primary":{"usedPercent":37,"windowDurationMins":10080}
            }}}
            """.utf8))
        }
    }

    func close() {}
}
