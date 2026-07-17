import AppKit
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class ActiveTaskContextTests: CodexNotchTestCase {
    func testLegacyV1SnapshotDecodesWithoutContextFields() throws {
        let data = Data("""
        {
          "schema_version": 1,
          "generation": "11111111-1111-4111-8111-111111111111",
          "sequence": 1,
          "generated_at": "2026-07-18T08:00:00Z",
          "tasks": [{
            "thread_id": "\(threadID)",
            "title": "Legacy task",
            "state": "running",
            "updated_at": "2026-07-18T08:00:00Z"
          }]
        }
        """.utf8)

        let snapshot = try JSONDecoder.codexNotch.decode(ActiveTaskSnapshot.self, from: data)

        XCTAssertTrue(snapshot.isValid)
        XCTAssertNil(snapshot.tasks[0].parentThreadID)
        XCTAssertNil(snapshot.tasks[0].projectLabel)
        XCTAssertNil(snapshot.tasks[0].branch)
    }

    func testSnapshotValidationRejectsAFullPathDisguisedAsProjectContext() {
        let event = ActiveTaskEvent(
            threadID: threadID,
            title: "Unsafe context",
            state: .running,
            updatedAt: Date(),
            projectLabel: "/Users/ralf/private/repository"
        )

        XCTAssertFalse(event.isValid)
    }

    func testLocalProjectionIncludesNestedAgentsAndSanitizedContext() throws {
        let rootID = "019f5d4f-3a8d-76c0-8c2d-19451190e020"
        let childID = "019f5d4f-3a8d-76c0-8c2d-19451190e021"
        let grandchildID = "019f5d4f-3a8d-76c0-8c2d-19451190e022"
        let rows: [[String: Any]] = [
            [
                "id": rootID,
                "name": "Ship Codex Notch",
                "status": ["type": "active", "activeFlags": []],
                "parentThreadId": NSNull(),
                "updatedAt": 1_784_352_000,
                "cwd": "/Users/ralf/private/codex-notch",
                "gitInfo": [
                    "branch": "codex/attention-workflow",
                    "originUrl": "git@github.com:private/secret.git",
                ],
            ],
            [
                "id": childID,
                "name": "Implement context",
                "status": ["type": "active", "activeFlags": []],
                "parentThreadId": rootID,
                "updatedAt": 1_784_352_001,
                "cwd": "/Users/ralf/private/codex-notch",
                "gitInfo": ["branch": "codex/attention-workflow"],
                "agentNickname": "Atlas",
                "agentRole": "worker",
            ],
            [
                "id": grandchildID,
                "name": "Verify privacy",
                "status": ["type": "active", "activeFlags": ["waitingOnUserInput"]],
                "parentThreadId": childID,
                "updatedAt": 1_784_352_002,
                "cwd": "/Users/ralf/private/codex-notch",
                "gitInfo": ["branch": "codex/attention-workflow"],
            ],
        ]

        let events = AppServerThreadProjection.activeEvents(
            from: rows,
            observedAt: Date(timeIntervalSince1970: 1_784_352_010)
        )

        XCTAssertEqual(events.count, 3)
        let child = try XCTUnwrap(events.first { $0.threadID == childID })
        let grandchild = try XCTUnwrap(events.first { $0.threadID == grandchildID })
        XCTAssertEqual(child.parentThreadID, rootID)
        XCTAssertEqual(child.rootThreadID, rootID)
        XCTAssertEqual(child.rootTitle, "Ship Codex Notch")
        XCTAssertEqual(child.projectLabel, "codex-notch")
        XCTAssertEqual(child.branch, "codex/attention-workflow")
        XCTAssertEqual(child.agentNickname, "Atlas")
        XCTAssertEqual(child.agentRole, "worker")
        XCTAssertEqual(grandchild.rootThreadID, rootID)

        let snapshot = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: Date(),
            tasks: events
        )
        let encoded = String(
            decoding: try JSONEncoder.codexNotch.encode(snapshot),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("/Users/ralf/private"))
        XCTAssertFalse(encoded.contains("originUrl"))
        XCTAssertFalse(encoded.contains("secret.git"))
    }

    func testStoreRollsNestedAgentsIntoRootAndElevatesAttention() throws {
        let rootID = "019f5d4f-3a8d-76c0-8c2d-19451190e040"
        let childID = "019f5d4f-3a8d-76c0-8c2d-19451190e041"
        let grandchildID = "019f5d4f-3a8d-76c0-8c2d-19451190e042"
        let now = Date(timeIntervalSince1970: 1_784_352_000)
        let snapshot = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: now,
            tasks: [
                ActiveTaskEvent(
                    threadID: rootID,
                    title: "Parent task",
                    state: .running,
                    updatedAt: now,
                    rootThreadID: rootID,
                    projectLabel: "codex-notch",
                    branch: "codex/attention-workflow"
                ),
                ActiveTaskEvent(
                    threadID: childID,
                    title: "Working child",
                    state: .running,
                    updatedAt: now.addingTimeInterval(1),
                    parentThreadID: rootID,
                    rootThreadID: rootID,
                    rootTitle: "Parent task"
                ),
                ActiveTaskEvent(
                    threadID: grandchildID,
                    title: "Blocked grandchild",
                    state: .waitingForInput,
                    updatedAt: now.addingTimeInterval(2),
                    parentThreadID: childID,
                    rootThreadID: rootID,
                    rootTitle: "Parent task"
                ),
            ]
        )
        let store = ActiveTaskStore(now: { now })

        XCTAssertTrue(store.replace(
            sourceID: "local",
            sourceLabel: "This Mac",
            snapshot: snapshot,
            receivedAt: now
        ))

        let task = try XCTUnwrap(store.tasks.only)
        XCTAssertEqual(task.threadID, rootID)
        XCTAssertEqual(task.title, "Parent task")
        XCTAssertEqual(task.state, .waitingForInput)
        XCTAssertEqual(task.projectLabel, "codex-notch")
        XCTAssertEqual(task.branch, "codex/attention-workflow")
        XCTAssertEqual(task.subagentCount, 2)
        XCTAssertEqual(task.runningSubagentCount, 1)
        XCTAssertEqual(task.attentionSubagentCount, 1)
    }

    func testChildOnlySnapshotSynthesizesAParentRollup() throws {
        let parentID = "019f5d4f-3a8d-76c0-8c2d-19451190e050"
        let childID = "019f5d4f-3a8d-76c0-8c2d-19451190e051"
        let now = Date(timeIntervalSince1970: 1_784_352_000)
        let store = ActiveTaskStore(now: { now })
        let snapshot = ActiveTaskSnapshot(
            generation: UUID().uuidString.lowercased(),
            sequence: 1,
            generatedAt: now,
            tasks: [ActiveTaskEvent(
                threadID: childID,
                title: "Child task",
                state: .waitingForApproval,
                updatedAt: now,
                parentThreadID: parentID,
                rootThreadID: parentID,
                rootTitle: "Parent task",
                projectLabel: "codex-notch"
            )]
        )

        XCTAssertTrue(store.replace(
            sourceID: "local",
            sourceLabel: "This Mac",
            snapshot: snapshot,
            receivedAt: now
        ))

        let task = try XCTUnwrap(store.tasks.only)
        XCTAssertEqual(task.threadID, parentID)
        XCTAssertEqual(task.title, "Parent task")
        XCTAssertEqual(task.state, .waitingForApproval)
        XCTAssertEqual(task.subagentCount, 1)
        XCTAssertEqual(task.attentionSubagentCount, 1)
    }

    func testActiveRowPresentsIdentityOnASecondLine() {
        let task = ActiveTask(
            threadID: threadID,
            title: "Build context",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .waitingForInput,
            updatedAt: Date(),
            projectLabel: "codex-notch",
            branch: "codex/attention-workflow",
            subagentCount: 2,
            runningSubagentCount: 1,
            attentionSubagentCount: 1
        )

        let row = ActiveTaskRowView(
            task: task,
            index: 0,
            theme: NotchTheme.all[0],
            open: {}
        )

        XCTAssertEqual(row.statusTextForTesting, "Needs input")
        XCTAssertTrue(row.contextTextForTesting.contains("This Mac"))
        XCTAssertTrue(row.contextTextForTesting.contains("codex-notch"))
        XCTAssertTrue(row.contextTextForTesting.contains("codex/attention-workflow"))
        XCTAssertTrue(row.contextTextForTesting.contains("2 subagents"))
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
