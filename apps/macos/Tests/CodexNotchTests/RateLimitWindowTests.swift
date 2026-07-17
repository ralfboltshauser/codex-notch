import AppKit
import XCTest
@testable import CodexNotchApp

final class RateLimitWindowTests: CodexNotchTestCase {
    private let fiveHourReset = Date(timeIntervalSince1970: 1_784_520_000)
    private let sevenDayReset = Date(timeIntervalSince1970: 1_784_900_000)

    func testParserKeepsPrimaryAndSecondaryAccountWindowsWithHonestLabels() throws {
        let limits = try XCTUnwrap(
            CodexRateLimitParser.accountLimits(from: dualWindowResponse())
        )

        XCTAssertEqual(limits.windows.map(\.durationLabel), ["5h", "7d"])
        XCTAssertEqual(limits.windows.map(\.remainingPercent), [0, 54])
        XCTAssertEqual(limits.windows.map(\.resetsAt), [fiveHourReset, sevenDayReset])
        XCTAssertTrue(limits.windows[0].isReached)
        XCTAssertFalse(limits.windows[1].isReached)
        XCTAssertEqual(limits.weeklyLimit?.remainingPercent, 54)
        XCTAssertEqual(limits.weeklyLimit?.resetsAt, sevenDayReset)
    }

    func testMonitorPersistsAndForecastsOnlyTheSevenDayWindow() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CodexUsageHistoryStore(
            fileURL: directory.appendingPathComponent("usage-history.json")
        )
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let monitor = CodexUsageMonitor(
            historyStore: history,
            now: { now },
            availableExecutables: { [] }
        )
        let available = expectation(description: "Both account windows are available")
        var received: CodexUsageOverview?
        monitor.onChange = { state in
            guard case .available(let overview) = state else { return }
            received = overview
            available.fulfill()
        }

        monitor.acceptRateLimitResponse(dualWindowResponse())
        wait(for: [available], timeout: 2)
        monitor.stop()

        let overview = try XCTUnwrap(received)
        XCTAssertEqual(overview.windows.map(\.durationLabel), ["5h", "7d"])
        XCTAssertEqual(overview.limit.remainingPercent, 54)
        XCTAssertEqual(history.storedSamples.map(\.remainingPercent), [54])
        XCTAssertEqual(history.storedSamples.map(\.resetsAt), [sevenDayReset])
        guard case .learning = overview.forecast else {
            return XCTFail("The seven-day history should own the forecast")
        }
    }

    func testShortWindowRemainsVisibleWithoutEnteringWeeklyHistory() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = CodexUsageHistoryStore(
            fileURL: directory.appendingPathComponent("usage-history.json")
        )
        let monitor = CodexUsageMonitor(
            historyStore: history,
            availableExecutables: { [] }
        )
        let available = expectation(description: "Short account window is available")
        var received: [CodexRateLimitWindow]?
        monitor.onChange = { state in
            guard case .availableWindows(let windows) = state else { return }
            received = windows
            available.fulfill()
        }

        monitor.acceptRateLimitResponse(Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex",
          "primary":{"usedPercent":20,"windowDurationMins":300,"resetsAt":1784520000},
          "secondary":null
        }}}
        """.utf8))
        wait(for: [available], timeout: 2)
        monitor.stop()

        let windows = try XCTUnwrap(received)
        XCTAssertEqual(windows.map(\.durationLabel), ["5h"])
        XCTAssertEqual(windows.map(\.remainingPercent), [80])
        XCTAssertTrue(history.storedSamples.isEmpty)
    }

    func testHeaderStacksBothWindowsAndNamesReachedState() throws {
        _ = NSApplication.shared
        let limits = try XCTUnwrap(
            CodexRateLimitParser.accountLimits(from: dualWindowResponse())
        )
        let weekly = try XCTUnwrap(limits.weeklyLimit)
        let overview = CodexUsageOverview(
            limit: weekly,
            forecast: .learning(observedFor: 0),
            recentTrend: nil,
            windows: limits.windows
        )
        let view = WeeklyUsageHeaderView(
            state: .available(overview),
            theme: NotchTheme.all[0],
            refresh: {}
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 22))
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.valueTextForTesting, "5h reached\n7d 54%")
        XCTAssertTrue(view.valueFitsWithoutTruncationForTesting)
        XCTAssertTrue(view.toolTip?.contains("5h Codex limit reached.") == true)
        XCTAssertTrue(
            view.toolTip?.contains("You have 54% of your weekly Codex limit remaining.") == true
        )
        XCTAssertEqual(view.frame.height, 22, accuracy: 0.1)
        XCTAssertFalse(view.hasAmbiguousLayout)
    }

    private func dualWindowResponse() -> Data {
        Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex",
          "primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":1784520000},
          "secondary":{"usedPercent":46,"windowDurationMins":10080,"resetsAt":1784900000}
        }}}
        """.utf8)
    }
}
