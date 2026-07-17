import AppKit
import Carbon
import CodexNotchCore
import XCTest
@testable import CodexNotchApp

final class OverlayInteractionTests: CodexNotchTestCase {
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
        func labelTexts(in view: NSView) -> [String] {
            let ownText = (view as? NSTextField).map { [$0.stringValue] } ?? []
            return ownText + view.subviews.flatMap(labelTexts)
        }
        let visibleLabels = labelTexts(in: try! XCTUnwrap(overlay.contentViewForTesting))
        XCTAssertFalse(visibleLabels.contains("2 active · 2 completed"))
        XCTAssertFalse(visibleLabels.contains("2 active"))
        XCTAssertFalse(visibleLabels.contains("2 completed"))

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
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, 140)
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
        XCTAssertGreaterThan(overlay.bodyHeightForTesting, 110)

        overlay.update(activeTasks: [active], visible: false)
        XCTAssertFalse(overlay.hasContent)
        XCTAssertTrue(overlay.hasEmptyStateForTesting)
    }

    func testOverlayShowsCompactAggregateHostHealth() {
        _ = NSApplication.shared
        let overlay = OverlayController(localHostHealth: { .working })
        overlay.toggle()
        let initialBadge = overlay.hostStatusButtonForTesting
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

        XCTAssertTrue(overlay.hostStatusButtonForTesting === initialBadge)
        XCTAssertEqual(overlay.remoteStatusTextForTesting, "Host working")
        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertEqual(overlay.hostStatusCountForTesting, "2")
        XCTAssertEqual(overlay.hostStatusButtonForTesting?.title, "")
        XCTAssertTrue(overlay.hostStatusToolTipForTesting?.contains("This Mac: Working") == true)
        XCTAssertTrue(overlay.hostStatusToolTipForTesting?.contains("Ubuntu: Working") == true)
        XCTAssertTrue(overlay.hostStatusCountColorForTesting?.isEqual(
            NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        ) == true)
        XCTAssertFalse(overlay.headerHasAmbiguousLayoutForTesting)
        XCTAssertFalse(overlay.headerButtonTitlesForTesting.contains("Button"))

        var wasHiddenWhenConnectionsOpened = false
        overlay.onConnections = {
            wasHiddenWhenConnectionsOpened = !overlay.isVisibleForTesting
        }
        overlay.hostStatusButtonForTesting?.performClick(nil)
        XCTAssertTrue(wasHiddenWhenConnectionsOpened)
        XCTAssertFalse(overlay.isVisibleForTesting)
    }

    func testHostStatusBadgeShowsOnlyTheLocalHostCountWithoutRemotes() {
        _ = NSApplication.shared
        let overlay = OverlayController(localHostHealth: { .working })

        overlay.toggle()

        XCTAssertEqual(overlay.hostStatusCountForTesting, "1")
        XCTAssertEqual(overlay.hostStatusButtonForTesting?.title, "")
        XCTAssertTrue(overlay.hostStatusToolTipForTesting?.contains("This Mac: Working") == true)
        overlay.hide(immediately: true)
    }

    func testWeeklyLimitUsesCompactHeaderMetricWithoutGrowingTheBody() throws {
        _ = NSApplication.shared
        let baseline = OverlayController()
        baseline.toggle()
        let baselineHeight = baseline.bodyHeightForTesting
        baseline.hide(immediately: true)

        let overlay = OverlayController()
        overlay.setUsageOverview(CodexUsageOverview(
            limit: CodexWeeklyLimit(
                remainingPercent: 63,
                resetsAt: Date(timeIntervalSince1970: 1_784_487_540)
            ),
            forecast: .lastsThroughReset(pacePercentPerDay: 8),
            recentTrend: CodexUsageTrend(usedPercent: 4, observedFor: 6 * 60 * 60)
        ))

        XCTAssertTrue(overlay.hasContent)
        overlay.toggle()

        XCTAssertEqual(overlay.weeklyUsageTextForTesting, "63%")
        XCTAssertTrue(overlay.weeklyUsageValueFitsForTesting)
        XCTAssertTrue(
            overlay.weeklyUsageToolTipForTesting?.contains(
                "You have 63% of your weekly Codex limit remaining."
            ) == true
        )
        XCTAssertTrue(
            overlay.weeklyUsageToolTipForTesting?.contains(
                "Account-wide, not task context."
            ) == true
        )
        XCTAssertTrue(
            overlay.weeklyUsageToolTipForTesting?.contains(
                "At this pace: lasts through reset"
            ) == true
        )
        XCTAssertTrue(
            overlay.weeklyUsageToolTipForTesting?.contains(
                "Recent change: 4% used over 6h"
            ) == true
        )
        XCTAssertEqual(overlay.weeklyUsageButtonForTesting?.title, "")
        XCTAssertEqual(overlay.bodyHeightForTesting, baselineHeight, accuracy: 0.1)
        let usageFrame = try XCTUnwrap(overlay.weeklyUsageFrameForTesting)
        let hostFrame = try XCTUnwrap(overlay.hostStatusFrameForTesting)
        XCTAssertLessThanOrEqual(usageFrame.maxX + 7, hostFrame.minX + 0.1)
        XCTAssertFalse(overlay.headerHasAmbiguousLayoutForTesting)
        XCTAssertFalse(overlay.headerButtonTitlesForTesting.contains("Button"))
        overlay.hide(immediately: true)
    }

    func testWeeklyUsageHeaderKeepsFailuresVisibleAndRetriesInPlace() throws {
        _ = NSApplication.shared
        let overlay = OverlayController()
        overlay.setUsageState(.loading)
        overlay.toggle()

        XCTAssertTrue(overlay.hasContent)
        XCTAssertEqual(overlay.weeklyUsageTextForTesting, "…")
        let initialButton = try XCTUnwrap(overlay.weeklyUsageButtonForTesting)
        let initialHeight = overlay.bodyHeightForTesting

        overlay.setUsageState(.unavailable(message: "Codex app or CLI was not found"))
        XCTAssertTrue(overlay.weeklyUsageButtonForTesting === initialButton)
        XCTAssertEqual(overlay.weeklyUsageTextForTesting, "—%")
        XCTAssertTrue(
            overlay.weeklyUsageToolTipForTesting?.contains(
                "Codex app or CLI was not found"
            ) == true
        )
        XCTAssertEqual(overlay.weeklyUsageButtonForTesting?.title, "")
        XCTAssertEqual(overlay.bodyHeightForTesting, initialHeight, accuracy: 0.1)

        var retried = false
        overlay.onRefreshUsage = { retried = true }
        overlay.weeklyUsageButtonForTesting?.performClick(nil)
        XCTAssertTrue(retried)
        XCTAssertFalse(overlay.headerHasAmbiguousLayoutForTesting)
        overlay.hide(immediately: true)
    }

    func testWeeklyUsageHeaderKeepsForecastInItsTooltip() {
        _ = NSApplication.shared
        let now = Date(timeIntervalSince1970: 1_784_500_000)
        let overview = CodexUsageOverview(
            limit: CodexWeeklyLimit(
                remainingPercent: 20,
                resetsAt: now.addingTimeInterval(7 * 24 * 60 * 60)
            ),
            forecast: .exhausts(
                estimatedAt: now.addingTimeInterval(8 * 60 * 60),
                pacePercentPerDay: 60
            ),
            recentTrend: CodexUsageTrend(usedPercent: 10, observedFor: 4 * 60 * 60)
        )
        let view = WeeklyUsageHeaderView(
            state: .available(overview),
            theme: NotchTheme.all[0],
            refresh: {}
        )
        view.update(.available(overview), now: now)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 90, height: 22))
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.valueTextForTesting, "20%")
        XCTAssertTrue(view.valueFitsWithoutTruncationForTesting)
        XCTAssertTrue(view.toolTip?.contains("At this pace: ~8h remaining") == true)
        XCTAssertTrue(view.toolTip?.contains("Recent change: 10% used over 4h") == true)
        XCTAssertEqual(view.title, "")
        XCTAssertFalse(view.hasAmbiguousLayout)
        XCTAssertTrue(view.subviews.allSatisfy { !$0.hasAmbiguousLayout })
        XCTAssertEqual(view.frame.height, 22, accuracy: 0.1)
    }

    func testWeeklyUsageHeaderFitsTheWidestPercentageInItsCompactWidth() {
        _ = NSApplication.shared
        let overview = CodexUsageOverview(
            limit: CodexWeeklyLimit(remainingPercent: 100, resetsAt: nil),
            forecast: .learning(observedFor: 0),
            recentTrend: nil
        )
        let view = WeeklyUsageHeaderView(
            state: .available(overview),
            theme: NotchTheme.all[0],
            refresh: {}
        )
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 22))
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.widthAnchor.constraint(equalTo: host.widthAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(view.valueTextForTesting, "100%")
        XCTAssertGreaterThanOrEqual(
            view.valueAllocatedWidthForTesting + 0.5,
            view.valueIntrinsicWidthForTesting,
            "allocated \(view.valueAllocatedWidthForTesting), intrinsic \(view.valueIntrinsicWidthForTesting)"
        )
        XCTAssertEqual(view.frame.width, 50, accuracy: 0.1)
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

    func testOverlayUsesSystemOverlayCollectionBehavior() {
        _ = NSApplication.shared
        let overlay = OverlayController()

        XCTAssertTrue(overlay.panel.isFloatingPanel)
        XCTAssertTrue(overlay.panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(overlay.panel.collectionBehavior.contains(.canJoinAllApplications))
        XCTAssertTrue(overlay.panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(overlay.panel.collectionBehavior.contains(.stationary))
        XCTAssertTrue(overlay.panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testShortcutDoesNotClosePanelVisibleOnAnotherSpace() {
        _ = NSApplication.shared
        let overlay = OverlayController(isWindowOnActiveSpace: { _ in false })
        var visibility: [Bool] = []
        overlay.onVisibilityChanged = { visibility.append($0) }

        overlay.toggle()
        overlay.toggle()

        XCTAssertTrue(overlay.isVisibleForTesting)
        XCTAssertTrue(overlay.isPinnedForTesting)
        XCTAssertEqual(visibility, [true])
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
}
