import AppKit
import Carbon
import CodexNotchCore
import Darwin
import Network
import XCTest
@testable import CodexNotchApp

final class CodexNotchTests: XCTestCase {
    private let threadID = "019f5d4f-3a8d-76c0-8c2d-19451190e028"

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

    func testRateLimitParserDoesNotMislabelShortWindowAsWeekly() {
        let response = Data("""
        {"id":2,"result":{"rateLimits":{
          "limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":300}
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
        XCTAssertTrue(paths.contains("/Users/ralf/.local/bin/codex"))
        XCTAssertTrue(paths.contains("/opt/homebrew/bin/codex"))
        XCTAssertTrue(paths.contains("/custom/bin/codex"))
        XCTAssertEqual(paths.filter { $0 == "/opt/homebrew/bin/codex" }.count, 1)
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

        try installer.uninstall()
        XCTAssertFalse(installer.isInstalled)
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

    func testRemoteEnvelopeAndAcknowledgementUseProtocolV1() throws {
        let data = Data("""
        {"protocol_version":1,"kind":"completion","token":"secret","event":{
          "schema_version":1,
          "event_id":"\(CompletionEvent.eventID(threadID: threadID, turnID: "turn-1"))",
          "thread_id":"\(threadID)","turn_id":"turn-1","title":"Task",
          "source_id":"remote","source_label":"Ubuntu","completed_at":"2026-07-14T12:00:00Z"
        }}
        """.utf8)
        let envelope = try JSONDecoder.codexNotch.decode(RemoteEnvelope.self, from: data)
        XCTAssertEqual(envelope.protocolVersion, 1)
        XCTAssertTrue(try XCTUnwrap(envelope.event).isValid)

        let ack = RemoteAcknowledgement.accepted(eventID: envelope.event!.eventID, duplicate: true)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.codexNotch.encode(ack)) as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "duplicate")
        XCTAssertEqual(object["protocol_version"] as? Int, 1)

        let activeData = try JSONEncoder.codexNotch.encode(ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: Date(),
            tasks: [ActiveTaskEvent(
                threadID: threadID,
                title: "Running",
                state: .running,
                updatedAt: Date()
            )]
        ))
        let activeObject = try XCTUnwrap(JSONSerialization.jsonObject(with: activeData))
        let activeEnvelopeData = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1,
            "kind": "active_snapshot",
            "token": "secret",
            "snapshot": activeObject,
        ])
        let activeEnvelope = try JSONDecoder.codexNotch.decode(RemoteEnvelope.self, from: activeEnvelopeData)
        XCTAssertTrue(try XCTUnwrap(activeEnvelope.snapshot).isValid)
    }

    func testRemoteSSHFailuresHideTracebacksAndStayBounded() {
        let traceback = """
        Traceback (most recent call last):
          File \"remote.py\", line 1, in <module>
        ValueError: invalid remote configuration
        """
        XCTAssertEqual(
            RemoteHostPairer.userFacingSSHError(traceback),
            "ValueError: invalid remote configuration"
        )
        XCTAssertEqual(RemoteHostPairer.userFacingSSHError("  \n"), "SSH command failed")
        XCTAssertEqual(
            RemoteHostPairer.userFacingSSHError(String(repeating: "x", count: 500)).count,
            360
        )
    }

    func testRemoteHealthSummaryHandlesMultipleHostsAndMixedFailures() {
        let checkedAt = Date(timeIntervalSince1970: 1_784_035_200)
        let first = RemoteHost(
            id: "host-1",
            label: "Build box",
            sshAlias: "build",
            endpointHost: "100.64.0.1",
            createdAt: checkedAt
        )
        let second = RemoteHost(
            id: "host-2",
            label: "Home server",
            sshAlias: "home",
            endpointHost: "100.64.0.1",
            createdAt: checkedAt
        )

        let checking = RemoteHostHealthSnapshot(
            hosts: [first, second],
            healthByHostID: [:],
            isRefreshing: true
        )
        XCTAssertEqual(checking.summaryText, "Checking 2 hosts…")

        let working = RemoteHostHealthSnapshot(
            hosts: [first, second],
            healthByHostID: [
                first.id: .working(checkedAt: checkedAt),
                second.id: .working(checkedAt: checkedAt),
            ]
        )
        XCTAssertEqual(working.summaryText, "2 hosts working")
        XCTAssertEqual(working.workingCount, 2)

        let mixed = RemoteHostHealthSnapshot(
            hosts: [first, second],
            healthByHostID: [
                first.id: .working(checkedAt: checkedAt),
                second.id: .unreachable(message: "No route to host", checkedAt: checkedAt),
            ]
        )
        XCTAssertEqual(mixed.summaryText, "1 of 2 working")
        XCTAssertEqual(mixed.problemCount, 1)
        XCTAssertEqual(mixed.health(for: second).statusText, "Offline")
    }

    func testRemoteHealthSeparatesOfflineHostsFromSSHConfigurationProblems() {
        let checkedAt = Date(timeIntervalSince1970: 1_784_035_200)
        let offline = RemoteHostPairer.healthResult(
            for: NSError(
                domain: "CodexNotch",
                code: 255,
                userInfo: [NSLocalizedDescriptionKey: "ssh: connect to host build: Connection timed out"]
            ),
            checkedAt: checkedAt
        )
        let authentication = RemoteHostPairer.healthResult(
            for: NSError(
                domain: "CodexNotch",
                code: 255,
                userInfo: [NSLocalizedDescriptionKey: "build: Permission denied (publickey)"]
            ),
            checkedAt: checkedAt
        )

        XCTAssertEqual(offline.statusText, "Offline")
        XCTAssertEqual(authentication.statusText, "Needs attention")
    }

    func testPairingTokensPersistInPrivateFileAndAuthenticateWithoutKeychain() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostsFile = directory.appendingPathComponent("remote-hosts.json")
        let tokensFile = directory.appendingPathComponent("remote-host-tokens.json")
        let host = RemoteHost(
            id: "remote-host-id",
            label: "Ubuntu",
            sshAlias: "ubuntu",
            endpointHost: "127.0.0.1",
            createdAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
        let token = String(repeating: "a", count: 64)
        let store = PairingStore(fileURL: hostsFile, tokensFileURL: tokensFile)

        try store.save(host, token: token)
        XCTAssertEqual(store.host(authenticating: token), host)
        XCTAssertNil(store.host(authenticating: String(repeating: "b", count: 64)))

        let reloaded = PairingStore(fileURL: hostsFile, tokensFileURL: tokensFile)
        XCTAssertEqual(reloaded.host(authenticating: token), host)
        let attributes = try FileManager.default.attributesOfItem(atPath: tokensFile.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        try reloaded.removeAllCredentials()
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokensFile.path))
        XCTAssertNil(reloaded.host(authenticating: token))
        XCTAssertEqual(reloaded.hosts, [host])
    }

    func testLegacyPairingRecoversMissingTokenIntoPrivateFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let hostsFile = directory.appendingPathComponent("remote-hosts.json")
        let tokensFile = directory.appendingPathComponent("remote-host-tokens.json")
        let host = RemoteHost(
            id: "legacy-host-id",
            label: "Ubuntu",
            sshAlias: "ubuntu",
            endpointHost: "127.0.0.1",
            createdAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
        try JSONEncoder.codexNotch.encode([host]).write(to: hostsFile)
        let store = PairingStore(fileURL: hostsFile, tokensFileURL: tokensFile)
        XCTAssertEqual(store.hostsMissingTokens, [host])

        let token = String(repeating: "c", count: 64)
        try store.saveRecoveredToken(token, forHostID: host.id)

        XCTAssertTrue(store.hostsMissingTokens.isEmpty)
        XCTAssertEqual(store.host(authenticating: token), host)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tokensFile.path))
    }

    func testOverlayGeometryAndPresentationModes() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        overlay.update(tasks: [CompletedTask(
            eventID: String(repeating: "b", count: 64),
            title: String(repeating: "A long finished task title ", count: 8),
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])
        XCTAssertEqual(overlay.bodyWidthForTesting, 820, accuracy: 0.5)
        XCTAssertEqual(
            overlay.bodyHeightForTesting,
            overlay.notchHeightForTesting + 110,
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(overlay.notchWidthForTesting, 80)

        let view = try! XCTUnwrap(overlay.contentViewForTesting)
        view.layoutSubtreeIfNeeded()
        let closedPath = try! XCTUnwrap((view.layer?.mask as? CAShapeLayer)?.path)
        XCTAssertTrue(closedPath.contains(CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 1)))
        XCTAssertFalse(closedPath.contains(CGPoint(x: 1, y: view.bounds.maxY - 1)))
        XCTAssertFalse(closedPath.contains(CGPoint(x: view.bounds.midX, y: 1)))

        overlay.toggle()
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)
        let expandedPath = try! XCTUnwrap((view.layer?.mask as? CAShapeLayer)?.path)
        let expandedBounds = expandedPath.boundingBoxOfPath
        XCTAssertEqual(expandedBounds.minX, 0, accuracy: 0.5)
        XCTAssertEqual(expandedBounds.maxX, view.bounds.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(expandedBounds.maxY, view.bounds.maxY)
        XCTAssertTrue(expandedPath.contains(CGPoint(x: view.bounds.midX, y: 1)))
        XCTAssertFalse(expandedPath.contains(CGPoint(x: 1, y: 1)))
        let expandedBodyInset = (view.bounds.width - overlay.bodyWidthForTesting) / 2
        XCTAssertTrue(expandedPath.contains(CGPoint(x: expandedBodyInset + 29, y: 1)))
        overlay.hide(immediately: true)
        overlay.showForEvent()
        XCTAssertTrue(overlay.hasHideTimerForTesting)
        overlay.hide(immediately: true)
    }

    func testTaskBadgesShowNerdLettersOnlyWhileControlShiftAreHeld() {
        _ = NSApplication.shared
        var modifiersHeld = false
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            shortcutModifierState: { modifiersHeld }
        )
        overlay.update(tasks: [
            CompletedTask(
                eventID: String(repeating: "1", count: 64),
                title: "First task",
                url: URL(string: "codex://threads/\(threadID)")!,
                receivedAt: Date()
            ),
            CompletedTask(
                eventID: String(repeating: "2", count: 64),
                title: "Second task",
                url: URL(string: "codex://threads/\(threadID)")!,
                receivedAt: Date()
            ),
        ])

        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["1", "2"])
        overlay.toggle()

        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["J", "K"])

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["1", "2"])
        overlay.hide(immediately: true)
    }

    func testActiveAndCompletedTasksShareTheVisibleShortcutOrder() {
        _ = NSApplication.shared
        var modifiersHeld = false
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            shortcutModifierState: { modifiersHeld }
        )
        overlay.update(tasks: [
            CompletedTask(
                eventID: String(repeating: "3", count: 64),
                title: "First completed task",
                url: URL(string: "codex://threads/\(threadID)")!,
                receivedAt: Date()
            ),
            CompletedTask(
                eventID: String(repeating: "4", count: 64),
                title: "Second completed task",
                url: URL(string: "codex://threads/\(threadID)")!,
                receivedAt: Date()
            ),
        ])
        overlay.update(activeTasks: [
            ActiveTask(
                threadID: "active-1",
                title: "First active task",
                sourceID: "local",
                sourceLabel: "This Mac",
                state: .running,
                updatedAt: Date()
            ),
            ActiveTask(
                threadID: "active-2",
                title: "Second active task",
                sourceID: "local",
                sourceLabel: "This Mac",
                state: .waitingForInput,
                updatedAt: Date()
            ),
        ], visible: true)

        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["1", "2", "3", "4"])
        overlay.toggle()

        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["J", "K", "L", "Ö"])

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["1", "2", "3", "4"])
        overlay.hide(immediately: true)
    }

    func testSharedShortcutIndexOpensActiveThenCompletedTasksAndSkipsActiveDismissal() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { true })
        let completed = CompletedTask(
            eventID: String(repeating: "5", count: 64),
            title: "Completed task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let active = ActiveTask(
            threadID: "active-shortcut",
            title: "Active task",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .running,
            updatedAt: Date()
        )
        overlay.update(tasks: [completed])
        overlay.update(activeTasks: [active], visible: true)
        var openedActive: ActiveTask?
        var openedCompleted: CompletedTask?
        var finishedCompleted: CompletedTask?
        var dismissedIndex: Int?
        overlay.onOpenActive = {
            openedActive = $0
            return true
        }
        overlay.onOpen = {
            openedCompleted = $0
            return true
        }
        overlay.onOpenFinished = { finishedCompleted = $0 }
        overlay.onDismiss = { dismissedIndex = $0 }

        overlay.openTask(at: 0, animated: false)
        XCTAssertEqual(openedActive, active)
        XCTAssertNil(openedCompleted)

        overlay.openTask(at: 1, animated: false)
        XCTAssertEqual(openedCompleted, completed)
        XCTAssertEqual(finishedCompleted, completed)

        overlay.dismissTask(at: 0, animated: false)
        XCTAssertNil(dismissedIndex)
        overlay.dismissTask(at: 1, animated: false)
        XCTAssertEqual(dismissedIndex, 0)
    }

    func testDoNotDisturbSuppressesAutomaticPresentationButKeepsManualToggle() {
        _ = NSApplication.shared
        var automaticOpenAllowed = false
        let overlay = OverlayController(
            automaticOpenAllowed: { automaticOpenAllowed },
            shouldReduceMotion: { true }
        )
        overlay.update(tasks: [CompletedTask(
            eventID: String(repeating: "d", count: 64),
            title: "Quietly completed task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])

        overlay.showForEvent()
        XCTAssertFalse(overlay.isVisibleForTesting)

        overlay.setUpdateAvailable(version: "0.4.0")
        XCTAssertFalse(overlay.isVisibleForTesting)

        overlay.toggle()
        XCTAssertTrue(overlay.isVisibleForTesting)
        overlay.hide(immediately: true)

        automaticOpenAllowed = true
        overlay.showForEvent()
        XCTAssertTrue(overlay.isVisibleForTesting)
        overlay.hide(immediately: true)
    }

    func testVisibleTaskOpenDefersRemovalUntilHandoffCompletes() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        let task = CompletedTask(
            eventID: String(repeating: "c", count: 64),
            title: "Open with a handoff",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        overlay.update(tasks: [task])

        var activated: CompletedTask?
        let finished = expectation(description: "launch handoff finished")
        overlay.onOpen = { opened in
            activated = opened
            return true
        }
        overlay.onOpenFinished = { opened in
            XCTAssertEqual(opened, task)
            finished.fulfill()
        }

        overlay.toggle()
        overlay.openTask(at: 0)
        XCTAssertEqual(activated, task)
        XCTAssertTrue(overlay.isLaunchingForTesting)
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(overlay.isVisibleForTesting)
    }

    func testKeyboardTaskOpenHandsOffImmediatelyWithoutMotion() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        let task = CompletedTask(
            eventID: String(repeating: "e", count: 64),
            title: "Open from keyboard",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        overlay.update(tasks: [task])
        var finishedTask: CompletedTask?
        overlay.onOpen = { _ in true }
        overlay.onOpenFinished = { finishedTask = $0 }

        overlay.toggle()
        overlay.openTask(at: 0, animated: false)

        XCTAssertEqual(finishedTask, task)
        XCTAssertFalse(overlay.isLaunchingForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)
    }

    func testKeyboardTaskDismissIsImmediate() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        overlay.update(tasks: [CompletedTask(
            eventID: String(repeating: "f", count: 64),
            title: "Dismiss from keyboard",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])
        var dismissedIndex: Int?
        overlay.onDismiss = { dismissedIndex = $0 }
        overlay.toggle()

        overlay.dismissTask(at: 0, animated: false)

        XCTAssertEqual(dismissedIndex, 0)
        overlay.hide(immediately: true)
    }

    func testAnimatedDismissTracksTaskIdentityAcrossConcurrentInsertion() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        let dismissedTask = CompletedTask(
            eventID: String(repeating: "4", count: 64),
            title: "Dismiss this task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let insertedTask = CompletedTask(
            eventID: String(repeating: "5", count: 64),
            title: "Arrived during dismissal",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        overlay.update(tasks: [dismissedTask])
        overlay.toggle()
        let dismissed = expectation(description: "task dismissed after exit motion")
        overlay.onDismiss = { index in
            XCTAssertEqual(index, 1)
            dismissed.fulfill()
        }

        overlay.dismissTask(at: 0)
        overlay.update(tasks: [insertedTask, dismissedTask])

        wait(for: [dismissed], timeout: 1)
        overlay.hide(immediately: true)
    }

    func testNewTaskGetsContextualArrivalMotionWhileNotchIsOpen() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { false })
        let first = CompletedTask(
            eventID: String(repeating: "1", count: 64),
            title: "First task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let second = CompletedTask(
            eventID: String(repeating: "2", count: 64),
            title: "Second task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        overlay.update(tasks: [first])
        overlay.toggle()

        overlay.update(tasks: [second, first])

        XCTAssertEqual(overlay.rowArrivalAnimationCountForTesting, 1)
        overlay.hide(immediately: true)
    }

    func testReducedMotionEventUsesOpacityContinuity() {
        _ = NSApplication.shared
        let overlay = OverlayController(shouldReduceMotion: { true })
        overlay.update(tasks: [CompletedTask(
            eventID: String(repeating: "3", count: 64),
            title: "Reduced motion task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])

        overlay.showForEvent()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.hasContentAnimationForTesting)
        overlay.hide(immediately: true)
    }

    func testUpdateAvailabilityAddsClickablePersistentContent() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        var clicked = false
        overlay.onUpdate = { clicked = true }

        overlay.setUpdateAvailable(version: "0.4.0")
        XCTAssertTrue(overlay.isUpdateAvailableForTesting)
        XCTAssertTrue(overlay.hasContent)
        overlay.updateButtonForTesting?.performClick(nil)
        XCTAssertTrue(clicked)

        overlay.setUpdateAvailable(version: nil)
        XCTAssertFalse(overlay.hasContent)
        overlay.hide(immediately: true)
    }

    func testEmptyOverlayCanBeToggledAndShowsEmptyState() {
        _ = NSApplication.shared
        let overlay = OverlayController()

        XCTAssertFalse(overlay.hasContent)
        overlay.toggle()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, overlay.notchHeightForTesting + 100)
        XCTAssertTrue(overlay.hasEmptyStateForTesting)
        overlay.hide(immediately: true)
    }

    func testActiveTaskAppearsAboveTheEmptyStateAndCanBeHidden() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        let active = ActiveTask(
            threadID: threadID,
            title: "Still building",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .running,
            updatedAt: Date()
        )

        overlay.update(activeTasks: [active], visible: true)
        XCTAssertTrue(overlay.hasContent)
        XCTAssertFalse(overlay.hasEmptyStateForTesting)
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, overlay.notchHeightForTesting + 110)

        overlay.update(activeTasks: [active], visible: false)
        XCTAssertFalse(overlay.hasContent)
        XCTAssertTrue(overlay.hasEmptyStateForTesting)
    }

    func testOverlayShowsAggregateRemoteHostHealth() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        let checkedAt = Date(timeIntervalSince1970: 1_784_035_200)
        let host = RemoteHost(
            id: "host-1",
            label: "Ubuntu",
            sshAlias: "ubuntu",
            endpointHost: "100.64.0.1",
            createdAt: checkedAt
        )

        overlay.setRemoteHostHealth(RemoteHostHealthSnapshot(
            hosts: [host],
            healthByHostID: [host.id: .working(checkedAt: checkedAt)]
        ))

        XCTAssertEqual(overlay.remoteStatusTextForTesting, "Host working")
        overlay.toggle()
        XCTAssertTrue(overlay.isVisibleForTesting)
        overlay.hide(immediately: true)
    }

    func testWeeklyLimitRemainsVisibleAlongsideActiveTaskSupport() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        overlay.setWeeklyLimit(CodexWeeklyLimit(
            remainingPercent: 63,
            resetsAt: Date(timeIntervalSince1970: 1_784_487_540)
        ))

        XCTAssertTrue(overlay.hasContent)
        overlay.toggle()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertEqual(overlay.weeklyLimitViewForTesting?.percentageTextForTesting, "63% left")
        XCTAssertTrue(
            overlay.weeklyLimitViewForTesting?.resetTextForTesting.hasPrefix("Resets ") == true
        )
        overlay.hide(immediately: true)
    }

    func testOverlayReportsVisibleLifetimeForScopedShortcuts() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        var visibility: [Bool] = []
        overlay.onVisibilityChanged = { visibility.append($0) }

        overlay.toggle()
        overlay.toggle()

        XCTAssertEqual(visibility, [true, false])
    }

    func testSettingsButtonClosesHUDBeforeOpeningSettings() {
        _ = NSApplication.shared
        let overlay = OverlayController()
        let task = CompletedTask(
            eventID: String(repeating: "d", count: 64),
            title: "Open settings",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        var wasHiddenWhenSettingsOpened = false
        overlay.onSettings = {
            wasHiddenWhenSettingsOpened = !overlay.isVisibleForTesting
        }

        overlay.update(tasks: [task])
        overlay.toggle()
        XCTAssertTrue(overlay.isVisibleForTesting)

        overlay.settingsButtonForTesting?.performClick(nil)

        XCTAssertTrue(wasHiddenWhenSettingsOpened)
        XCTAssertFalse(overlay.isVisibleForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
    }

    func testSettingsWindowIsKeyCapableAndClosesWithCommandW() throws {
        _ = NSApplication.shared
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertTrue(window.isVisible)

        let commandW = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        XCTAssertTrue(window.performKeyEquivalent(with: commandW))
        XCTAssertFalse(window.isVisible)
    }

    func testSettingsUsesRegularActivationOnlyWhileVisible() {
        _ = NSApplication.shared
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        NSApp.setActivationPolicy(.accessory)
        let directory = temporaryDirectory()
        defer {
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
            NSApp.setActivationPolicy(.accessory)
            try? FileManager.default.removeItem(at: directory)
        }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(pairings: pairings, pairer: pairer)

        controller.present()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertTrue(controller.window?.canBecomeKey == true)
        XCTAssertEqual(NSApp.mainMenu?.items.first?.title, ApplicationMenu.applicationName)
        XCTAssertEqual(NSApp.mainMenu?.items.map(\.title), ["Codex Notch", "File", "Edit", "Window"])
        XCTAssertTrue(NSApp.windowsMenu === NSApp.mainMenu?.items.last?.submenu)

        controller.close()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertTrue(controller.window?.isVisible == false)
    }

    func testSettingsVersionDescriptionIncludesReleaseAndBuildNumbers() {
        XCTAssertEqual(
            OnboardingWindowController.versionDescription(info: [
                "CFBundleShortVersionString": "0.3.6",
                "CFBundleVersion": "9",
            ]),
            "Version 0.3.6 (9)"
        )
        XCTAssertEqual(
            OnboardingWindowController.versionDescription(info: [:]),
            "Version unavailable"
        )
    }

    func testSettingsCheckForUpdatesButtonInvokesHandler() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )
        var checked = false
        controller.onCheckForUpdates = { checked = true }

        let button = try XCTUnwrap(controller.checkForUpdatesButtonForTesting)
        XCTAssertEqual(button.title, "Check for Updates")
        button.performClick(nil)

        XCTAssertTrue(checked)
    }

    func testSettingsRendersThemesSoundsAndPaddedNavigationTabs() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        XCTAssertEqual(
            controller.settingsTabTitlesForTesting,
            ["Themes", "Tasks", "Sounds", "Connections"]
        )
        XCTAssertEqual(controller.renderedThemeChoiceCountForTesting, 6)
        XCTAssertFalse(controller.hasEmbeddedThemePreviewForTesting)
        XCTAssertGreaterThanOrEqual(SettingsNavigationButton.horizontalContentPadding, 12)

        controller.showSoundsForTesting()

        XCTAssertEqual(controller.renderedSoundChoiceCountForTesting, 7)
        XCTAssertEqual(NotificationSound.allCases.filter { $0 != .none }.count, 6)
        XCTAssertTrue(NotificationSound.allCases.filter { $0 != .none }.allSatisfy {
            $0.resourceURL != nil
        })
    }

    func testSettingsThemeAndSoundChoicesReceiveVisibleFrames() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true }
        )

        XCTAssertEqual(controller.renderedThemeChoiceFramesForTesting.count, 6)
        for frame in controller.renderedThemeChoiceFramesForTesting {
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThan(frame.height, 60)
            XCTAssertTrue(controller.settingsBoundsForTesting.intersects(frame))
        }

        controller.showSoundsForTesting()

        XCTAssertEqual(controller.renderedSoundChoiceFramesForTesting.count, 7)
        for frame in controller.renderedSoundChoiceFramesForTesting {
            XCTAssertGreaterThan(frame.width, 100)
            XCTAssertGreaterThan(frame.height, 40)
            XCTAssertTrue(controller.settingsBoundsForTesting.intersects(frame))
        }
    }

    func testThemeTabKeepsRealNotchOpenAndReleasesItWhenLeaving() {
        _ = NSApplication.shared
        let previousMainMenu = NSApp.mainMenu
        let previousWindowsMenu = NSApp.windowsMenu
        NSApp.setActivationPolicy(.accessory)
        let directory = temporaryDirectory()
        defer {
            NSApp.mainMenu = previousMainMenu
            NSApp.windowsMenu = previousWindowsMenu
            NSApp.setActivationPolicy(.accessory)
            try? FileManager.default.removeItem(at: directory)
        }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let overlay = OverlayController(shouldReduceMotion: { true })
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true },
            shouldReduceMotion: { true }
        )
        controller.onThemePreviewVisibilityChanged = { visible, screen in
            overlay.setThemePreviewVisible(visible, on: screen)
        }

        controller.present()
        XCTAssertFalse(controller.hasEmbeddedThemePreviewForTesting)
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)

        overlay.toggle()
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)

        controller.selectSettingsTabForTesting(titled: "Tasks")
        waitForMainQueue(seconds: 0.2)
        XCTAssertFalse(overlay.isThemePreviewActiveForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)

        controller.selectSettingsTabForTesting(titled: "Themes")
        waitForMainQueue(seconds: 0.2)
        XCTAssertTrue(overlay.isThemePreviewActiveForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)

        controller.close()
        XCTAssertFalse(overlay.isThemePreviewActiveForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isVisibleForTesting)
    }

    func testSettingsTabTransitionsPreserveFixedWindowGeometry() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            isHookInstalled: { true },
            shouldReduceMotion: { false }
        )
        let window = try XCTUnwrap(controller.window)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        let expectedSize = OnboardingWindowController.settingsContentSize
        XCTAssertEqual(controller.settingsBoundsForTesting.width, expectedSize.width, accuracy: 0.5)
        XCTAssertEqual(controller.settingsBoundsForTesting.height, expectedSize.height, accuracy: 0.5)

        for title in ["Tasks", "Sounds", "Connections", "Themes"] {
            controller.selectSettingsTabForTesting(titled: title)
            let transitionFinished = expectation(description: "\(title) tab transition finished")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                transitionFinished.fulfill()
            }
            wait(for: [transitionFinished], timeout: 1)

            XCTAssertEqual(
                controller.settingsBoundsForTesting.width,
                expectedSize.width,
                accuracy: 0.5,
                "\(title) changed the settings width"
            )
            XCTAssertEqual(
                controller.settingsBoundsForTesting.height,
                expectedSize.height,
                accuracy: 0.5,
                "\(title) changed the settings height"
            )
        }
    }

    func testSettingsDoNotDisturbTogglePersistsWithoutMacOSFocus() throws {
        _ = NSApplication.shared
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "CodexNotchTests.SettingsDoNotDisturb.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DoNotDisturbPreferences(defaults: defaults)
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let pairer = RemoteHostPairer(store: pairings) { _ in }
        let controller = OnboardingWindowController(
            pairings: pairings,
            pairer: pairer,
            doNotDisturbPreferences: preferences,
            isHookInstalled: { true }
        )

        controller.showTasksForTesting()
        let disabledButton = try XCTUnwrap(controller.doNotDisturbButtonForTesting)
        XCTAssertEqual(disabledButton.title, "Off")
        disabledButton.performClick(nil)

        XCTAssertTrue(preferences.isEnabled)
        XCTAssertEqual(controller.doNotDisturbButtonForTesting?.title, "On")
    }

    func testThemePreviewIsTemporaryAndSelectionPersists() {
        let suiteName = "CodexNotchTests.Theme.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create isolated defaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let themes = ThemeStore(defaults: defaults)

        XCTAssertEqual(themes.selectedID, .obsidian)
        themes.preview(.ember)
        XCTAssertEqual(themes.activeTheme.id, .ember)
        XCTAssertEqual(themes.selectedID, .obsidian)

        themes.endPreview(.ember)
        XCTAssertEqual(themes.activeTheme.id, .obsidian)
        themes.preview(.aurora)
        themes.select(.aurora)

        XCTAssertEqual(themes.activeTheme.id, .aurora)
        XCTAssertEqual(defaults.string(forKey: ThemeStore.defaultsKey), "aurora")
        XCTAssertEqual(ThemeStore(defaults: defaults).selectedID, .aurora)
    }

    func testNotificationSoundsResolveFromPackagedApplicationResourcesWithoutModuleFallback() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resources = directory.appendingPathComponent("Contents/Resources", isDirectory: true)
        let sounds = resources
            .appendingPathComponent(NotificationSound.resourceBundleName, isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)

        for sound in NotificationSound.allCases where sound != .none {
            let expectedURL = sounds
                .appendingPathComponent(sound.rawValue)
                .appendingPathExtension("mp3")
            try Data([0x49, 0x44, 0x33]).write(to: expectedURL)
            var usedFallback = false

            let resolvedURL = sound.resourceURL(
                applicationResourcesURL: resources,
                fallbackBundle: {
                    usedFallback = true
                    return nil
                }
            )

            XCTAssertEqual(resolvedURL, expectedURL)
            XCTAssertFalse(usedFallback, "\(sound.name) unexpectedly evaluated Bundle.module")
        }
    }

    func testMissingPackagedSoundFailsQuietlyWhenFallbackIsUnavailable() {
        let missingResources = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: missingResources) }
        var usedFallback = false

        let resolvedURL = NotificationSound.glassDrop.resourceURL(
            applicationResourcesURL: missingResources,
            fallbackBundle: {
                usedFallback = true
                return nil
            }
        )

        XCTAssertNil(resolvedURL)
        XCTAssertTrue(usedFallback)
    }

    func testTailscaleListenerReportsReadyBeforePairingContinues() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let listener = TailscaleListener(pairings: pairings) { _ in .accepted }
        defer { listener.stop() }

        try listener.start(host: "127.0.0.1", port: .any)
        try listener.waitUntilReady(timeout: 2)
    }

    func testTailscaleListenerBindsAConcretePortAndAnswersAFrame() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pairings = PairingStore(fileURL: directory.appendingPathComponent("pairings.json"))
        let host = RemoteHost(
            id: "listener-host-id",
            label: "Ubuntu",
            sshAlias: "ubuntu",
            endpointHost: "127.0.0.1",
            createdAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
        let token = String(repeating: "d", count: 64)
        try pairings.save(host, token: token)
        var receivedSnapshot: ActiveTaskSnapshot?
        let listener = TailscaleListener(
            pairings: pairings,
            activeDelivery: { deliveredHost, snapshot in
                XCTAssertEqual(deliveredHost, host)
                receivedSnapshot = snapshot
                return true
            },
            delivery: { _ in .accepted }
        )
        defer { listener.stop() }

        let port = try unusedLoopbackPort()
        try listener.start(host: "127.0.0.1", port: port)
        try listener.waitUntilReady(timeout: 2)

        let payload = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1,
            "kind": "ping",
            "token": "not-paired",
        ])
        let acknowledgement = try socketRoundTrip(payload, port: port.rawValue)
        XCTAssertEqual(acknowledgement.status, "rejected")
        XCTAssertEqual(acknowledgement.error, "authentication failed")

        let pairedPayload = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1,
            "kind": "ping",
            "token": token,
        ])
        let pairedAcknowledgement = try socketRoundTrip(pairedPayload, port: port.rawValue)
        XCTAssertEqual(pairedAcknowledgement.status, "pong")

        let snapshotTimestamp = Date(timeIntervalSince1970: 1_784_035_200)
        let snapshot = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: snapshotTimestamp,
            tasks: [ActiveTaskEvent(
                threadID: threadID,
                title: "Running remotely",
                state: .running,
                updatedAt: snapshotTimestamp
            )]
        )
        let snapshotObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder.codexNotch.encode(snapshot))
        )
        let activePayload = try JSONSerialization.data(withJSONObject: [
            "protocol_version": 1,
            "kind": "active_snapshot",
            "token": token,
            "snapshot": snapshotObject,
        ])
        let activeAcknowledgementExpectation = expectation(description: "Active snapshot acknowledgement")
        var activeAcknowledgementResult: Result<RemoteAcknowledgement, Error>?
        DispatchQueue.global().async {
            activeAcknowledgementResult = Result {
                try self.socketRoundTrip(activePayload, port: port.rawValue)
            }
            activeAcknowledgementExpectation.fulfill()
        }
        wait(for: [activeAcknowledgementExpectation], timeout: 2)
        let activeAcknowledgement = try XCTUnwrap(activeAcknowledgementResult).get()
        XCTAssertEqual(activeAcknowledgement.status, "accepted")
        XCTAssertEqual(receivedSnapshot, snapshot)

        listener.stop()
        try listener.start(host: "127.0.0.1", port: port)
        try listener.waitUntilReady(timeout: 2)
    }

    func testLocalUninstallerIncludesCurrentAndLegacyArtifacts() {
        let bundle = URL(fileURLWithPath: "/tmp/Codex Notch.app")
        let paths = Set(LocalApplicationUninstaller.cleanupArtifacts(bundleURL: bundle).map(\.path))
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].path

        XCTAssertTrue(paths.contains("\(library)/Application Support/Codex Notch"))
        XCTAssertTrue(paths.contains("\(library)/Caches/com.ralfbuilds.CodexNotch"))
        XCTAssertTrue(paths.contains("\(library)/Preferences/com.ralfbuilds.CodexNotch.plist"))
        XCTAssertTrue(paths.contains("\(library)/Application Support/Ntfy Codex Overlay"))
        XCTAssertTrue(paths.contains("\(library)/LaunchAgents/com.ralfbuilds.ntfy-codex-overlay.plist"))
    }

    private func makeEvent() -> CompletionEvent {
        CompletionEvent(
            eventID: CompletionEvent.eventID(threadID: threadID, turnID: "turn-1"),
            threadID: threadID,
            turnID: "turn-1",
            title: "Build the overlay",
            sourceID: "local",
            sourceLabel: "This Mac",
            completedAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("codex-notch-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func waitForMainQueue(seconds: TimeInterval) {
        let finished = expectation(description: "Main queue advanced")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: seconds + 1)
    }

    private func hooksRoot(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func unusedLoopbackPort() throws -> NWEndpoint.Port {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        XCTAssertEqual(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr), 1)
        let bindStatus = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else { throw POSIXError(.EADDRINUSE) }

        var boundAddress = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameStatus = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard nameStatus == 0,
              let port = NWEndpoint.Port(rawValue: UInt16(bigEndian: boundAddress.sin_port))
        else { throw POSIXError(.EIO) }
        return port
    }

    private func socketRoundTrip(_ payload: Data, port: UInt16) throws -> RemoteAcknowledgement {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        XCTAssertEqual(inet_pton(AF_INET, "127.0.0.1", &address.sin_addr), 1)
        let status = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }

        var length = UInt32(payload.count).bigEndian
        var frame = withUnsafeBytes(of: &length) { Data($0) }
        frame.append(payload)
        try sendAll(frame, descriptor: descriptor)
        let header = try receiveExact(4, descriptor: descriptor)
        let responseLength = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let response = try receiveExact(Int(responseLength), descriptor: descriptor)
        return try JSONDecoder.codexNotch.decode(RemoteAcknowledgement.self, from: response)
    }

    private func sendAll(_ data: Data, descriptor: Int32) throws {
        try data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let amount = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    data.count - offset,
                    0
                )
                guard amount > 0 else { throw POSIXError(.EIO) }
                offset += amount
            }
        }
    }

    private func receiveExact(_ count: Int, descriptor: Int32) throws -> Data {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            var offset = 0
            while offset < count {
                let amount = Darwin.recv(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    count - offset,
                    0
                )
                if amount <= 0 { return -1 }
                offset += amount
            }
            return offset
        }
        guard received == count else { throw POSIXError(.EIO) }
        return data
    }
}
