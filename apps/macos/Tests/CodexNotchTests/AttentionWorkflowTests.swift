import AppKit
import XCTest
@testable import CodexNotchApp

final class AttentionWorkflowTests: CodexNotchTestCase {
    func testPolicyKeepsFrequentAndLowPrioritySignalsCalm() {
        XCTAssertEqual(
            AttentionPolicy.disposition(for: .completion, mode: .notify),
            .expand(playSound: true)
        )
        XCTAssertEqual(
            AttentionPolicy.disposition(for: .update, mode: .notify),
            .glance
        )
        XCTAssertEqual(
            AttentionPolicy.disposition(for: .completion, mode: .glance),
            .glance
        )
        XCTAssertEqual(
            AttentionPolicy.disposition(for: .input, mode: .glance),
            .expand(playSound: false)
        )
        XCTAssertEqual(
            AttentionPolicy.disposition(for: .completion, mode: .quiet),
            .collectSilently
        )
    }

    func testCoordinatorDeduplicatesSignalsAndClearsGlancesWhenSeen() throws {
        let suite = "CodexNotchTests.AttentionCoordinator.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AttentionPreferences(defaults: defaults)
        preferences.mode = .glance
        let coordinator = AttentionCoordinator(preferences: preferences)
        var counts: [Int] = []
        var expansions: [AttentionEvent] = []
        coordinator.onGlanceCountChanged = { counts.append($0) }
        coordinator.onExpand = { expansions.append($0) }

        let event = AttentionEvent(id: "completion:1", kind: .completion)
        coordinator.receive(event)
        coordinator.receive(event)

        XCTAssertEqual(coordinator.unseenCount, 1)
        XCTAssertEqual(counts, [1])
        XCTAssertTrue(expansions.isEmpty)

        coordinator.markSeen()
        XCTAssertEqual(coordinator.unseenCount, 0)
        XCTAssertEqual(counts, [1, 0])
    }

    func testGlancesMatchInspectableGroupsAndVisibleContentIsAlreadySeen() throws {
        let suite = "CodexNotchTests.AttentionGroups.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AttentionPreferences(defaults: defaults)
        preferences.mode = .glance
        let coordinator = AttentionCoordinator(preferences: preferences)
        var presentedCounts: [Int] = []
        coordinator.onGlanceCountChanged = { presentedCounts.append($0) }

        coordinator.receive(AttentionEvent(
            id: "completion:event-1",
            kind: .completion,
            groupID: "completion:thread-1"
        ))
        coordinator.receive(AttentionEvent(
            id: "completion:event-2",
            kind: .completion,
            groupID: "completion:thread-1"
        ))
        coordinator.receive(
            AttentionEvent(id: "update:1", kind: .update, groupID: "update"),
            isSurfaceVisible: true
        )

        XCTAssertEqual(coordinator.unseenCount, 1)
        preferences.mode = .quiet
        XCTAssertEqual(coordinator.unseenCount, 1, "Quiet hides the signal without erasing it")
        preferences.mode = .notify
        XCTAssertEqual(coordinator.unseenCount, 1, "Changing mode must not mark content seen")
        XCTAssertEqual(presentedCounts, [1, 0, 1])

        coordinator.retainCompletionGroups([])
        XCTAssertEqual(coordinator.unseenCount, 0)
        XCTAssertEqual(presentedCounts, [1, 0, 1, 0])
    }

    func testNotifyCompletionExpandsAndPlaysSoundWhileUpdateOnlyGlances() throws {
        let suite = "CodexNotchTests.AttentionNotify.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AttentionCoordinator(
            preferences: AttentionPreferences(defaults: defaults)
        )
        var expandedIDs: [String] = []
        var soundCount = 0
        var glanceCounts: [Int] = []
        coordinator.onExpand = { expandedIDs.append($0.id) }
        coordinator.onPlaySound = { soundCount += 1 }
        coordinator.onGlanceCountChanged = { glanceCounts.append($0) }

        coordinator.receive(AttentionEvent(id: "completion:1", kind: .completion))
        coordinator.receive(AttentionEvent(id: "update:1", kind: .update))

        XCTAssertEqual(expandedIDs, ["completion:1"])
        XCTAssertEqual(soundCount, 1)
        XCTAssertEqual(glanceCounts, [1])
    }

    func testLegacyDoNotDisturbMigratesToQuietAndOutcomesDefaultOn() throws {
        let priorSuite = "CodexNotchTests.AttentionMigrationPrior.\(UUID())"
        let priorDefaults = try XCTUnwrap(UserDefaults(suiteName: priorSuite))
        defer { priorDefaults.removePersistentDomain(forName: priorSuite) }
        _ = AttentionPreferences(defaults: priorDefaults)

        let suite = "CodexNotchTests.AttentionMigration.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: AttentionPreferences.legacyDoNotDisturbKey)

        let preferences = AttentionPreferences(defaults: defaults)
        XCTAssertEqual(preferences.mode, .quiet)
        preferences.mode = .notify
        XCTAssertEqual(
            AttentionPreferences(defaults: defaults).mode,
            .notify,
            "A persisted attention choice must not be replaced by legacy migration"
        )
        XCTAssertTrue(CompletionOutcomePreferences(defaults: defaults).isEnabled)
        XCTAssertEqual(AttentionMode.quiet.headerTitle, "Quiet")
        XCTAssertEqual(AttentionMode.quiet.headerSystemImageName, "moon.fill")
    }

    func testActiveAttentionOnlyFiresAfterBaselineWhenTaskStartsNeedingUser() {
        var tracker = ActiveTaskAttentionTracker()
        let running = ActiveTask(
            threadID: threadID,
            title: "Build release",
            sourceID: "local",
            sourceLabel: "This Mac",
            state: .running,
            updatedAt: Date()
        )
        XCTAssertTrue(tracker.events(for: [running]).isEmpty)

        let needsInput = running.replacingState(.waitingForInput)
        XCTAssertEqual(tracker.events(for: [needsInput]).map(\.kind), [.input])
        XCTAssertTrue(tracker.events(for: [needsInput]).isEmpty)
        _ = tracker.events(for: [running])
        XCTAssertEqual(
            tracker.events(for: [running.replacingState(.waitingForApproval)]).map(\.kind),
            [.approval]
        )
        _ = tracker.events(for: [running.replacingState(.unavailable)])
        XCTAssertEqual(tracker.events(for: [needsInput]).map(\.kind), [.input])
    }

    func testConnectionAttentionFiresOncePerStableProblemIncident() {
        let host = RemoteHost(
            id: "host-1",
            label: "Ubuntu",
            sshAlias: "ubuntu",
            endpointHost: "100.64.0.2",
            createdAt: Date()
        )
        let working = RemoteHostHealthSnapshot(
            hosts: [host],
            healthByHostID: [host.id: .working(checkedAt: Date())]
        )
        let problem = RemoteHostHealthSnapshot(
            hosts: [host],
            healthByHostID: [host.id: .unreachable(message: "Offline", checkedAt: Date())]
        )
        var tracker = ConnectionAttentionTracker()

        XCTAssertNil(tracker.event(for: working))
        let first = tracker.event(for: problem)
        XCTAssertEqual(first?.kind, .connection)
        XCTAssertNil(tracker.event(for: problem))
        XCTAssertNil(tracker.event(for: working))
        let second = tracker.event(for: problem)
        XCTAssertNotEqual(first?.id, second?.id)
    }

    func testGlanceBadgeHangsFromHardwareNotchWithoutMimickingPrivacyDot() {
        let screenFrame = NSRect(x: 0, y: 0, width: 1_512, height: 982)
        let notch = ScreenNotchGeometry(
            screenFrame: screenFrame,
            visibleFrame: NSRect(x: 0, y: 0, width: 1_512, height: 944),
            safeTop: 38,
            leftArea: NSRect(x: 0, y: 944, width: 682, height: 38),
            rightArea: NSRect(x: 830, y: 944, width: 682, height: 38)
        )
        let frame = GlanceBadgePlacement.frame(screenFrame: screenFrame, notch: notch)
        let notchBottom = screenFrame.maxY - notch.height

        XCTAssertEqual(frame.midX, screenFrame.midX, accuracy: 0.5)
        XCTAssertLessThan(frame.minY, notchBottom)
        XCTAssertEqual(
            frame.maxY,
            notchBottom + GlanceBadgePlacement.hardwareAttachmentOverlap,
            accuracy: 0.5
        )
        XCTAssertLessThan(frame.midY, notchBottom)
        XCTAssertGreaterThan(frame.width, frame.height)
    }

    func testGlanceBadgeFitsCappedCountWithoutAmbiguousConstraints() {
        _ = NSApplication.shared
        let badge = GlanceBadgeButton(theme: NotchTheme.all[0])
        badge.update(count: 100, theme: NotchTheme.all[0])
        let host = NSView(frame: NSRect(origin: .zero, size: GlanceBadgePlacement.size))
        host.addSubview(badge)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            badge.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            badge.topAnchor.constraint(equalTo: host.topAnchor),
            badge.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        host.layoutSubtreeIfNeeded()

        XCTAssertEqual(badge.countTextForTesting, "99+")
        XCTAssertFalse(badge.hasAmbiguousLayout)
    }

    func testAttentionSurfaceRequiresAnOpenPanelOnTheActiveSpace() {
        _ = NSApplication.shared
        var isOnActiveSpace = false
        let overlay = OverlayController(
            shouldReduceMotion: { true },
            isWindowOnActiveSpace: { _ in isOnActiveSpace }
        )

        overlay.toggle()
        XCTAssertFalse(overlay.isAttentionSurfaceVisible)
        isOnActiveSpace = true
        XCTAssertTrue(overlay.isAttentionSurfaceVisible)
        overlay.hide(immediately: true)
        XCTAssertFalse(overlay.isAttentionSurfaceVisible)
    }
}
