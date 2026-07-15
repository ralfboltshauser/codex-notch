import AppKit
import Carbon
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class HookAndTaskModelTests: CodexNotchTestCase {
    func testEventIDMatchesRemoteImplementation() {
        XCTAssertEqual(
            CompletionEvent.eventID(threadID: threadID, turnID: "turn-1"),
            "e0b98fc8f63e72f945615d03770fda0d3e1063f35217213afa86783953b844bc"
        )
    }

    func testEventEncodingUsesWireKeysAndBuildsURLLocally() throws {
        let event = makeEvent()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.codexNotch.encode(event)) as? [String: Any]
        )
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["thread_id"] as? String, threadID)
        XCTAssertNil(object["url"])

        let task = try XCTUnwrap(CompletedTask(event: event))
        XCTAssertEqual(task.url.absoluteString, "codex://threads/\(threadID)")
    }

    func testRejectsMalformedCompletionEvents() {
        let event = CompletionEvent(
            eventID: "../unsafe",
            threadID: threadID,
            turnID: "turn-1",
            title: "Task",
            sourceID: "local",
            sourceLabel: "This Mac",
            completedAt: Date()
        )
        XCTAssertFalse(event.isValid)
        XCTAssertNil(CompletedTask(event: event))
    }

    func testLocalHookWritesContentAddressedEvent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let event = makeEvent()
        try LocalHookRunner.write(event, inbox: directory)
        let file = directory.appendingPathComponent(event.eventID).appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let decoded = try JSONDecoder.codexNotch.decode(
            CompletionEvent.self,
            from: Data(contentsOf: file)
        )
        XCTAssertEqual(decoded, event)
    }

    func testHookInstallerPreservesOtherHooksAndIsIdempotent() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hooksFile = directory.appendingPathComponent("hooks.json")
        let executable = directory.appendingPathComponent("Hook With Spaces")
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let existing: [String: Any] = ["hooks": [
            "PostToolUse": [["hooks": [["type": "command", "command": "/other"]]]],
            "Stop": [["hooks": [["type": "command", "command": "/existing-stop"]]]],
        ]]
        try JSONSerialization.data(withJSONObject: existing).write(to: hooksFile)
        let installer = CodexHookInstaller(hooksFile: hooksFile, executableURL: executable)

        try installer.install()
        try installer.install()
        let root = try hooksRoot(at: hooksFile)
        let hooks = try XCTUnwrap(root["hooks"] as? [String: Any])
        XCTAssertNotNil(hooks["PostToolUse"])
        let groups = try XCTUnwrap(hooks["Stop"] as? [[String: Any]])
        let commands = groups.flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        XCTAssertEqual(commands.filter { $0.contains(CodexHookInstaller.marker) }.count, 1)
        XCTAssertTrue(commands.contains("/existing-stop"))
        XCTAssertTrue(installer.hasOwnedInstallation)
        XCTAssertFalse(installer.needsRepair)
        XCTAssertFalse(installer.isTrusted)
        XCTAssertEqual(
            installer.localHostHealth,
            .needsAttention(message: "Local completion hook still needs trust")
        )
        let movedInstaller = CodexHookInstaller(
            hooksFile: hooksFile,
            executableURL: directory.appendingPathComponent("Moved Hook")
        )
        XCTAssertTrue(movedInstaller.hasOwnedInstallation)
        XCTAssertTrue(movedInstaller.needsRepair)
        let configFile = directory.appendingPathComponent("config.toml")
        let ownedStateKey = "\(hooksFile.path):stop:1:0"
        try Data("""
        [hooks.state]

        [hooks.state."\(ownedStateKey)"]
        trusted_hash = "sha256:owned"

        [hooks.state."plugin:unrelated"]
        trusted_hash = "sha256:unrelated"
        """.utf8).write(to: configFile)

        XCTAssertTrue(installer.isTrusted)
        XCTAssertEqual(installer.localHostHealth, .working)
        XCTAssertFalse(movedInstaller.isTrusted)

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled)
        XCTAssertFalse(installer.isTrusted)
        let final = try hooksRoot(at: hooksFile)
        let finalHooks = try XCTUnwrap(final["hooks"] as? [String: Any])
        XCTAssertNotNil(finalHooks["PostToolUse"])
        let backup = try hooksRoot(at: hooksFile.appendingPathExtension("bak"))
        let backupCommands = (((backup["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]]) ?? [])
            .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
            .compactMap { $0["command"] as? String }
        XCTAssertFalse(backupCommands.contains { $0.contains(CodexHookInstaller.marker) })
        let config = try String(contentsOf: configFile, encoding: .utf8)
        XCTAssertFalse(config.contains(ownedStateKey))
        XCTAssertTrue(config.contains("plugin:unrelated"))
    }

    func testHookUninstallRemovesLegacyOwnedHookButPreservesOtherHandlers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hooksFile = directory.appendingPathComponent("hooks.json")
        let root: [String: Any] = ["hooks": ["Stop": [["hooks": [
            ["type": "command", "command": "/other --codex-hook"],
            [
                "type": "command",
                "command": "'/Users/test/Applications/Ntfy Codex Overlay.app/Contents/MacOS/NtfyCodexOverlay' --codex-hook",
                "statusMessage": "Sending completion to ntfy",
            ],
        ]]]]]
        try JSONSerialization.data(withJSONObject: root).write(to: hooksFile)

        try CodexHookInstaller(hooksFile: hooksFile, executableURL: directory).uninstall()

        let cleaned = try hooksRoot(at: hooksFile)
        let cleanedHooks = try XCTUnwrap(cleaned["hooks"] as? [String: Any])
        let groups = try XCTUnwrap(cleanedHooks["Stop"] as? [[String: Any]])
        let handlers = try XCTUnwrap(groups.first?["hooks"] as? [[String: Any]])
        let commands = handlers.compactMap { $0["command"] as? String }
        XCTAssertEqual(commands, ["/other --codex-hook"])
    }

    func testTaskStorePersistsLatestTenAndDeduplicates() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: file)
        for index in 0..<11 {
            let id = String(format: "%012d", index)
            let task = CompletedTask(
                eventID: String(format: "%064x", index),
                title: "Task \(index)",
                url: URL(string: "codex://threads/00000000-0000-0000-0000-\(id)")!,
                receivedAt: Date(timeIntervalSince1970: TimeInterval(1_700_000_000 + index))
            )
            XCTAssertTrue(try store.add(task))
        }
        XCTAssertEqual(store.tasks.count, 10)
        XCTAssertEqual(store.tasks.first?.title, "Task 10")
        XCTAssertFalse(try store.add(store.tasks[0]))
        XCTAssertEqual(TaskStore(fileURL: file).tasks, store.tasks)
    }

    func testActiveSnapshotValidationAndWireKeys() throws {
        let snapshot = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 7,
            generatedAt: Date(timeIntervalSince1970: 1_784_035_200),
            tasks: [ActiveTaskEvent(
                threadID: threadID,
                title: "Build active tasks",
                state: .waitingForApproval,
                updatedAt: Date(timeIntervalSince1970: 1_784_035_199)
            )]
        )
        XCTAssertTrue(snapshot.isValid)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.codexNotch.encode(snapshot)) as? [String: Any]
        )
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        let task = try XCTUnwrap((object["tasks"] as? [[String: Any]])?.first)
        XCTAssertEqual(task["state"] as? String, "waiting_for_approval")
        XCTAssertNil(task["cwd"])
        XCTAssertNil(task["prompt"])
    }

    func testActiveStoreReplacesBySourceRejectsStaleSequenceAndExpires() {
        var now = Date(timeIntervalSince1970: 1_784_035_200)
        let store = ActiveTaskStore(now: { now })
        let generation = UUID().uuidString.lowercased()
        func snapshot(sequence: UInt64, title: String) -> ActiveTaskSnapshot {
            ActiveTaskSnapshot(
                generation: generation,
                sequence: sequence,
                generatedAt: now,
                tasks: [ActiveTaskEvent(
                    threadID: threadID,
                    title: title,
                    state: .running,
                    updatedAt: now
                )]
            )
        }
        XCTAssertTrue(store.replace(sourceID: "local", sourceLabel: "This Mac", snapshot: snapshot(sequence: 2, title: "New")))
        XCTAssertFalse(store.replace(sourceID: "local", sourceLabel: "This Mac", snapshot: snapshot(sequence: 1, title: "Old")))
        XCTAssertEqual(store.tasks.first?.title, "New")
        now.addTimeInterval(46)
        XCTAssertEqual(store.tasks.first?.state, .unavailable)
        let replacementGeneration = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: now,
            tasks: []
        )
        XCTAssertTrue(store.replace(sourceID: "local", sourceLabel: "This Mac", snapshot: replacementGeneration))
        XCTAssertFalse(store.replace(sourceID: "local", sourceLabel: "This Mac", snapshot: snapshot(sequence: 3, title: "Late old process")))
        XCTAssertTrue(store.tasks.isEmpty)
        now.addTimeInterval(75)
        store.reapStaleSources()
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testActiveTaskPreferenceDefaultsOnAndToggles() throws {
        let suite = "CodexNotchTests.ActiveTasks.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ActiveTaskPreferences(defaults: defaults)
        XCTAssertTrue(preferences.isVisible)
        XCTAssertFalse(preferences.toggle())
        XCTAssertFalse(ActiveTaskPreferences(defaults: defaults).isVisible)
    }

    func testDoNotDisturbPreferenceDefaultsOffAndPersists() throws {
        let suite = "CodexNotchTests.DoNotDisturb.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let preferences = DoNotDisturbPreferences(defaults: defaults)
        XCTAssertFalse(preferences.isEnabled)
        XCTAssertTrue(preferences.toggle())
        XCTAssertTrue(DoNotDisturbPreferences(defaults: defaults).isEnabled)
    }

    func testAppServerSocketDiscoveryIncludesStableAndRemoteControlSockets() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remoteControl = directory.appendingPathComponent("codex-rc-test")
        try FileManager.default.createDirectory(at: remoteControl, withIntermediateDirectories: true)
        let socket = remoteControl.appendingPathComponent("rc.sock")
        XCTAssertTrue(FileManager.default.createFile(atPath: socket.path, contents: Data()))
        let paths = AppServerObserver.socketCandidates(
            codexHome: directory.appendingPathComponent("codex-home"),
            temporaryDirectory: directory
        )
        let canonicalPaths = Set(paths.map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path
        })
        XCTAssertTrue(canonicalPaths.contains(
            directory.appendingPathComponent("codex-home/app-server-control/app-server-control.sock")
                .resolvingSymlinksInPath().path
        ))
        XCTAssertTrue(canonicalPaths.contains(socket.resolvingSymlinksInPath().path))
    }

    func testNotificationSoundCatalogContainsSixBundledChoicesAndSilence() throws {
        let audible = NotificationSound.allCases.filter { $0 != .none }

        XCTAssertEqual(audible.count, 6)
        XCTAssertEqual(Set(audible.map(\.rawValue)).count, 6)
        XCTAssertTrue(audible.allSatisfy { $0.resourceURL != nil })
        for sound in audible {
            let url = try XCTUnwrap(sound.resourceURL)
            XCTAssertGreaterThan(try Data(contentsOf: url).count, 1_000)
        }
        XCTAssertNil(NotificationSound.none.resourceURL)
    }

    func testNotificationSoundSelectionPersistsAndFallsBackSafely() throws {
        let suiteName = "CodexNotchTests.NotificationSounds.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(NotificationSound.selected(in: defaults), .glassDrop)
        NotificationSound.prism.select(in: defaults)
        XCTAssertEqual(NotificationSound.selected(in: defaults), .prism)

        defaults.set("removed-sound", forKey: NotificationSound.preferenceKey)
        XCTAssertEqual(NotificationSound.selected(in: defaults), .glassDrop)
    }

    func testNerdShortcutsUseSwissKeyboardLayoutAndOpenTenSlots() {
        XCTAssertEqual(
            GlobalHotKeys.nerdBindings.map(\.keyLabel),
            ["H", "J", "K", "L", "Ö", "U", "I", "O", "P", "N", "M"]
        )
        XCTAssertEqual(
            GlobalHotKeys.nerdBindings.map(\.action),
            [.toggle] + (0..<10).map { .open($0) }
        )
        XCTAssertEqual(
            GlobalHotKeys.nerdBindings[4].keyCode,
            UInt32(kVK_ANSI_Semicolon)
        )
        XCTAssertEqual(GlobalHotKeys.toggleShortcutLabel(), "⌃⇧H")
        XCTAssertEqual(GlobalHotKeys.activeTasksShortcutLabel(), "⌃⇧R")
        XCTAssertEqual(GlobalHotKeys.openShortcutKeyLabel(at: 0), "J")
        XCTAssertEqual(GlobalHotKeys.openShortcutKeyLabel(at: 3), "Ö")
        XCTAssertEqual(GlobalHotKeys.openShortcutLabel(at: 9), "⌃⇧M")
        XCTAssertEqual(GlobalHotKeys.action(forHotKeyID: 310), .open(9))
        XCTAssertEqual(GlobalHotKeys.action(forHotKeyID: 210), .dismiss(9))
        XCTAssertEqual(GlobalHotKeys.action(forHotKeyID: 400), .settings)
        XCTAssertEqual(GlobalHotKeys.action(forHotKeyID: 401), .toggleActiveTasks)
    }
}
