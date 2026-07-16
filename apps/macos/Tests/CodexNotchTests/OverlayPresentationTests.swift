import AppKit
import Carbon
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class OverlayPresentationTests: CodexNotchTestCase {
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
            92,
            accuracy: 0.5
        )
        XCTAssertGreaterThanOrEqual(overlay.notchWidthForTesting, 80)
        XCTAssertEqual(try! XCTUnwrap(overlay.headerTopInsetForTesting), 0, accuracy: 0.5)

        let view = try! XCTUnwrap(overlay.contentViewForTesting)
        view.layoutSubtreeIfNeeded()
        let closedPath = try! XCTUnwrap((view.layer?.mask as? CAShapeLayer)?.path)
        XCTAssertTrue(closedPath.contains(CGPoint(x: view.bounds.midX, y: view.bounds.maxY - 1)))
        XCTAssertFalse(closedPath.contains(CGPoint(x: 1, y: view.bounds.maxY - 1)))
        XCTAssertFalse(closedPath.contains(CGPoint(x: view.bounds.midX, y: 1)))

        overlay.toggle()
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)
        let expandedView = try! XCTUnwrap(overlay.contentViewForTesting)
        expandedView.layoutSubtreeIfNeeded()
        let expandedPath = try! XCTUnwrap(
            (expandedView.layer?.mask as? CAShapeLayer)?.path
        )
        let expandedBounds = expandedPath.boundingBoxOfPath
        XCTAssertEqual(expandedBounds.minX, 0, accuracy: 0.5)
        XCTAssertEqual(expandedBounds.maxX, expandedView.bounds.maxX, accuracy: 0.5)
        XCTAssertGreaterThan(expandedBounds.maxY, expandedView.bounds.maxY)
        XCTAssertTrue(expandedPath.contains(CGPoint(x: expandedView.bounds.midX, y: 1)))
        XCTAssertFalse(expandedPath.contains(CGPoint(x: 1, y: 1)))
        let expandedBodyInset = (
            expandedView.bounds.width - overlay.bodyWidthForTesting
        ) / 2
        XCTAssertTrue(expandedPath.contains(CGPoint(x: expandedBodyInset + 29, y: 1)))
        overlay.hide(immediately: true)
        overlay.showForEvent()
        XCTAssertTrue(overlay.hasHideTimerForTesting)
        overlay.hide(immediately: true)
    }

    func testCompletionRelativeTimeUsesCompactStableUnits() {
        let now = Date(timeIntervalSince1970: 1_784_500_000)

        XCTAssertEqual(CompletionRelativeTime.text(since: now, now: now), "Just now")
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(-59), now: now),
            "Just now"
        )
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(-60), now: now),
            "1 min ago"
        )
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(-3_599), now: now),
            "59 min ago"
        )
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(-3_600), now: now),
            "1 hr ago"
        )
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(-86_400), now: now),
            "1 d ago"
        )
        XCTAssertEqual(
            CompletionRelativeTime.text(since: now.addingTimeInterval(30), now: now),
            "Just now",
            "Remote clock skew must not produce a negative age"
        )
    }

    func testStopHookOpeningShowsOnlyItsTaskAndKeepsRelativeAgeFresh() {
        _ = NSApplication.shared
        var now = Date(timeIntervalSince1970: 1_784_500_000)
        let newest = CompletedTask(
            eventID: String(repeating: "1", count: 64),
            title: "Newest task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: now.addingTimeInterval(-10)
        )
        let triggering = CompletedTask(
            eventID: String(repeating: "2", count: 64),
            title: "Task that opened the notch",
            url: URL(string: "codex://threads/019f5d4f-3a8d-76c0-8c2d-19451190e029")!,
            receivedAt: now.addingTimeInterval(-3 * 60)
        )
        let overlay = OverlayController(now: { now }, shouldReduceMotion: { true })
        overlay.update(tasks: [newest, triggering])

        XCTAssertEqual(overlay.taskRelativeTimesForTesting, ["Just now", "3 min ago"])
        XCTAssertTrue(overlay.triggeredTaskEventIDsForTesting.isEmpty)
        let fullHeight = overlay.bodyHeightForTesting

        overlay.showForEvent(triggeringEventID: triggering.eventID)

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.isTriggeredPresentationForTesting)
        XCTAssertEqual(overlay.shortcutTaskTitlesForTesting, [triggering.title])
        XCTAssertLessThan(overlay.bodyHeightForTesting, fullHeight)
        XCTAssertEqual(overlay.triggeredTaskEventIDsForTesting, [triggering.eventID])

        now.addTimeInterval(2 * 60)
        overlay.refreshRelativeTimesForTesting()
        XCTAssertEqual(overlay.taskRelativeTimesForTesting, ["5 min ago"])

        overlay.hide(immediately: true)
        XCTAssertTrue(overlay.triggeredTaskEventIDsForTesting.isEmpty)
        overlay.toggle()
        XCTAssertTrue(
            overlay.triggeredTaskEventIDsForTesting.isEmpty,
            "A later manual opening must not reuse an old stop-hook highlight"
        )
        overlay.hide(immediately: true)
    }

    func testShortcutPromotesTriggeredTaskToFullNotchWithCriticalSpring() {
        _ = NSApplication.shared
        let first = CompletedTask(
            eventID: String(repeating: "8", count: 64),
            title: "Newer completed task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let triggering = CompletedTask(
            eventID: String(repeating: "9", count: 64),
            title: "Task that triggered the compact notch",
            url: URL(string: "codex://threads/019f5d4f-3a8d-76c0-8c2d-19451190e029")!,
            receivedAt: Date().addingTimeInterval(-60)
        )
        let overlay = OverlayController(shouldReduceMotion: { false })
        overlay.update(tasks: [first, triggering])
        overlay.showForEvent(triggeringEventID: triggering.eventID)
        let compactHeight = overlay.bodyHeightForTesting

        overlay.toggle()

        XCTAssertFalse(overlay.isTriggeredPresentationForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)
        XCTAssertEqual(
            overlay.shortcutTaskTitlesForTesting,
            [first.title, triggering.title]
        )
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, compactHeight)
        XCTAssertTrue(overlay.hasPromotionSpringForTesting)
        XCTAssertEqual(
            try! XCTUnwrap(overlay.promotionDampingRatioForTesting),
            1,
            accuracy: 0.001
        )
        XCTAssertTrue(overlay.triggeredRowHasPromotionAnimationForTesting)
        overlay.hide(immediately: true)
    }

    func testHoverPromotesTriggeredTaskAndResumesAutoHideAfterExit() {
        _ = NSApplication.shared
        let triggering = CompletedTask(
            eventID: String(repeating: "a", count: 64),
            title: "Hover to see the full task list",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let other = CompletedTask(
            eventID: String(repeating: "b", count: 64),
            title: "Another completed task",
            url: URL(string: "codex://threads/019f5d4f-3a8d-76c0-8c2d-19451190e029")!,
            receivedAt: Date().addingTimeInterval(-60)
        )
        let overlay = OverlayController(shouldReduceMotion: { false })
        overlay.update(tasks: [triggering, other])
        overlay.showForEvent(triggeringEventID: triggering.eventID)

        overlay.contentHoverChangedForTesting(true)

        XCTAssertFalse(overlay.isTriggeredPresentationForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)
        XCTAssertEqual(
            overlay.shortcutTaskTitlesForTesting,
            [triggering.title, other.title]
        )
        XCTAssertTrue(overlay.hasPromotionSpringForTesting)

        overlay.contentHoverChangedForTesting(false)
        XCTAssertTrue(overlay.hasHideTimerForTesting)
        overlay.hide(immediately: true)
    }

    func testReducedMotionUsesFadeWhenPromotingTriggeredTask() {
        _ = NSApplication.shared
        let triggering = CompletedTask(
            eventID: String(repeating: "c", count: 64),
            title: "Reduced-motion trigger",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let overlay = OverlayController(shouldReduceMotion: { true })
        overlay.update(tasks: [triggering])
        overlay.showForEvent(triggeringEventID: triggering.eventID)

        overlay.contentHoverChangedForTesting(true)

        XCTAssertFalse(overlay.isTriggeredPresentationForTesting)
        XCTAssertFalse(overlay.hasPromotionSpringForTesting)
        XCTAssertTrue(overlay.hasContentAnimationForTesting)
        overlay.hide(immediately: true)
    }

    func testShortcutCanInterruptAClosingTriggeredNotch() {
        _ = NSApplication.shared
        let triggering = CompletedTask(
            eventID: String(repeating: "d", count: 64),
            title: "Reopen while the compact notch is closing",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let overlay = OverlayController(shouldReduceMotion: { false })
        overlay.update(tasks: [triggering])
        overlay.showForEvent(triggeringEventID: triggering.eventID)
        overlay.hide()

        overlay.toggle()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.isTriggeredPresentationForTesting)
        XCTAssertTrue(overlay.hasPromotionSpringForTesting)
        overlay.hide(immediately: true)
    }

    func testCompletedTaskRowTimeAndHighlightFitWithoutAmbiguousLayout() {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let task = CompletedTask(
            eventID: String(repeating: "3", count: 64),
            title: "A task title that can yield space before fixed metadata truncates",
            sourceLabel: "ralfs-ubuntu",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: now.addingTimeInterval(-59 * 60)
        )
        let row = TaskRowView(
            task: task,
            index: 0,
            theme: NotchTheme.all[0],
            now: now,
            isTriggered: true,
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
        XCTAssertEqual(row.relativeTimeTextForTesting, "59 min ago")
        XCTAssertTrue(row.isTriggeredForTesting)
    }

    func testMenuBarHeaderReservesTheMeasuredHardwareNotch() {
        let exclusion = try! XCTUnwrap(OverlayGeometry.menuBarNotchExclusion(
            notchWidth: 180,
            centerOffset: 12,
            hasHardwareNotch: true
        ))

        XCTAssertEqual(exclusion.lowerBound, -88, accuracy: 0.5)
        XCTAssertEqual(exclusion.upperBound, 112, accuracy: 0.5)
        XCTAssertNil(OverlayGeometry.menuBarNotchExclusion(
            notchWidth: 180,
            centerOffset: 12,
            hasHardwareNotch: false
        ))
    }

    func testNotchHoverTargetTracksTheMeasuredNotchFootprint() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let notch = ScreenNotchGeometry(
            screenFrame: screenFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 944),
            safeTop: 38,
            leftArea: NSRect(x: 0, y: 944, width: 656, height: 38),
            rightArea: NSRect(x: 856, y: 944, width: 656, height: 38)
        )
        let target = NotchHoverTarget.rect(screenFrame: screenFrame, notch: notch)

        XCTAssertTrue(notch.hasHardwareNotch)
        XCTAssertEqual(notch.width, 200, accuracy: 0.5)
        XCTAssertEqual(target.width, 220, accuracy: 0.5)
        XCTAssertEqual(target.height, 38, accuracy: 0.5)
        XCTAssertTrue(target.contains(NSPoint(x: 756, y: 970)))
        XCTAssertFalse(target.contains(NSPoint(x: 500, y: 970)))
        XCTAssertFalse(target.contains(NSPoint(x: 756, y: 930)))
    }

    func testNotchHoverIntentDwellsOnceAndRearmsAfterLeaving() {
        var intent = NotchHoverIntent(dwellDuration: 0.14)

        XCTAssertFalse(intent.update(isInside: true, at: 1.00))
        XCTAssertFalse(intent.update(isInside: true, at: 1.13))
        XCTAssertTrue(intent.update(isInside: true, at: 1.15))
        XCTAssertFalse(intent.update(isInside: true, at: 2.00))
        XCTAssertFalse(intent.update(isInside: false, at: 2.01))
        XCTAssertFalse(intent.update(isInside: true, at: 2.02))
        XCTAssertTrue(intent.update(isInside: true, at: 2.17))
    }

    func testNotchHoverUsesSmoothUnpinnedPresentationEvenWhenEmpty() throws {
        _ = NSApplication.shared
        var modifiersHeld = false
        let overlay = OverlayController(
            shouldReduceMotion: { false },
            shortcutModifierState: { modifiersHeld }
        )
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)

        XCTAssertFalse(overlay.hasContent)
        overlay.showFromNotchHover(on: screen)

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.hasHideTimerForTesting)
        XCTAssertTrue(overlay.hasContentAnimationForTesting)
        XCTAssertEqual(overlay.hoverOpenDurationForTesting, 0.32, accuracy: 0.001)

        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()
        XCTAssertFalse(overlay.isPinnedForTesting)
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

    func testControlShiftMakesAnAutomaticEventOpeningPersistent() {
        _ = NSApplication.shared
        var modifiersHeld = false
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            shortcutModifierState: { modifiersHeld }
        )
        overlay.update(tasks: [CompletedTask(
            eventID: String(repeating: "e", count: 64),
            title: "Finished while working",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )])

        overlay.showForEvent()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertFalse(overlay.isPinnedForTesting)
        XCTAssertTrue(overlay.hasHideTimerForTesting)

        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()

        XCTAssertTrue(overlay.isShortcutOrderLockedForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()

        XCTAssertFalse(overlay.isShortcutOrderLockedForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertFalse(overlay.hasHideTimerForTesting)
        XCTAssertTrue(overlay.isVisibleForTesting)
        overlay.hide(immediately: true)
    }

    func testControlShiftLocksVisibleTaskOrderUntilReleased() {
        _ = NSApplication.shared
        var modifiersHeld = false
        let first = CompletedTask(
            eventID: String(repeating: "a", count: 64),
            title: "First task",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let incoming = CompletedTask(
            eventID: String(repeating: "b", count: 64),
            title: "Incoming task",
            url: URL(string: "codex://threads/019f5d4f-3a8d-76c0-8c2d-19451190e029")!,
            receivedAt: Date().addingTimeInterval(1)
        )
        let initialActive = ActiveTask(
            threadID: "019f5d4f-3a8d-76c0-8c2d-19451190e030",
            title: "Initial active task",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .running,
            updatedAt: Date()
        )
        let incomingActive = ActiveTask(
            threadID: "019f5d4f-3a8d-76c0-8c2d-19451190e031",
            title: "Incoming active task",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .waitingForInput,
            updatedAt: Date().addingTimeInterval(1)
        )
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            shortcutModifierState: { modifiersHeld }
        )
        overlay.update(tasks: [first])
        overlay.update(activeTasks: [initialActive], visible: true)
        overlay.toggle()

        XCTAssertEqual(
            overlay.shortcutHintTextForTesting,
            GlobalHotKeys.toggleShortcutLabel()
        )
        XCTAssertFalse(overlay.isActiveFreezeIndicatorVisibleForTesting)

        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()
        let lockedHeight = overlay.bodyHeightForTesting
        XCTAssertTrue(overlay.isShortcutOrderLockedForTesting)
        XCTAssertEqual(
            overlay.shortcutHintTextForTesting,
            GlobalHotKeys.toggleShortcutLabel()
        )
        XCTAssertTrue(overlay.isActiveFreezeIndicatorVisibleForTesting)
        XCTAssertTrue(overlay.isActiveFreezeIndicatorBesideSectionForTesting)
        XCTAssertEqual(overlay.activeFreezeTextForTesting, "· FROZEN")
        XCTAssertEqual(
            overlay.activeFreezeToolTipForTesting,
            "Live updates pause while you hold Control–Shift so task shortcuts stay stable. Release the keys to resume."
        )
        XCTAssertEqual(
            overlay.shortcutTaskTitlesForTesting,
            ["Initial active task", "First task"]
        )
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["J", "K"])

        overlay.update(tasks: [incoming, first])
        overlay.update(activeTasks: [incomingActive], visible: true)

        XCTAssertEqual(overlay.bodyHeightForTesting, lockedHeight, accuracy: 0.5)
        XCTAssertEqual(
            overlay.shortcutTaskTitlesForTesting,
            ["Initial active task", "First task"]
        )
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["J", "K"])
        var openedActiveTitle: String?
        var openedTitle: String?
        overlay.onOpenActive = { task in
            openedActiveTitle = task.title
            return false
        }
        overlay.onOpen = { task in
            openedTitle = task.title
            return false
        }
        overlay.openTask(at: 0, animated: false)
        overlay.openTask(at: 1, animated: false)
        XCTAssertEqual(openedActiveTitle, "Initial active task")
        XCTAssertEqual(openedTitle, "First task")

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()

        XCTAssertFalse(overlay.isShortcutOrderLockedForTesting)
        XCTAssertEqual(
            overlay.shortcutHintTextForTesting,
            GlobalHotKeys.toggleShortcutLabel()
        )
        XCTAssertFalse(overlay.isActiveFreezeIndicatorVisibleForTesting)
        XCTAssertEqual(
            overlay.shortcutTaskTitlesForTesting,
            ["Incoming active task", "Incoming task", "First task"]
        )
        XCTAssertEqual(overlay.taskBadgeTextsForTesting, ["1", "2", "3"])
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, lockedHeight)
        overlay.openTask(at: 0, animated: false)
        overlay.openTask(at: 1, animated: false)
        XCTAssertEqual(openedActiveTitle, "Incoming active task")
        XCTAssertEqual(openedTitle, "Incoming task")
        overlay.hide(immediately: true)
    }

    func testStopHookHighlightWaitsForShortcutFreezeToEnd() {
        _ = NSApplication.shared
        var modifiersHeld = false
        let first = CompletedTask(
            eventID: String(repeating: "6", count: 64),
            title: "Visible before shortcuts freeze",
            url: URL(string: "codex://threads/\(threadID)")!,
            receivedAt: Date()
        )
        let incoming = CompletedTask(
            eventID: String(repeating: "7", count: 64),
            title: "Finished while shortcuts are frozen",
            url: URL(string: "codex://threads/019f5d4f-3a8d-76c0-8c2d-19451190e029")!,
            receivedAt: Date()
        )
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            shortcutModifierState: { modifiersHeld }
        )
        overlay.update(tasks: [first])
        overlay.toggle()
        modifiersHeld = true
        overlay.refreshShortcutModifierStateForTesting()

        overlay.update(tasks: [incoming, first])
        overlay.showForEvent(triggeringEventID: incoming.eventID)

        XCTAssertTrue(overlay.triggeredTaskEventIDsForTesting.isEmpty)
        XCTAssertEqual(overlay.shortcutTaskTitlesForTesting, [first.title])

        modifiersHeld = false
        overlay.refreshShortcutModifierStateForTesting()

        XCTAssertEqual(overlay.triggeredTaskEventIDsForTesting, [incoming.eventID])
        XCTAssertEqual(overlay.shortcutTaskTitlesForTesting, [incoming.title, first.title])
        overlay.hide(immediately: true)
    }
}
