import AppKit
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class AppServerObserverTests: CodexNotchTestCase {
    private let parentID = "019f77e0-1111-7111-8111-111111111110"
    private let childID = "019f77e0-1111-7111-8111-111111111111"
    private let standaloneID = "019f77e0-1111-7111-8111-111111111112"

    func testLoadedThreadReconciliationPaginatesReadsThreadsAndMissingAncestors() throws {
        let client = ScriptedAppServerSocketClient(
            loadedThreadIDs: [childID, standaloneID],
            threads: [
                childID: thread(
                    id: childID,
                    name: "Verify loaded reconciliation",
                    status: ["type": "active", "activeFlags": ["waitingOnUserInput"]],
                    parentID: parentID,
                    updatedAt: 1_784_352_002
                ),
                standaloneID: thread(
                    id: standaloneID,
                    name: "Older active thread outside the first page",
                    status: ["type": "active", "activeFlags": []],
                    updatedAt: 1_784_352_001
                ),
                parentID: thread(
                    id: parentID,
                    name: "Parent outside the first page",
                    status: ["type": "notLoaded"],
                    updatedAt: 1_784_352_000
                ),
            ]
        )
        let observer = observer(client: client)
        let received = expectation(description: "Complete loaded-thread snapshot")
        var snapshot: ActiveTaskSnapshot?
        observer.onSnapshot = { _, _, value in
            snapshot = value
            received.fulfill()
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        let value = try XCTUnwrap(snapshot)
        XCTAssertEqual(value.tasks.count, 2)
        let child = try XCTUnwrap(value.tasks.first { $0.threadID == childID })
        let standalone = try XCTUnwrap(value.tasks.first { $0.threadID == standaloneID })
        XCTAssertEqual(child.state, .waitingForInput)
        XCTAssertEqual(child.parentThreadID, parentID)
        XCTAssertEqual(child.rootThreadID, parentID)
        XCTAssertEqual(child.rootTitle, "Parent outside the first page")
        XCTAssertEqual(standalone.projectLabel, "codex-notch")
        XCTAssertEqual(standalone.branch, "codex/loaded-reconciliation")

        XCTAssertEqual(client.methodCount("thread/list"), 1)
        XCTAssertEqual(client.methodCount("thread/loaded/list"), 2)
        XCTAssertEqual(Set(client.threadReadIDs), Set([childID, standaloneID, parentID]))
        XCTAssertTrue(client.threadReadParams.allSatisfy { $0["includeTurns"] as? Bool == false })
        XCTAssertTrue(Set(client.sentMethods).isSubset(of: [
            "initialize", "initialized", "thread/list", "thread/loaded/list",
            "thread/read", "account/rateLimits/read",
        ]))

        let encoded = String(
            decoding: try JSONEncoder.codexNotch.encode(value),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("/Users/ralf/private"))
        XCTAssertFalse(encoded.contains("secret prompt"))
        XCTAssertFalse(encoded.contains("originUrl"))
        XCTAssertFalse(encoded.contains("secret.git"))
        XCTAssertFalse(encoded.contains("turns"))
    }

    func testOlderServerFallsBackOnceAndKeepsUsingThreadList() throws {
        let legacyRow = thread(
            id: standaloneID,
            name: "Legacy active thread",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )
        let client = ScriptedAppServerSocketClient(
            listRows: [legacyRow],
            loadedListUnavailable: true
        )
        let observer = observer(client: client)
        let received = expectation(description: "Initial and refreshed fallback snapshots")
        received.expectedFulfillmentCount = 2
        var snapshots: [ActiveTaskSnapshot] = []
        observer.onSnapshot = { _, _, value in
            snapshots.append(value)
            received.fulfill()
            if snapshots.count == 1 {
                client.emit(method: "thread/status/changed")
            }
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        XCTAssertEqual(snapshots.count, 2)
        XCTAssertTrue(snapshots.allSatisfy { $0.tasks.map(\.threadID) == [standaloneID] })
        XCTAssertEqual(client.methodCount("thread/list"), 2)
        XCTAssertEqual(client.methodCount("thread/loaded/list"), 1)
        XCTAssertEqual(client.methodCount("thread/read"), 0)
    }

    func testThreadReadSendFailureAbortsWithoutPublishingDemotedSnapshot() throws {
        let row = thread(
            id: standaloneID,
            name: "Still running after a failed write",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_200
        )
        let client = ScriptedAppServerSocketClient(
            listRows: [row],
            loadedThreadIDs: [standaloneID],
            threads: [standaloneID: row],
            threadReadSendFailureCount: 1,
            retryDelay: 0.06
        )
        let observer = observer(client: client, snapshotFailureBackoff: 0.02)
        let received = expectation(description: "Snapshot only after the retry succeeds")
        var snapshots: [ActiveTaskSnapshot] = []
        observer.onSnapshot = { _, _, value in
            snapshots.append(value)
            received.fulfill()
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        XCTAssertEqual(client.methodCount("thread/read"), 2)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.sequence, 1)
        XCTAssertEqual(snapshots.first?.tasks.map(\.threadID), [standaloneID])
    }

    func testTransientLoadedListFailureRemainsRetryable() throws {
        let row = thread(
            id: standaloneID,
            name: "Retry a transient list failure",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_300
        )
        let client = ScriptedAppServerSocketClient(
            listRows: [row],
            loadedThreadIDs: [standaloneID],
            threads: [standaloneID: row],
            loadedListTransientFailureCount: 1,
            retryDelay: 0.06
        )
        let observer = observer(client: client, snapshotFailureBackoff: 0.02)
        let received = expectation(description: "Snapshot after transient loaded-list retry")
        var snapshot: ActiveTaskSnapshot?
        observer.onSnapshot = { _, _, value in
            snapshot = value
            received.fulfill()
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        XCTAssertEqual(client.methodCount("thread/loaded/list"), 2)
        XCTAssertEqual(client.methodCount("thread/read"), 1)
        XCTAssertEqual(snapshot?.sequence, 1)
        XCTAssertEqual(snapshot?.tasks.map(\.threadID), [standaloneID])
    }

    func testLoadedListTimeoutRemainsRetryable() throws {
        let row = thread(
            id: standaloneID,
            name: "Retry a timed-out loaded list",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_400
        )
        let client = ScriptedAppServerSocketClient(
            listRows: [row],
            loadedThreadIDs: [standaloneID],
            threads: [standaloneID: row],
            loadedListDroppedResponseCount: 1,
            retryDelay: 0.06
        )
        let observer = observer(
            client: client,
            snapshotTimeout: 0.02,
            snapshotFailureBackoff: 0.02
        )
        let received = expectation(description: "Snapshot after timed-out loaded-list retry")
        var snapshot: ActiveTaskSnapshot?
        observer.onSnapshot = { _, _, value in
            snapshot = value
            received.fulfill()
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        XCTAssertEqual(client.methodCount("thread/loaded/list"), 2)
        XCTAssertEqual(client.methodCount("thread/read"), 1)
        XCTAssertEqual(snapshot?.sequence, 1)
        XCTAssertEqual(snapshot?.tasks.map(\.threadID), [standaloneID])
    }

    func testLoadedReconciliationBoundsAscendingPaginationAndPrioritizesRecentRows() throws {
        let loadedIDs = (1 ... 75).map { syntheticID($0) }
        let parentIDs = (1 ... 75).map { syntheticID(1_000 + $0) }
        let grandparentIDs = (2 ... 75).map { syntheticID(2_000 + $0) }
        var threads: [String: [String: Any]] = [:]

        for (index, id) in loadedIDs.enumerated() {
            threads[id] = thread(
                id: id,
                name: "Loaded task \(index + 1)",
                status: ["type": "active", "activeFlags": []],
                parentID: parentIDs[index],
                updatedAt: index == 0 ? 1_784_500_000 : 1_784_400_000 + index
            )
        }
        for (index, id) in parentIDs.enumerated() {
            threads[id] = thread(
                id: id,
                name: "Ancestor \(index + 1)",
                status: ["type": "notLoaded"],
                parentID: index == 0 ? nil : syntheticID(2_001 + index),
                updatedAt: 1_784_300_000 - index
            )
        }
        for (index, id) in grandparentIDs.enumerated() {
            threads[id] = thread(
                id: id,
                name: "Deeper ancestor \(index + 2)",
                status: ["type": "notLoaded"],
                updatedAt: 1_784_200_000 - index
            )
        }

        let client = ScriptedAppServerSocketClient(
            // The first ID represents an old, long-running task returned first
            // by updated-descending thread/list. loadedThreadIDs deliberately
            // models upstream's ascending UUID ordering.
            listRows: [threads[loadedIDs[0]]!],
            loadedThreadIDs: loadedIDs,
            threads: threads,
            loadedPageSize: 10
        )
        let observer = observer(client: client)
        let received = expectation(description: "Bounded loaded-thread snapshot")
        var snapshot: ActiveTaskSnapshot?
        observer.onSnapshot = { _, _, value in
            snapshot = value
            received.fulfill()
        }

        observer.start()
        wait(for: [received], timeout: 2)
        observer.stop()

        let value = try XCTUnwrap(snapshot)
        let selectedLoadedIDs = [loadedIDs[0]] + Array(loadedIDs.suffix(49))
        let selectedParentIDs = [parentIDs[0]] + Array(parentIDs.suffix(49))
        let expectedReads = Set(selectedLoadedIDs + selectedParentIDs)
        XCTAssertEqual(value.tasks.count, ActiveTaskSnapshot.maximumTaskCount)
        XCTAssertEqual(client.methodCount("thread/loaded/list"), 8)
        XCTAssertEqual(
            Set(client.loadedListLimits),
            Set([100])
        )
        XCTAssertEqual(client.threadReadIDs.count, 100)
        XCTAssertEqual(Set(client.threadReadIDs), expectedReads)
        XCTAssertTrue(Set(loadedIDs[1 ... 25]).isDisjoint(with: client.threadReadIDs))
        XCTAssertTrue(Set(grandparentIDs).isDisjoint(with: client.threadReadIDs))
        XCTAssertTrue(value.tasks.contains { $0.threadID == loadedIDs.last })

        let first = try XCTUnwrap(value.tasks.first { $0.threadID == loadedIDs[0] })
        XCTAssertEqual(first.rootThreadID, parentIDs[0])
        XCTAssertEqual(first.rootTitle, "Ancestor 1")
    }

    func testLoadedEnumerationFailsClosedAtTenPages() {
        let client = ScriptedAppServerSocketClient(
            loadedThreadIDs: (1 ... 1_001).map { syntheticID(10_000 + $0) },
            loadedPageSize: 100
        )
        let observer = observer(client: client)
        let reachedBound = expectation(description: "Loaded-list request bound reached")
        let exceededBound = expectation(description: "No loaded-list request beyond the bound")
        exceededBound.isInverted = true
        client.onLoadedListRequest = { count in
            if count == 10 { reachedBound.fulfill() }
            if count > 10 { exceededBound.fulfill() }
        }
        var snapshots: [ActiveTaskSnapshot] = []
        observer.onSnapshot = { _, _, value in snapshots.append(value) }

        observer.start()
        wait(for: [reachedBound], timeout: 2)
        wait(for: [exceededBound], timeout: 0.1)
        observer.stop()

        XCTAssertEqual(client.methodCount("thread/loaded/list"), 10)
        XCTAssertEqual(client.methodCount("thread/read"), 0)
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testAbsoluteCycleDeadlineBoundsSlowTrickleAndBacksOffQueuedRefreshes() {
        let loadedIDs = (1 ... 100).map { syntheticID(20_000 + $0) }
        let client = ScriptedAppServerSocketClient(
            loadedThreadIDs: loadedIDs,
            loadedPageSize: 1,
            responseDelay: 0.015,
            loadedListRefreshDelays: [0.005, 0.06, 0.25]
        )
        let observer = observer(
            client: client,
            snapshotTimeout: 0.04,
            snapshotCycleTimeout: 0.06,
            snapshotFailureBackoff: 0.08
        )
        let retriedAfterBackoff = expectation(description: "A later notification retries")
        let timeLock = NSLock()
        var threadListRequestTimes: [UInt64] = []
        client.onThreadListRequest = { count in
            timeLock.lock()
            threadListRequestTimes.append(DispatchTime.now().uptimeNanoseconds)
            timeLock.unlock()
            if count == 2 { retriedAfterBackoff.fulfill() }
        }
        var snapshots: [ActiveTaskSnapshot] = []
        observer.onSnapshot = { _, _, value in snapshots.append(value) }

        observer.start()
        wait(for: [retriedAfterBackoff], timeout: 1)
        observer.stop()

        timeLock.lock()
        let times = threadListRequestTimes
        timeLock.unlock()
        XCTAssertEqual(client.methodCount("thread/list"), 2)
        XCTAssertLessThan(client.methodCount("thread/loaded/list"), 10)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertEqual(times.count, 2)
        if times.count == 2 {
            let elapsed = Double(times[1] - times[0]) / 1_000_000_000
            XCTAssertGreaterThanOrEqual(elapsed, 0.22)
        }
    }

    func testMalformedCycleDropsNotificationFloodUntilFreshPostBackoffSignal() {
        let valid = thread(
            id: standaloneID,
            name: "Known active task",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )
        var malformed = valid
        malformed["status"] = ["type": "active", "activeFlags": "running"]
        let client = ScriptedAppServerSocketClient(
            listRows: [valid],
            loadedThreadIDs: [standaloneID],
            threads: [standaloneID: valid],
            listRowCycles: [[valid], [malformed], [valid]]
        )
        let backoff: TimeInterval = 0.08
        let observer = observer(
            client: client,
            snapshotFailureBackoff: backoff
        )
        let firstSnapshot = expectation(description: "Initial complete snapshot")
        let malformedCycle = expectation(description: "Malformed cycle started")
        let postBackoffRetry = expectation(description: "Fresh notification retries later")
        let timingLock = NSLock()
        var malformedCycleStartedAt: UInt64?
        var retryDelay: TimeInterval?
        var receivedInitialSnapshot = false

        client.onThreadListRequest = { count in
            if count == 2 {
                timingLock.lock()
                malformedCycleStartedAt = DispatchTime.now().uptimeNanoseconds
                timingLock.unlock()
                malformedCycle.fulfill()
                for _ in 0 ..< 32 {
                    client.emit(method: "thread/status/changed")
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) {
                    client.emit(method: "thread/status/changed")
                }
            } else if count == 3 {
                timingLock.lock()
                if let startedAt = malformedCycleStartedAt {
                    retryDelay = Double(DispatchTime.now().uptimeNanoseconds - startedAt)
                        / 1_000_000_000
                }
                timingLock.unlock()
                postBackoffRetry.fulfill()
            }
        }
        observer.onSnapshot = { _, _, _ in
            guard !receivedInitialSnapshot else { return }
            receivedInitialSnapshot = true
            firstSnapshot.fulfill()
        }

        observer.start()
        wait(for: [firstSnapshot], timeout: 2)
        client.emit(method: "thread/status/changed")
        wait(for: [malformedCycle, postBackoffRetry], timeout: 1)
        observer.stop()

        timingLock.lock()
        let measuredRetryDelay = retryDelay
        timingLock.unlock()
        XCTAssertEqual(client.methodCount("thread/list"), 3)
        XCTAssertGreaterThanOrEqual(measuredRetryDelay ?? 0, backoff)
    }

    func testReconciliationRowDropsContentPathsAndGitRemotes() throws {
        let safe = try XCTUnwrap(AppServerThreadProjection.reconciliationRow(from: thread(
            id: standaloneID,
            name: "Privacy projection",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )))

        XCTAssertEqual(safe["projectLabel"] as? String, "codex-notch")
        XCTAssertEqual((safe["gitInfo"] as? [String: Any])?["branch"] as? String,
                       "codex/loaded-reconciliation")
        XCTAssertNil(safe["cwd"])
        XCTAssertNil(safe["preview"])
        XCTAssertNil(safe["turns"])
        XCTAssertNil(safe["path"])
        XCTAssertNil((safe["gitInfo"] as? [String: Any])?["originUrl"])
    }

    func testReconciliationRowRejectsMalformedStatusParentAndFlags() {
        let valid = thread(
            id: standaloneID,
            name: "Strict projection",
            status: ["type": "active", "activeFlags": ["waitingOnUserInput"]],
            updatedAt: 1_784_352_100
        )
        var missingStatus = valid
        missingStatus.removeValue(forKey: "status")
        var invalidParent = valid
        invalidParent["parentThreadId"] = "not-a-thread-id"
        var invalidFlags = valid
        invalidFlags["status"] = ["type": "active", "activeFlags": "waitingOnUserInput"]

        XCTAssertNil(AppServerThreadProjection.reconciliationRow(from: missingStatus))
        XCTAssertNil(AppServerThreadProjection.reconciliationRow(from: invalidParent))
        XCTAssertNil(AppServerThreadProjection.reconciliationRow(from: invalidFlags))
    }

    func testMalformedSecondThreadListRetainsTheLastCompleteSnapshot() {
        let valid = thread(
            id: standaloneID,
            name: "Known active task",
            status: ["type": "active", "activeFlags": ["waitingOnUserInput"]],
            updatedAt: 1_784_352_100
        )
        var malformed = valid
        malformed["status"] = ["type": "active", "activeFlags": "waitingOnUserInput"]
        assertMalformedSecondCycleRetainsSnapshot(
            client: ScriptedAppServerSocketClient(
                listRows: [valid],
                loadedThreadIDs: [standaloneID],
                threads: [standaloneID: valid],
                listRowCycles: [[valid], [malformed]]
            )
        )
    }

    func testMalformedSecondLoadedIDRetainsTheLastCompleteSnapshot() {
        let valid = thread(
            id: standaloneID,
            name: "Known active task",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )
        assertMalformedSecondCycleRetainsSnapshot(
            client: ScriptedAppServerSocketClient(
                listRows: [valid],
                loadedThreadIDs: [standaloneID],
                threads: [standaloneID: valid],
                loadedThreadIDCycles: [[standaloneID], ["not-a-thread-id"]]
            )
        )
    }

    func testMalformedSecondLoadedCursorRetainsTheLastCompleteSnapshot() {
        let valid = thread(
            id: standaloneID,
            name: "Known active task",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )
        assertMalformedSecondCycleRetainsSnapshot(
            client: ScriptedAppServerSocketClient(
                listRows: [valid],
                loadedThreadIDs: [standaloneID],
                threads: [standaloneID: valid],
                loadedNextCursorByCycle: [1: 7]
            )
        )
    }

    func testNonNullErrorAlongsideResultRetainsTheLastCompleteSnapshot() {
        let valid = thread(
            id: standaloneID,
            name: "Known active task",
            status: ["type": "active", "activeFlags": []],
            updatedAt: 1_784_352_100
        )
        assertMalformedSecondCycleRetainsSnapshot(
            client: ScriptedAppServerSocketClient(
                listRows: [valid],
                loadedThreadIDs: [standaloneID],
                threads: [standaloneID: valid],
                loadedErrorByCycle: [
                    1: ["code": -32_000, "message": "Error must win over result"],
                ]
            )
        )
    }

    private func assertMalformedSecondCycleRetainsSnapshot(
        client: ScriptedAppServerSocketClient,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let observer = observer(client: client)
        let first = expectation(description: "Initial complete snapshot")
        let partial = expectation(description: "Malformed cycle must not publish")
        partial.isInverted = true
        var snapshots: [ActiveTaskSnapshot] = []
        observer.onSnapshot = { _, _, snapshot in
            snapshots.append(snapshot)
            if snapshots.count == 1 { first.fulfill() } else { partial.fulfill() }
        }

        observer.start()
        wait(for: [first], timeout: 2)
        client.emit(method: "thread/status/changed")
        wait(for: [partial], timeout: 0.12)
        observer.stop()

        XCTAssertEqual(snapshots.count, 1, file: file, line: line)
        XCTAssertEqual(snapshots.first?.sequence, 1, file: file, line: line)
        XCTAssertEqual(
            snapshots.first?.tasks.map(\.threadID),
            [standaloneID],
            file: file,
            line: line
        )
    }

    private func observer(
        client: ScriptedAppServerSocketClient,
        snapshotTimeout: TimeInterval = 6,
        snapshotCycleTimeout: TimeInterval = 8,
        snapshotFailureBackoff: TimeInterval = 2
    ) -> AppServerObserver {
        AppServerObserver(
            socketCandidates: { ["/tmp/fake-codex.sock"] },
            pathExists: { _ in true },
            clientFactory: { _, queue in
                client.callbackQueue = queue
                return client
            },
            snapshotTimeout: snapshotTimeout,
            snapshotCycleTimeout: snapshotCycleTimeout,
            snapshotFailureBackoff: snapshotFailureBackoff
        )
    }

    private func syntheticID(_ number: Int) -> String {
        let tail = String(format: "%012llx", UInt64(number))
        return "019f77e0-2222-7111-8111-\(tail)"
    }

    private func thread(
        id: String,
        name: String,
        status: [String: Any],
        parentID: String? = nil,
        updatedAt: Int
    ) -> [String: Any] {
        var result: [String: Any] = [
            "id": id,
            "name": name,
            "status": status,
            "updatedAt": updatedAt,
            "cwd": "/Users/ralf/private/codex-notch",
            "gitInfo": [
                "branch": "codex/loaded-reconciliation",
                "originUrl": "git@github.com:private/secret.git",
            ],
            "preview": "secret prompt content",
            "turns": [["items": ["secret transcript"]]],
            "path": "/Users/ralf/private/.codex/sessions/secret.jsonl",
        ]
        if let parentID { result["parentThreadId"] = parentID }
        return result
    }
}
