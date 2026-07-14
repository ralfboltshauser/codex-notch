import XCTest
import AppKit
@testable import NtfyCodexOverlay

final class NtfyCodexOverlayTests: XCTestCase {
    private let threadID = "019f5d4f-3a8d-76c0-8c2d-19451190e028"

    func testParsesRealNotificationShape() throws {
        let data = Data("""
        {
          "id":"event-1",
          "time":1783976966,
          "event":"message",
          "title":"Codex finished: which deep links does codex support?",
          "click":"codex://threads/\(threadID)",
          "actions":[{"action":"view","url":"codex://threads/\(threadID)"}]
        }
        """.utf8)
        let task = try XCTUnwrap(NtfyEventParser.task(from: data))
        XCTAssertEqual(task.title, "which deep links does codex support?")
        XCTAssertEqual(task.eventID, "event-1")
    }

    func testFallsBackToViewAction() {
        let data = Data("""
        {"id":"e","event":"message","title":"Task", "actions":[
          {"action":"view","url":"codex://threads/\(threadID)"}
        ]}
        """.utf8)
        XCTAssertNotNil(NtfyEventParser.task(from: data))
    }

    func testRejectsUnsafeAndMalformedLinks() {
        let values = [
            "https://example.com",
            "file:///etc/passwd",
            "codex://threads/not-a-uuid",
            "codex://threads/\(threadID)?extra=true",
            "codex://other/\(threadID)",
        ]
        for value in values {
            XCTAssertNil(NtfyEventParser.validCodexThreadURL(value), value)
        }
    }

    func testNormalizesTopicAndPreservesAuthQueryForSubscription() throws {
        let topic = try XCTUnwrap(AppConfiguration.normalizedTopicURL(
            from: "  https://ntfy.example.com/my-topic/json?auth=secret  "
        ))
        XCTAssertEqual(topic.absoluteString, "https://ntfy.example.com/my-topic?auth=secret")
        let configuration = AppConfiguration(topicURL: topic)
        let subscription = try XCTUnwrap(configuration.subscriptionURL(parameters: [
            "poll": "1", "since": "latest",
        ]))
        let components = try XCTUnwrap(URLComponents(url: subscription, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/my-topic/json")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) }), [
            "auth": "secret", "poll": "1", "since": "latest",
        ])
        XCTAssertNil(AppConfiguration.normalizedTopicURL(from: "http://ntfy.example.com/topic"))
    }

    func testHookInstallerMergesWithoutOverwritingExistingHooks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hook-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let hooksFile = directory.appendingPathComponent("hooks.json")
        let existing: [String: Any] = [
            "hooks": [
                "PostToolUse": [["matcher": "Bash", "hooks": [[
                    "type": "command", "command": "/existing-hook",
                ]]]],
                "Stop": [["hooks": [["type": "command", "command": "/existing-stop"]]]],
            ],
        ]
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksFile)
        let executable = directory.appendingPathComponent("App With Spaces")
        let installer = CodexHookInstaller(hooksFile: hooksFile, executableURL: executable)
        try installer.install()

        XCTAssertTrue(installer.isInstalled)
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile)) as? [String: Any]
        )
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PostToolUse"])
        let stop = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        XCTAssertEqual(stop.count, 2)
        let newCommand = ((stop.last?["hooks"] as? [[String: Any]])?.first?["command"] as? String)
        XCTAssertEqual(newCommand, "'\(executable.path)' --codex-hook")

        try installer.install()
        let secondRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile)) as? [String: Any]
        )
        let secondStop = ((secondRoot["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        XCTAssertEqual(secondStop?.count, 2, "Reinstall must replace, not duplicate, our hook")

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled)
        let finalRoot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: hooksFile)) as? [String: Any]
        )
        let finalHooks = try XCTUnwrap(finalRoot["hooks"] as? [String: Any])
        XCTAssertNotNil(finalHooks["PostToolUse"])
        XCTAssertEqual((finalHooks["Stop"] as? [[String: Any]])?.count, 1)
    }

    func testHookPayloadContainsOnlySafeThreadAction() throws {
        let payload = CodexStopHook.notificationPayload(
            sessionID: threadID,
            title: "Build the overlay"
        )
        XCTAssertEqual(payload["title"] as? String, "Codex finished: Build the overlay")
        XCTAssertEqual(payload["click"] as? String, "codex://threads/\(threadID)")
        let action = try XCTUnwrap((payload["actions"] as? [[String: Any]])?.first)
        XCTAssertEqual(action["action"] as? String, "view")
        XCTAssertEqual(action["url"] as? String, payload["click"] as? String)

        let request = CodexStopHook.publishRequest(
            sessionID: threadID,
            title: "Build Zürich overlay",
            topicURL: URL(string: "https://ntfy.example/topic")!
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "Task finished")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Click"), "codex://threads/\(threadID)")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Actions"),
            "view, Open Codex task, codex://threads/\(threadID), clear=true"
        )
        XCTAssertTrue(request.value(forHTTPHeaderField: "Title")!.hasPrefix("=?UTF-8?B?"))
    }

    func testOverlayUsesWideFixedBodyWithoutGrowingForLongTitles() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        let task = CompletedTask(
            eventID: "visual-test",
            title: String(repeating: "A very long finished task title ", count: 8),
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        overlay.update(tasks: [])
        overlay.update(tasks: [task])
        XCTAssertEqual(overlay.bodyWidthForTesting, 820, accuracy: 0.5)
        XCTAssertGreaterThan(overlay.frameForTesting.width, overlay.bodyWidthForTesting)
        XCTAssertEqual(overlay.bodyHeightForTesting, 106, accuracy: 0.5)
        XCTAssertEqual(overlay.eventVisibilityDurationForTesting, 5)
    }

    func testShortcutTogglePinsUntilExplicitlyClosed() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        overlay.update(tasks: [CompletedTask(
            eventID: "toggle-test",
            title: "A persistent task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])

        overlay.toggle()
        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)

        overlay.toggle()
        XCTAssertFalse(overlay.isPinnedForTesting)
    }

    func testEventPresentationUsesAutoHideTimer() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        overlay.update(tasks: [CompletedTask(
            eventID: "event-test",
            title: "A transient task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])

        overlay.showForEvent()
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.hasHideTimerForTesting)
        overlay.hide(immediately: true)
    }

    func testOverlayShapeFlowsFromScreenEdgeIntoBody() throws {
        _ = NSApplication.shared
        let overlay = OverlayController()
        overlay.update(tasks: [
            "ralf",
            "Respond to greeting",
            "Do the things you can do for the first 3 frames and show me before and…",
        ].enumerated().map { index, title in
            CompletedTask(
                eventID: "shape-test-\(index)",
                title: title,
                url: URL(string: "codex://threads/\(threadID)")!,
                receivedAt: Date()
            )
        })

        let view = try XCTUnwrap(overlay.contentViewForTesting)
        view.layoutSubtreeIfNeeded()
        let path = try XCTUnwrap((view.layer?.mask as? CAShapeLayer)?.path)
        XCTAssertTrue(path.contains(CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 1)))
        XCTAssertTrue(path.contains(CGPoint(x: 20, y: view.bounds.maxY - 1)))
        XCTAssertFalse(path.contains(CGPoint(x: 1, y: view.bounds.maxY - 36)))
        XCTAssertTrue(path.contains(CGPoint(x: view.bounds.midX, y: 1)))

        XCTAssertTrue(view.layer?.sublayers?.isEmpty ?? true, "The HUD must have no border layer")
        let background = try XCTUnwrap(view.layer?.backgroundColor)
        let rgb = try XCTUnwrap(NSColor(cgColor: background)?.usingColorSpace(.deviceRGB))
        XCTAssertEqual(rgb.redComponent, 0, accuracy: 0.000_001)
        XCTAssertEqual(rgb.greenComponent, 0, accuracy: 0.000_001)
        XCTAssertEqual(rgb.blueComponent, 0, accuracy: 0.000_001)
        XCTAssertEqual(rgb.alphaComponent, 1, accuracy: 0.000_001)
        XCTAssertEqual(view.layer?.opacity, 1)

        overlay.toggle()
        XCTAssertEqual(overlay.panelAlphaForTesting, 1, accuracy: 0.000_001)
        overlay.hide(immediately: true)

        if let snapshotPath = ProcessInfo.processInfo.environment["OVERLAY_SNAPSHOT_PATH"],
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: snapshotPath))
        }
    }

    func testQueueKeepsLatestNineAndRemovesDuplicateThread() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskStore(defaults: defaults)
        for index in 0..<10 {
            store.add(CompletedTask(
                eventID: "e\(index)",
                title: "Task \(index)",
                url: URL(string: "codex://threads/00000000-0000-0000-0000-00000000000\(index)")!,
                receivedAt: Date()
            ))
        }
        XCTAssertEqual(store.tasks.count, 9)
        XCTAssertEqual(store.tasks.first?.title, "Task 9")

        let sameThread = CompletedTask(
            eventID: "new-event",
            title: "Updated task",
            url: store.tasks[1].url,
            receivedAt: Date()
        )
        store.add(sameThread)
        XCTAssertEqual(store.tasks.count, 9)
        XCTAssertEqual(store.tasks.first?.title, "Updated task")
    }
}
