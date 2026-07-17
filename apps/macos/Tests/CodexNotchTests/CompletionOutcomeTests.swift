import AppKit
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class CompletionOutcomeTests: CodexNotchTestCase {
    func testFormatterSelectsFirstProseParagraphAndRemovesDisplayMarkdown() {
        let message = """
        ## Summary

        ```swift
        let privateImplementation = true
        ```

        Implemented the **auth fix**; [`42 tests`](https://example.com/tests) pass.

        - Added more detail that does not belong in the one-line outcome.
        """

        XCTAssertEqual(
            CompletionOutcomeFormatter.format(message),
            "Implemented the auth fix; 42 tests pass."
        )
    }

    func testFormatterJoinsWrappedProseAndStopsBeforeAList() {
        let message = """
        Fixed the reconnect race and preserved
        the native fallback behavior.
        - Internal implementation detail
        """

        XCTAssertEqual(
            CompletionOutcomeFormatter.format(message),
            "Fixed the reconnect race and preserved the native fallback behavior."
        )
        XCTAssertEqual(
            CompletionOutcomeFormatter.format("- Fixed the crash\n- Added tests"),
            "Fixed the crash"
        )
    }

    func testFormatterIsOptionalAndStrictlyBounded() {
        XCTAssertNil(CompletionOutcomeFormatter.format(nil))
        XCTAssertNil(CompletionOutcomeFormatter.format(" \n```\nsecret\n```\n"))
        XCTAssertEqual(CompletionOutcomeFormatter.format("# Done"), "Done")

        let outcome = CompletionOutcomeFormatter.format(String(repeating: "a", count: 300))
        XCTAssertEqual(outcome?.count, CompletionOutcomeFormatter.maximumLength)
        XCTAssertTrue(outcome?.hasSuffix("…") == true)
    }

    func testStopInputDecodesOptionalLastAssistantMessage() throws {
        let current = try JSONDecoder().decode(
            CodexStopHookInput.self,
            from: Data("""
            {"session_id":"\(threadID)","turn_id":"turn-1","hook_event_name":"Stop",\
            "last_assistant_message":"Implemented the fix."}
            """.utf8)
        )
        XCTAssertEqual(current.lastAssistantMessage, "Implemented the fix.")

        let legacy = try JSONDecoder().decode(
            CodexStopHookInput.self,
            from: Data("""
            {"session_id":"\(threadID)","turn_id":"turn-1","hook_event_name":"Stop"}
            """.utf8)
        )
        XCTAssertNil(legacy.lastAssistantMessage)
    }

    func testOutcomeRoundTripsAndLegacyRecordsRemainDecodable() throws {
        let event = CompletionEvent(
            eventID: CompletionEvent.eventID(threadID: threadID, turnID: "turn-1"),
            threadID: threadID,
            turnID: "turn-1",
            title: "Build the overlay",
            sourceID: "local",
            sourceLabel: "This Mac",
            completedAt: Date(timeIntervalSince1970: 1_784_035_200),
            outcome: "Implemented the **overlay**."
        )
        XCTAssertEqual(event.outcome, "Implemented the overlay.")
        let eventData = try JSONEncoder.codexNotch.encode(event)
        XCTAssertEqual(
            try JSONDecoder.codexNotch.decode(CompletionEvent.self, from: eventData),
            event
        )

        let task = try XCTUnwrap(CompletedTask(event: event))
        XCTAssertEqual(task.outcome, event.outcome)
        let taskData = try JSONEncoder.codexNotch.encode(task)
        XCTAssertEqual(
            try JSONDecoder.codexNotch.decode(CompletedTask.self, from: taskData),
            task
        )

        let legacyEventData = try JSONEncoder.codexNotch.encode(makeEvent())
        XCTAssertNil(
            try JSONDecoder.codexNotch.decode(CompletionEvent.self, from: legacyEventData).outcome
        )

        let legacyTask = CompletedTask(
            eventID: String(repeating: "1", count: 64),
            title: "Legacy task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date(timeIntervalSince1970: 1_784_035_200)
        )
        let legacyTaskData = try JSONEncoder.codexNotch.encode(legacyTask)
        XCTAssertNil(
            try JSONDecoder.codexNotch.decode(CompletedTask.self, from: legacyTaskData).outcome
        )
    }

    func testCompletedRowShowsOutcomeAsASecondaryLine() {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let task = CompletedTask(
            eventID: String(repeating: "2", count: 64),
            title: "Build the overlay",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: now,
            outcome: "Implemented the overlay; tests pass."
        )
        let row = TaskRowView(
            task: task,
            index: 0,
            theme: NotchTheme.all[0],
            now: now,
            isTriggered: false,
            shouldReduceMotion: { true },
            open: {},
            dismiss: {}
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 46))
        host.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            row.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        XCTAssertFalse(row.hasAmbiguousLayout)
        XCTAssertEqual(row.outcomeTextForTesting, task.outcome)

        let hiddenRow = TaskRowView(
            task: task,
            index: 0,
            theme: NotchTheme.all[0],
            now: now,
            isTriggered: false,
            showsOutcome: false,
            shouldReduceMotion: { true },
            open: {},
            dismiss: {}
        )
        XCTAssertNil(hiddenRow.outcomeTextForTesting)
    }
}
