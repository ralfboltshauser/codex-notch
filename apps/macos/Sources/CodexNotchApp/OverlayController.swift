import AppKit
import CoreGraphics
import QuartzCore
private struct IslandGeometry {
    let windowWidth: CGFloat
    let bodyInset: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchCenterOffset: CGFloat
    let hasHardwareNotch: Bool
}

final class OverlayController {
    static let eventVisibilityDuration: TimeInterval = 5
    private static let hardwareNotchPadding: CGFloat = 10

    private enum Phase {
        case hidden
        case opening
        case open
        case closing
        case launching
    }

    private let panel: FocuslessPanel
    private let shouldReduceMotion: () -> Bool
    private let shortcutModifierState: () -> Bool
    private let automaticOpenAllowed: () -> Bool
    private let localHostHealth: () -> LocalHostHealth
    private let now: () -> Date
    private var tasks: [CompletedTask] = []
    private var activeTasks: [ActiveTask] = []
    private var showsActiveTasks = ActiveTaskPreferences.shared.isVisible
    private var hideTimer: Timer?
    private var shortcutModifierTimer: Timer?
    private var relativeTimeTimer: Timer?
    private var shortcutLettersVisible = false
    private var lockedActiveTasks: [ActiveTask]?
    private var lockedCompletedTasks: [CompletedTask]?
    private var eventAutoCloseCanBeCancelled = false
    private var targetScreen: NSScreen?
    private var isPinned = false
    private var isThemePreviewActive = false
    private var currentBodyInset: CGFloat = 0
    private var currentNotchWidth: CGFloat = 0
    private var currentNotchHeight: CGFloat = 0
    private var transitionID = 0
    private var phase: Phase = .hidden
    private var pendingRebuild = false
    private var updateVersion: String?
    private var usageState: CodexUsageState = .idle
    private var remoteHealth = RemoteHostHealthSnapshot.empty
    private weak var updateButton: ClosureButton?
    private weak var settingsButton: ClosureButton?
    private weak var hostStatusBadge: HostStatusBadgeView?
    private weak var weeklyUsageBadge: WeeklyUsageHeaderView?
    private weak var emptyStateView: EmptyStateView?
    private weak var shortcutHintLabel: NSTextField?
    private weak var activeSectionLabel: NSTextField?
    private weak var activeFreezeLabel: NSTextField?
    private weak var rootView: HUDContentView?
    private var rowsByEventID: [String: TaskRowView] = [:]
    private var activeTaskRows: [ActiveTaskRowView] = []
    private var dismissingEventIDs: Set<String> = []
    private var triggeringEventID: String?
    private var themeObserver: NSObjectProtocol?

    var onOpen: ((CompletedTask) -> Bool)?
    var onOpenActive: ((ActiveTask) -> Bool)?
    var onOpenFinished: ((CompletedTask) -> Void)?
    var onDismiss: ((Int) -> Void)?
    var onClear: (() -> Void)?
    var onSettings: (() -> Void)?
    var onConnections: (() -> Void)?
    var onRefreshUsage: (() -> Void)?
    var onToggleActiveTasks: (() -> Void)?
    var onUpdate: (() -> Void)?
    var onVisibilityChanged: ((Bool) -> Void)?
    var frameForTesting: NSRect { panel.frame }
    var bodyHeightForTesting: CGFloat { panel.frame.height }
    var bodyWidthForTesting: CGFloat { panel.frame.width - currentBodyInset * 2 }
    var notchWidthForTesting: CGFloat { currentNotchWidth }
    var notchHeightForTesting: CGFloat { currentNotchHeight }
    var eventVisibilityDurationForTesting: TimeInterval { Self.eventVisibilityDuration }
    var hoverOpenDurationForTesting: TimeInterval { NotchMotion.hoverOpenDuration }
    var isPinnedForTesting: Bool { isPinned }
    var isThemePreviewActiveForTesting: Bool { isThemePreviewActive }
    var hasHideTimerForTesting: Bool { hideTimer?.isValid == true }
    var isVisibleForTesting: Bool { panel.isVisible }
    var isLaunchingForTesting: Bool { phase == .launching }
    var panelAlphaForTesting: CGFloat { panel.alphaValue }
    var contentViewForTesting: NSView? { panel.contentView }
    var isUpdateAvailableForTesting: Bool { updateVersion != nil }
    var updateButtonForTesting: NSButton? { updateButton }
    var settingsButtonForTesting: NSButton? { settingsButton }
    var remoteStatusTextForTesting: String? {
        remoteHealth.hosts.isEmpty ? nil : remoteHealth.summaryText
    }
    var hostStatusCountForTesting: String? { hostStatusBadge?.countTextForTesting }
    var hostStatusToolTipForTesting: String? { hostStatusBadge?.toolTip }
    var hostStatusCountColorForTesting: NSColor? { hostStatusBadge?.countColorForTesting }
    var hostStatusButtonForTesting: NSButton? { hostStatusBadge }
    var hostStatusFrameForTesting: NSRect? { hostStatusBadge?.frame }
    var hasEmptyStateForTesting: Bool { emptyStateView != nil }
    var weeklyUsageTextForTesting: String? { weeklyUsageBadge?.valueTextForTesting }
    var weeklyUsageToolTipForTesting: String? { weeklyUsageBadge?.toolTip }
    var weeklyUsageValueFitsForTesting: Bool {
        weeklyUsageBadge?.valueFitsWithoutTruncationForTesting == true
    }
    var weeklyUsageButtonForTesting: NSButton? { weeklyUsageBadge }
    var weeklyUsageFrameForTesting: NSRect? { weeklyUsageBadge?.frame }
    var isShortcutOrderLockedForTesting: Bool { shortcutLettersVisible }
    var shortcutHintTextForTesting: String? { shortcutHintLabel?.stringValue }
    var activeFreezeTextForTesting: String? { activeFreezeLabel?.stringValue }
    var activeFreezeToolTipForTesting: String? { activeFreezeLabel?.toolTip }
    var isActiveFreezeIndicatorVisibleForTesting: Bool {
        activeFreezeLabel?.isHidden == false
    }
    var isActiveFreezeIndicatorBesideSectionForTesting: Bool {
        guard let section = activeSectionLabel,
              let frozen = activeFreezeLabel,
              section.superview === frozen.superview else { return false }
        section.superview?.layoutSubtreeIfNeeded()
        return frozen.frame.minX >= section.frame.maxX
            && abs(frozen.frame.midY - section.frame.midY) <= 1
    }
    var shortcutTaskTitlesForTesting: [String] {
        shortcutActiveTasks.map(\.title) + shortcutCompletedTasks.map(\.title)
    }
    var taskBadgeTextsForTesting: [String] {
        activeTaskRows.map(\.badgeTextForTesting)
            + presentedTasks.compactMap { rowsByEventID[$0.eventID]?.badgeTextForTesting }
    }
    var taskRelativeTimesForTesting: [String] {
        presentedTasks.compactMap { rowsByEventID[$0.eventID]?.relativeTimeTextForTesting }
    }
    var triggeredTaskEventIDsForTesting: [String] {
        presentedTasks.compactMap { task in
            rowsByEventID[task.eventID]?.isTriggeredForTesting == true ? task.eventID : nil
        }
    }
    var rowArrivalAnimationCountForTesting: Int {
        rowsByEventID.values.filter(\.hasArrivalAnimationForTesting).count
    }
    var hasContentAnimationForTesting: Bool {
        rootView?.hasContentAnimationForTesting == true
    }
    var headerTopInsetForTesting: CGFloat? { rootView?.headerTopInsetForTesting }
    var headerHasAmbiguousLayoutForTesting: Bool {
        rootView?.headerHasAmbiguousLayoutForTesting == true
    }
    var headerButtonTitlesForTesting: [String] {
        rootView?.headerButtonTitlesForTesting ?? []
    }
    static func menuBarNotchExclusionForTesting(
        notchWidth: CGFloat,
        centerOffset: CGFloat,
        hasHardwareNotch: Bool
    ) -> ClosedRange<CGFloat>? {
        menuBarNotchExclusion(
            notchWidth: notchWidth,
            centerOffset: centerOffset,
            hasHardwareNotch: hasHardwareNotch
        )
    }
    var hasContent: Bool {
        !tasks.isEmpty
            || (showsActiveTasks && !activeTasks.isEmpty)
            || updateVersion != nil
            || usageState.isVisible
    }
    private var presentedTasks: [CompletedTask] {
        guard showsActiveTasks, !activeTasks.isEmpty else { return tasks }
        let activeKeys = Set(activeTasks.map { "\($0.sourceID)\u{0}\($0.threadID.lowercased())" })
        return tasks.filter { !activeKeys.contains("\($0.sourceID)\u{0}\($0.threadID.lowercased())") }
    }
    private var displayedActiveTasks: [ActiveTask] {
        showsActiveTasks ? Array(activeTasks.prefix(4)) : []
    }
    private var shortcutActiveTasks: [ActiveTask] {
        lockedActiveTasks ?? displayedActiveTasks
    }
    private var shortcutCompletedTasks: [CompletedTask] {
        lockedCompletedTasks ?? presentedTasks
    }
    private var currentHostHealthOverview: HostHealthOverview {
        HostHealthOverview(local: localHostHealth(), remote: remoteHealth)
    }

    init(
        automaticOpenAllowed: @escaping () -> Bool = { true },
        localHostHealth: @escaping () -> LocalHostHealth = {
            CodexHookInstaller().localHostHealth
        },
        now: @escaping () -> Date = Date.init,
        shouldReduceMotion: @escaping () -> Bool = {
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        },
        shortcutModifierState: @escaping () -> Bool = {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            return flags.contains(.maskControl) && flags.contains(.maskShift)
        }
    ) {
        self.automaticOpenAllowed = automaticOpenAllowed
        self.localHostHealth = localHostHealth
        self.now = now
        self.shouldReduceMotion = shouldReduceMotion
        self.shortcutModifierState = shortcutModifierState
        panel = FocuslessPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.screenParametersDidChange() }
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.themeDidChange() }
    }

    deinit {
        shortcutModifierTimer?.invalidate()
        relativeTimeTimer?.invalidate()
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
    }

    func refreshShortcutModifierStateForTesting() {
        refreshShortcutModifierState()
    }

    private func themeDidChange() {
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func update(tasks: [CompletedTask]) {
        let previousEventIDs = Set(self.tasks.map(\.eventID))
        let previousRowFrames = rowsByEventID.mapValues(screenFrame)
        let insertedEventIDs = tasks
            .map(\.eventID)
            .filter { !previousEventIDs.contains($0) }
        self.tasks = tasks
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
            if !shouldReduceMotion() {
                for (eventID, oldFrame) in previousRowFrames {
                    guard let row = rowsByEventID[eventID] else { continue }
                    row.animateReposition(from: oldFrame, to: screenFrame(row))
                }
            }
            for (index, eventID) in insertedEventIDs.enumerated() {
                rowsByEventID[eventID]?.animateArrival(
                    reducedMotion: shouldReduceMotion(),
                    delay: min(Double(index) * 0.03, 0.09)
                )
            }
        }
    }

    func update(activeTasks: [ActiveTask], visible: Bool) {
        self.activeTasks = activeTasks
        showsActiveTasks = visible
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching: pendingRebuild = true
        case .hidden: rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func setUpdateAvailable(version: String?) {
        let wasAvailable = updateVersion != nil
        updateVersion = version
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }

        if version != nil, !wasAvailable { showForEvent() }
    }

    func setUsageOverview(_ overview: CodexUsageOverview?) {
        setUsageState(overview.map(CodexUsageState.available) ?? .idle)
    }

    func setUsageState(_ state: CodexUsageState) {
        guard usageState != state else { return }
        let visibilityChanged = usageState.isVisible != state.isVisible
        usageState = state
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        if !visibilityChanged, let weeklyUsageBadge {
            weeklyUsageBadge.update(state)
            return
        }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func setRemoteHostHealth(_ snapshot: RemoteHostHealthSnapshot) {
        remoteHealth = snapshot
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        if let hostStatusBadge {
            hostStatusBadge.update(currentHostHealthOverview)
            return
        }
        switch phase {
        case .opening, .closing, .launching:
            pendingRebuild = true
        case .hidden:
            rebuildContent(initiallyExpanded: false)
        case .open:
            rebuildContent(initiallyExpanded: true)
            positionPanel()
        }
    }

    func showForEvent(triggeringEventID: String? = nil) {
        guard automaticOpenAllowed(), hasContent else { return }
        if let triggeringEventID {
            setTriggeringEventID(triggeringEventID)
        }
        if !isPinned { eventAutoCloseCanBeCancelled = true }
        if shortcutLettersVisible, panel.isVisible {
            makeEventPresentationPersistent()
            return
        }
        if phase == .hidden { targetScreen = screenUnderPointer() }
        if phase == .open || phase == .opening {
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }
        present(autoHide: !isPinned, duration: NotchMotion.eventOpenDuration)
    }

    func showFromNotchHover(on screen: NSScreen) {
        guard !isThemePreviewActive, phase != .launching else { return }
        guard phase != .open, phase != .opening else { return }
        setTriggeringEventID(nil, animated: false)
        targetScreen = screen
        isPinned = false
        eventAutoCloseCanBeCancelled = false
        if phase == .hidden { rebuildContent(initiallyExpanded: false) }
        present(autoHide: true, duration: NotchMotion.hoverOpenDuration)
    }

    func setThemePreviewVisible(_ visible: Bool, on screen: NSScreen? = nil) {
        guard isThemePreviewActive != visible else { return }
        isThemePreviewActive = visible
        eventAutoCloseCanBeCancelled = false
        if visible {
            setTriggeringEventID(nil, animated: false)
            targetScreen = screen ?? screenUnderPointer()
            isPinned = true
            present(autoHide: false, duration: 0)
        } else {
            hide(immediately: true)
        }
    }

    func toggle() {
        guard !isThemePreviewActive else { return }
        switch phase {
        case .hidden:
            setTriggeringEventID(nil, animated: false)
            targetScreen = screenUnderPointer()
            isPinned = true
            eventAutoCloseCanBeCancelled = false
            present(autoHide: false, duration: 0)
        case .closing:
            setTriggeringEventID(nil, animated: false)
            isPinned = true
            eventAutoCloseCanBeCancelled = false
            present(autoHide: false, duration: 0)
        case .launching:
            break
        case .opening, .open:
            hide(immediately: true)
        }
    }

    func openSettings() {
        guard panel.isVisible else { return }
        if isThemePreviewActive {
            onSettings?()
            return
        }
        hide(immediately: true)
        onSettings?()
    }

    func openConnections() {
        guard panel.isVisible else { return }
        if isThemePreviewActive {
            onConnections?()
            return
        }
        hide(immediately: true)
        onConnections?()
    }

    func openTask(at index: Int, animated: Bool = true) {
        let active = shortcutActiveTasks
        if active.indices.contains(index) {
            openActiveTask(active[index])
            return
        }
        let completedIndex = index - active.count
        let completed = shortcutCompletedTasks
        guard completed.indices.contains(completedIndex) else { return }
        openTask(completed[completedIndex], animated: animated)
    }

    func dismissTask(at index: Int, animated: Bool = true) {
        let completedIndex = index - shortcutActiveTasks.count
        let visibleTasks = shortcutCompletedTasks
        guard visibleTasks.indices.contains(completedIndex) else { return }
        let eventID = visibleTasks[completedIndex].eventID
        guard animated,
              !shouldReduceMotion(),
              phase == .open,
              let row = rowsByEventID[eventID]
        else {
            guard let storedIndex = tasks.firstIndex(where: { $0.eventID == eventID }) else { return }
            onDismiss?(storedIndex)
            return
        }
        dismissingEventIDs.insert(eventID)
        row.animateDismiss { [weak self] in
            guard let self else { return }
            self.dismissingEventIDs.remove(eventID)
            guard let currentIndex = self.tasks.firstIndex(where: { $0.eventID == eventID })
            else { return }
            self.onDismiss?(currentIndex)
        }
    }

    func clearTasks(animated: Bool = true) {
        let rows = tasks.compactMap { rowsByEventID[$0.eventID] }
        guard animated, !shouldReduceMotion(), phase == .open, !rows.isEmpty else {
            onClear?()
            return
        }
        dismissingEventIDs.formUnion(tasks.map(\.eventID))
        for (index, row) in rows.enumerated() {
            let delay = min(Double(index) * 0.012, 0.10)
            let completion: (() -> Void)? = index == rows.count - 1
                ? { [weak self] in
                    self?.dismissingEventIDs.removeAll()
                    self?.onClear?()
                }
                : nil
            row.animateDismiss(delay: delay, completion: completion)
        }
    }

    func hide(immediately: Bool = false) {
        hideTimer?.invalidate()
        isPinned = false
        eventAutoCloseCanBeCancelled = false
        transitionID &+= 1
        let hidingTransitionID = transitionID
        guard phase != .hidden || panel.isVisible else { return }

        if immediately {
            rootView?.setInitialState(expanded: false)
            orderPanelOut()
            phase = .hidden
            finishPendingRebuild(expanded: false)
            return
        }
        guard phase != .launching else { return }

        phase = .closing
        if shouldReduceMotion() {
            rootView?.animateReducedMotionContent(
                visible: false,
                duration: NotchMotion.reducedMotionFadeDuration
            )
            DispatchQueue.main.asyncAfter(
                deadline: .now() + NotchMotion.reducedMotionFadeDuration
            ) { [weak self] in
                guard let self, self.transitionID == hidingTransitionID else { return }
                self.orderPanelOut()
                self.phase = .hidden
                self.rootView?.setInitialState(expanded: false)
                self.finishPendingRebuild(expanded: false)
            }
            return
        }

        rootView?.animateContentOut(duration: 0.10)
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.closeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.closeDuration) { [weak self] in
            guard let self, self.transitionID == hidingTransitionID else { return }
            self.orderPanelOut()
            self.phase = .hidden
            self.finishPendingRebuild(expanded: false)
        }
    }

    private func present(autoHide: Bool, duration: TimeInterval) {
        if phase == .open || phase == .opening {
            if autoHide, !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }

        transitionID &+= 1
        let presentingTransitionID = transitionID
        let wasHidden = phase == .hidden || !panel.isVisible
        if rootView == nil { rebuildContent(initiallyExpanded: false) }
        positionPanel()
        hideTimer?.invalidate()
        panel.alphaValue = 1
        let reduceMotion = shouldReduceMotion()
        let shouldAnimateSpatially = duration > 0 && !reduceMotion
        let shouldFade = duration > 0 && reduceMotion
        if wasHidden && shouldFade { rootView?.prepareReducedMotionOpen() }
        if wasHidden { orderPanelFront() }

        phase = .opening
        if shouldAnimateSpatially {
            rootView?.animateExpansion(expanded: true, duration: duration)
            rootView?.animateContentIn(duration: min(0.16, duration))
        } else if shouldFade {
            rootView?.animateReducedMotionContent(
                visible: true,
                duration: NotchMotion.reducedMotionFadeDuration
            )
        } else {
            rootView?.setInitialState(expanded: true)
            phase = .open
            finishPendingRebuild(expanded: true)
        }

        if shouldAnimateSpatially || shouldFade {
            let completionDuration = shouldAnimateSpatially
                ? duration
                : NotchMotion.reducedMotionFadeDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + completionDuration) { [weak self] in
                guard let self, self.transitionID == presentingTransitionID else { return }
                self.phase = .open
                self.finishPendingRebuild(expanded: true)
            }
        }
        if autoHide, !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
    }

    private func openTask(_ task: CompletedTask, animated: Bool = true) {
        guard phase != .launching, onOpen?(task) == true else { return }
        guard animated, phase != .hidden, !shouldReduceMotion() else {
            transitionID &+= 1
            hideTimer?.invalidate()
            isPinned = false
            if panel.isVisible { orderPanelOut() }
            phase = .hidden
            pendingRebuild = false
            onOpenFinished?(task)
            return
        }

        transitionID &+= 1
        let launchTransitionID = transitionID
        hideTimer?.invalidate()
        isPinned = false
        phase = .launching

        rootView?.animateLaunch(selectedRow: rowsByEventID[task.eventID])
        rootView?.animateExpansion(expanded: false, duration: NotchMotion.launchDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchMotion.launchDuration) { [weak self] in
            guard let self, self.transitionID == launchTransitionID else { return }
            self.orderPanelOut()
            self.phase = .hidden
            self.pendingRebuild = false
            self.onOpenFinished?(task)
        }
    }

    private func openActiveTask(_ task: ActiveTask) {
        guard onOpenActive?(task) == true else { return }
        hide(immediately: shouldReduceMotion())
    }

    private func rebuildContent(initiallyExpanded: Bool) {
        let theme = ThemeStore.shared.activeTheme
        let screen = targetScreen ?? screenUnderPointer()
        let geometry = islandGeometry(for: screen)
        currentBodyInset = geometry.bodyInset
        currentNotchWidth = geometry.notchWidth
        currentNotchHeight = geometry.notchHeight
        let completedTasks = presentedTasks
        let built = OverlayContentBuilder.build(
            configuration: OverlayContentConfiguration(
                geometry: geometry,
                theme: theme,
                completedTasks: completedTasks,
                displayedActiveTasks: displayedActiveTasks,
                totalActiveTaskCount: activeTasks.count,
                showsActiveTasks: showsActiveTasks,
                shortcutLettersVisible: shortcutLettersVisible,
                updateVersion: updateVersion,
                usageState: usageState,
                hostHealth: currentHostHealthOverview,
                triggeringEventID: triggeringEventID,
                dismissingEventIDs: dismissingEventIDs,
                now: now(),
                notchExclusion: Self.menuBarNotchExclusion(
                    notchWidth: geometry.notchWidth,
                    centerOffset: geometry.notchCenterOffset,
                    hasHardwareNotch: geometry.hasHardwareNotch
                ),
                shouldReduceMotion: shouldReduceMotion
            ),
            actions: OverlayContentActions(
                refreshUsage: { [weak self] in self?.onRefreshUsage?() },
                openConnections: { [weak self] in self?.openConnections() },
                toggleActiveTasks: { [weak self] in self?.onToggleActiveTasks?() },
                clearTasks: { [weak self] in self?.clearTasks() },
                openSettings: { [weak self] in self?.openSettings() },
                installUpdate: { [weak self] in self?.onUpdate?() },
                openActiveTask: { [weak self] task in self?.openActiveTask(task) },
                openCompletedTask: { [weak self] task in self?.openTask(task) },
                dismissTask: { [weak self] index in self?.dismissTask(at: index) },
                hoverChanged: { [weak self] hovering in
                    if hovering {
                        self?.hideTimer?.invalidate()
                    } else if self?.isPinned == false {
                        self?.scheduleHide(after: Self.eventVisibilityDuration)
                    }
                }
            )
        )

        panel.contentView = built.root
        panel.contentMinSize = built.size
        panel.contentMaxSize = built.size
        panel.setContentSize(built.size)
        built.root.layoutSubtreeIfNeeded()
        built.root.setInitialState(expanded: initiallyExpanded)
        rootView = built.root
        rowsByEventID = built.rowsByEventID
        activeTaskRows = built.activeTaskRows
        activeSectionLabel = built.activeSectionLabel
        activeFreezeLabel = built.activeFreezeLabel
        emptyStateView = built.emptyStateView
        updateButton = built.updateButton
        settingsButton = built.settingsButton
        hostStatusBadge = built.hostStatusBadge
        weeklyUsageBadge = built.weeklyUsageBadge
        shortcutHintLabel = built.shortcutHintLabel
        pendingRebuild = false
    }

    private func finishPendingRebuild(expanded: Bool) {
        guard pendingRebuild, !shortcutLettersVisible else { return }
        rebuildContent(initiallyExpanded: expanded)
        if expanded { positionPanel() }
    }

    private func positionPanel() {
        panel.setFrameOrigin(visibleOrigin())
    }

    private func orderPanelFront() {
        let wasVisible = panel.isVisible
        panel.orderFrontRegardless()
        if !wasVisible {
            startShortcutModifierMonitoring()
            startRelativeTimeMonitoring()
            onVisibilityChanged?(true)
        }
    }

    private func orderPanelOut() {
        let wasVisible = panel.isVisible
        panel.orderOut(nil)
        if wasVisible {
            stopShortcutModifierMonitoring()
            stopRelativeTimeMonitoring()
            setTriggeringEventID(nil, animated: false)
            onVisibilityChanged?(false)
        }
    }

    private func startRelativeTimeMonitoring() {
        refreshRelativeTimes()
        guard relativeTimeTimer == nil else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, !self.shortcutLettersVisible else { return }
            self.refreshRelativeTimes()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        relativeTimeTimer = timer
    }

    private func stopRelativeTimeMonitoring() {
        relativeTimeTimer?.invalidate()
        relativeTimeTimer = nil
    }

    private func refreshRelativeTimes() {
        let timestamp = now()
        rowsByEventID.values.forEach { $0.updateRelativeTime(now: timestamp) }
    }

    func refreshRelativeTimesForTesting() {
        refreshRelativeTimes()
    }

    private func setTriggeringEventID(_ eventID: String?, animated: Bool = true) {
        guard triggeringEventID != eventID else { return }
        let previousEventID = triggeringEventID
        triggeringEventID = eventID
        if shortcutLettersVisible, panel.isVisible {
            pendingRebuild = true
            return
        }
        if let previousEventID {
            rowsByEventID[previousEventID]?.setTriggered(false, animated: animated)
        }
        if let eventID {
            rowsByEventID[eventID]?.setTriggered(true, animated: animated)
        }
    }

    private func startShortcutModifierMonitoring() {
        refreshShortcutModifierState()
        guard shortcutModifierTimer == nil else { return }
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.refreshShortcutModifierState()
        }
        RunLoop.main.add(timer, forMode: .common)
        shortcutModifierTimer = timer
    }

    private func stopShortcutModifierMonitoring() {
        shortcutModifierTimer?.invalidate()
        shortcutModifierTimer = nil
        setShortcutLettersVisible(false)
    }

    private func refreshShortcutModifierState() {
        setShortcutLettersVisible(shortcutModifierState())
    }

    private func setShortcutLettersVisible(_ visible: Bool) {
        guard shortcutLettersVisible != visible else { return }
        if visible {
            lockedActiveTasks = displayedActiveTasks
            lockedCompletedTasks = presentedTasks
            hideTimer?.invalidate()
            makeEventPresentationPersistent()
        }
        shortcutLettersVisible = visible
        activeTaskRows.forEach { $0.setShortcutLetterVisible(visible) }
        rowsByEventID.values.forEach { $0.setShortcutLetterVisible(visible) }
        activeFreezeLabel?.isHidden = !visible
        guard !visible else { return }
        lockedActiveTasks = nil
        lockedCompletedTasks = nil
        if (phase == .open || phase == .opening), panel.isVisible {
            finishPendingRebuild(expanded: true)
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
        }
    }

    private func makeEventPresentationPersistent() {
        guard eventAutoCloseCanBeCancelled, panel.isVisible else { return }
        eventAutoCloseCanBeCancelled = false
        isPinned = true
        hideTimer?.invalidate()
    }

    private func screenFrame(_ row: TaskRowView) -> NSRect {
        panel.convertToScreen(row.convert(row.bounds, to: nil))
    }

    private func visibleOrigin() -> NSPoint {
        let screen = targetScreen ?? screenUnderPointer()
        let frame = screen.frame
        return NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.maxY - panel.frame.height
        )
    }

    private func islandGeometry(for screen: NSScreen) -> IslandGeometry {
        let notch = ScreenNotchGeometry(screen: screen)
        let bodyInset: CGFloat = 34
        let bodyWidth = min(820, max(460, screen.frame.width - 160))
        return IslandGeometry(
            windowWidth: bodyWidth + bodyInset * 2,
            bodyInset: bodyInset,
            notchWidth: notch.width,
            notchHeight: notch.height,
            notchCenterOffset: notch.centerOffset,
            hasHardwareNotch: notch.hasHardwareNotch
        )
    }

    private static func menuBarNotchExclusion(
        notchWidth: CGFloat,
        centerOffset: CGFloat,
        hasHardwareNotch: Bool
    ) -> ClosedRange<CGFloat>? {
        guard hasHardwareNotch else { return nil }
        let halfWidth = notchWidth / 2 + hardwareNotchPadding
        return (centerOffset - halfWidth)...(centerOffset + halfWidth)
    }

    private func screenUnderPointer() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private func screenParametersDidChange() {
        if deferVisibleRebuildWhileShortcutsLocked() { return }
        let expanded = phase != .hidden && phase != .closing
        rebuildContent(initiallyExpanded: expanded)
        positionPanel()
    }

    private func scheduleHide(after interval: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    @discardableResult
    private func deferVisibleRebuildWhileShortcutsLocked() -> Bool {
        guard shortcutLettersVisible, panel.isVisible else { return false }
        pendingRebuild = true
        return true
    }
}
