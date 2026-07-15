import AppKit
import CodexNotchCore
import Darwin
import Network
import XCTest
@testable import CodexNotchApp

final class RemoteConnectionTests: CodexNotchTestCase {
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

    func testHostHealthOverviewIncludesLocalAndEveryRemoteHost() {
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
            endpointHost: "100.64.0.2",
            createdAt: checkedAt
        )
        let allWorking = HostHealthOverview(
            local: .working,
            remote: RemoteHostHealthSnapshot(
                hosts: [first, second],
                healthByHostID: [
                    first.id: .working(checkedAt: checkedAt),
                    second.id: .working(checkedAt: checkedAt),
                ]
            )
        )

        XCTAssertEqual(allWorking.totalCount, 3)
        XCTAssertEqual(allWorking.workingCount, 3)
        XCTAssertTrue(allWorking.allWorking)
        XCTAssertEqual(allWorking.badgeDetailText, "hosts working")
        XCTAssertTrue(allWorking.toolTipText.contains("This Mac: Working"))
        XCTAssertTrue(allWorking.toolTipText.contains("Build box: Working"))
        XCTAssertTrue(allWorking.toolTipText.contains("Home server: Working"))

        let mixed = HostHealthOverview(
            local: .working,
            remote: RemoteHostHealthSnapshot(
                hosts: [first, second],
                healthByHostID: [
                    first.id: .working(checkedAt: checkedAt),
                    second.id: .unreachable(
                        message: "No route to host",
                        checkedAt: checkedAt
                    ),
                ]
            )
        )
        XCTAssertEqual(mixed.totalCount, 3)
        XCTAssertEqual(mixed.workingCount, 2)
        XCTAssertEqual(mixed.problemCount, 1)
        XCTAssertFalse(mixed.allWorking)
        XCTAssertEqual(mixed.badgeDetailText, "hosts · 2 working")
        XCTAssertTrue(
            mixed.toolTipText.contains("Home server: Offline — No route to host")
        )
        XCTAssertTrue(mixed.toolTipText.hasSuffix("Click to open Connections."))
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
}
