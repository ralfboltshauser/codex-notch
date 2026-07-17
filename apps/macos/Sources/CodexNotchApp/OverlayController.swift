import AppKit
import CoreGraphics
import QuartzCore

final class OverlayController {
    static let eventVisibilityDuration: TimeInterval = 5

    private enum Phase {
        case hidden
        case opening
        case open
        case closing
        case launching
    }

    let panel: FocuslessPanel
    private let shouldReduceMotion: () -> Bool
    private let shortcutModifierState: () -> Bool
    private let automaticOpenAllowed: () -> Bool
    private let localHostHealth: () -> LocalHostHealth
    private let now: () -> Date
    private let isWindowOnActiveSpace: (NSWindow) -> Bool
    private var tasks: [CompletedTask] = []
    private var activeTasks: [ActiveTask] = []
    private var showsActiveTasks = ActiveTaskPreferences.shared.isVisible
    var hideTimer: Timer?
    private var shortcutModifierTimer: Timer?
    private var relativeTimeTimer: Timer?
    var shortcutLettersVisible = false
    private var lockedActiveTasks: [ActiveTask]?
    private var lockedCompletedTasks: [CompletedTask]?
    private var eventAutoCloseCanBeCancelled = false
    private var targetScreen: NSScreen?
    var isPinned = false
    private var isPointerInsideContent = false
    var isThemePreviewActive = false
    var presentationScope = OverlayPresentationScope.full
    var currentBodyInset: CGFloat = 0
    var currentNotchWidth: CGFloat = 0
    var currentNotchHeight: CGFloat = 0
    private var transitionID = 0
    private var phase: Phase = .hidden
    private var pendingRebuild = false
    var updateVersion: String?
    private var usageState: CodexUsageState = .idle
    var remoteHealth = RemoteHostHealthSnapshot.empty
    weak var updateButton: ClosureButton?
    weak var settingsButton: ClosureButton?
    weak var hostStatusBadge: HostStatusBadgeView?
    weak var weeklyUsageBadge: WeeklyUsageHeaderView?
    weak var emptyStateView: EmptyStateView?
    weak var shortcutHintLabel: NSTextField?
    weak var activeSectionLabel: NSTextField?
    weak var activeFreezeLabel: NSTextField?
    weak var rootView: HUDContentView?
    var rowsByEventID: [String: TaskRowView] = [:]
    var activeTaskRows: [ActiveTaskRowView] = []
    private var dismissingEventIDs: Set<String> = []
    var triggeringEventID: String?
    private var themeObserver: NSObjectProtocol?
    private var completionOutcomeObserver: NSObjectProtocol?

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
    var isLaunchingForTesting: Bool { phase == .launching }
    var isAttentionSurfaceVisible: Bool {
        panel.isVisible && isWindowOnActiveSpace(panel) && (phase == .opening || phase == .open)
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
    var presentationCompletedTasks: [CompletedTask] {
        presentationScope.completedTasks(from: presentedTasks)
    }
    var presentationActiveTasks: [ActiveTask] {
        presentationScope == .full ? displayedActiveTasks : []
    }
    var shortcutActiveTasks: [ActiveTask] {
        lockedActiveTasks ?? presentationActiveTasks
    }
    var shortcutCompletedTasks: [CompletedTask] {
        lockedCompletedTasks ?? presentationCompletedTasks
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
        },
        isWindowOnActiveSpace: @escaping (NSWindow) -> Bool = { $0.isOnActiveSpace }
    ) {
        self.automaticOpenAllowed = automaticOpenAllowed
        self.localHostHealth = localHostHealth
        self.now = now
        self.shouldReduceMotion = shouldReduceMotion
        self.shortcutModifierState = shortcutModifierState
        self.isWindowOnActiveSpace = isWindowOnActiveSpace
        panel = FocuslessPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        OverlaySpaceBehavior.configure(panel)
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.screenParametersDidChange() }
        themeObserver = NotificationCenter.default.addObserver(
            forName: ThemeStore.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.presentationPreferenceDidChange() }
        completionOutcomeObserver = NotificationCenter.default.addObserver(
            forName: CompletionOutcomePreferences.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.presentationPreferenceDidChange() }
    }

    deinit {
        shortcutModifierTimer?.invalidate()
        relativeTimeTimer?.invalidate()
        if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        if let completionOutcomeObserver { NotificationCenter.default.removeObserver(completionOutcomeObserver) }
    }

    func refreshShortcutModifierStateForTesting() {
        refreshShortcutModifierState()
    }

    func contentHoverChangedForTesting(_ hovering: Bool) {
        contentHoverChanged(hovering)
    }

    private func presentationPreferenceDidChange() {
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
        if panel.isVisible, !isWindowOnActiveSpace(panel) { revealPanelOnActiveSpace() }
        let resolvedTrigger = triggeringEventID.flatMap { eventID in
            presentedTasks.contains(where: { $0.eventID == eventID }) ? eventID : nil
        }
        if phase == .hidden {
            targetScreen = screenUnderPointer()
            if let resolvedTrigger {
                presentationScope = .triggeredTask(eventID: resolvedTrigger)
            } else {
                presentationScope = .full
            }
            setTriggeringEventID(resolvedTrigger, animated: false)
            rebuildContent(initiallyExpanded: false)
        } else if let resolvedTrigger {
            if presentationScope.triggeringEventID != nil, !isPinned {
                presentationScope = .triggeredTask(eventID: resolvedTrigger)
                setTriggeringEventID(resolvedTrigger, animated: false)
                if shortcutLettersVisible {
                    pendingRebuild = true
                } else {
                    rebuildContent(initiallyExpanded: true)
                    positionPanel()
                }
            } else {
                setTriggeringEventID(resolvedTrigger)
            }
        }
        if !isPinned { eventAutoCloseCanBeCancelled = true }
        if shortcutLettersVisible, panel.isVisible {
            makeEventPresentationPersistent()
            return
        }
        if phase == .open || phase == .opening {
            if !isPinned { scheduleHide(after: Self.eventVisibilityDuration) }
            return
        }
        present(autoHide: !isPinned, duration: NotchMotion.eventOpenDuration)
    }

    func showFromNotchHover(on screen: NSScreen) {
        guard !isThemePreviewActive, phase != .launching else { return }
        guard phase != .open, phase != .opening else { return }
        presentationScope = .full
        setTriggeringEventID(nil, animated: false)
        targetScreen = screen
        isPinned = false
        eventAutoCloseCanBeCancelled = false
        rebuildContent(initiallyExpanded: false)
        present(autoHide: true, duration: NotchMotion.hoverOpenDuration)
    }

    func setThemePreviewVisible(_ visible: Bool, on screen: NSScreen? = nil) {
        guard isThemePreviewActive != visible else { return }
        isThemePreviewActive = visible
        eventAutoCloseCanBeCancelled = false
        if visible {
            presentationScope = .full
            setTriggeringEventID(nil, animated: false)
            targetScreen = screen ?? screenUnderPointer()
            isPinned = true
            rebuildContent(initiallyExpanded: false)
            present(autoHide: false, duration: 0)
        } else {
            hide(immediately: true)
        }
    }

    func toggle() {
        guard !isThemePreviewActive else { return }
        switch phase {
        case .hidden:
            presentationScope = .full
            setTriggeringEventID(nil, animated: false)
            targetScreen = screenUnderPointer()
            isPinned = true
            eventAutoCloseCanBeCancelled = false
            rebuildContent(initiallyExpanded: false)
            present(autoHide: false, duration: 0)
        case .closing:
            if presentationScope.triggeringEventID != nil {
                promoteTriggeredPresentationToFull(pin: true)
            } else {
                presentationScope = .full
                setTriggeringEventID(nil, animated: false)
                isPinned = true
                eventAutoCloseCanBeCancelled = false
                rebuildContent(initiallyExpanded: false)
                present(autoHide: false, duration: 0)
            }
        case .launching:
            break
        case .opening, .open:
            if presentationScope.triggeringEventID != nil {
                promoteTriggeredPresentationToFull(pin: true)
            } else if panel.isVisible, !isWindowOnActiveSpace(panel) {
                revealPanelOnActiveSpace()
            } else {
                hide(immediately: true)
            }
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

    private func contentHoverChanged(_ hovering: Bool) {
        isPointerInsideContent = hovering
        if hovering {
            hideTimer?.invalidate()
            if presentationScope.triggeringEventID != nil {
                promoteTriggeredPresentationToFull(pin: isPinned)
            }
        } else if !isPinned {
            scheduleHide(after: Self.eventVisibilityDuration)
        }
    }

    private func promoteTriggeredPresentationToFull(pin: Bool) {
        guard let eventID = presentationScope.triggeringEventID,
              phase == .open || phase == .opening || phase == .closing else { return }
        let compactHeight = panel.frame.height
        let compactShapePath = rootView?.currentShapePathForPromotion
        let oldRowFrame = rowsByEventID[eventID].map(screenFrame)

        transitionID &+= 1
        let promotionTransitionID = transitionID
        hideTimer?.invalidate()
        presentationScope = .full
        if pin {
            isPinned = true
            eventAutoCloseCanBeCancelled = false
        }
        if shortcutLettersVisible {
            lockedActiveTasks = displayedActiveTasks
            lockedCompletedTasks = presentedTasks
        }

        phase = .opening
        rebuildContent(initiallyExpanded: true)
        positionPanel()
        let reduceMotion = shouldReduceMotion()
        if isPointerInsideContent {
            rootView?.setControlsVisible(true, animated: !reduceMotion)
        }
        if reduceMotion {
            rootView?.prepareReducedMotionPromotion()
            rootView?.animateReducedMotionContent(
                visible: true,
                duration: NotchMotion.reducedMotionFadeDuration
            )
        } else {
            rootView?.animatePromotion(
                fromExpandedHeight: compactHeight,
                sourcePath: compactShapePath
            )
            if let oldRowFrame, let row = rowsByEventID[eventID] {
                row.animatePromotion(from: oldRowFrame, to: screenFrame(row))
            }
        }

        let duration = reduceMotion
            ? NotchMotion.reducedMotionFadeDuration
            : NotchMotion.promotionDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.transitionID == promotionTransitionID else { return }
            self.phase = .open
            self.finishPendingRebuild(expanded: true)
            if !self.isPinned, !self.isPointerInsideContent {
                self.scheduleHide(after: Self.eventVisibilityDuration)
            }
        }
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
        let geometry = OverlayGeometry.island(for: screen)
        currentBodyInset = geometry.bodyInset
        currentNotchWidth = geometry.notchWidth
        currentNotchHeight = geometry.notchHeight
        let completedTasks = presentationCompletedTasks
        let activeTasks = presentationActiveTasks
        let built = OverlayContentBuilder.build(
            configuration: OverlayContentConfiguration(
                geometry: geometry,
                theme: theme,
                completedTasks: completedTasks,
                showsCompletionOutcomes: CompletionOutcomePreferences.shared.isEnabled,
                attentionMode: AttentionPreferences.shared.mode,
                displayedActiveTasks: activeTasks,
                totalActiveTaskCount: presentationScope == .full
                    ? self.activeTasks.count
                    : 0,
                showsActiveTasks: showsActiveTasks,
                shortcutLettersVisible: shortcutLettersVisible,
                updateVersion: updateVersion,
                usageState: usageState,
                hostHealth: currentHostHealthOverview,
                triggeringEventID: triggeringEventID,
                dismissingEventIDs: dismissingEventIDs,
                now: now(),
                notchExclusion: OverlayGeometry.menuBarNotchExclusion(
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
                    self?.contentHoverChanged(hovering)
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
    private func revealPanelOnActiveSpace() {
        // AppKit can retain an ordered panel on its previous Space even though
        // it remains `isVisible`. Reassert the overlay behavior before ordering
        // it so the global shortcut never acts as a hidden close operation.
        OverlaySpaceBehavior.configure(panel)
        targetScreen = screenUnderPointer()
        positionPanel()
        panel.orderFrontRegardless()
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
            isPointerInsideContent = false
            presentationScope = .full
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
            lockedActiveTasks = presentationActiveTasks
            lockedCompletedTasks = presentationCompletedTasks
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
