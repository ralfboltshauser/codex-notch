import AppKit
import Foundation

struct ScreenNotchGeometry: Equatable {
    let width: CGFloat
    let height: CGFloat
    let centerOffset: CGFloat
    let hasHardwareNotch: Bool

    init(screen: NSScreen) {
        self.init(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeTop: screen.safeAreaInsets.top,
            leftArea: screen.auxiliaryTopLeftArea,
            rightArea: screen.auxiliaryTopRightArea
        )
    }

    init(
        screenFrame: NSRect,
        visibleFrame: NSRect,
        safeTop: CGFloat,
        leftArea: NSRect?,
        rightArea: NSRect?
    ) {
        let menuHeight = screenFrame.maxY - visibleFrame.maxY
        height = max(CGFloat(28), max(safeTop, menuHeight))

        var measuredWidth: CGFloat = 128
        var measuredCenterOffset: CGFloat = 0
        var measuredHardwareNotch = false
        if let leftArea, let rightArea {
            let measuredGap = rightArea.minX - leftArea.maxX
            measuredHardwareNotch = leftArea.width > 0
                && rightArea.width > 0
                && measuredGap >= 80
                && measuredGap <= screenFrame.width * 0.35
            if measuredHardwareNotch {
                measuredWidth = measuredGap
                measuredCenterOffset = (leftArea.maxX + rightArea.minX) / 2
                    - screenFrame.midX
            }
        }
        width = measuredWidth
        centerOffset = measuredCenterOffset
        hasHardwareNotch = measuredHardwareNotch
    }
}

struct NotchHoverTarget {
    static let horizontalPadding: CGFloat = 10

    static func rect(screenFrame: NSRect, notch: ScreenNotchGeometry) -> NSRect {
        let width = notch.width + horizontalPadding * 2
        return NSRect(
            x: screenFrame.midX + notch.centerOffset - width / 2,
            y: screenFrame.maxY - notch.height,
            width: width,
            height: notch.height
        )
    }
}

struct NotchHoverIntent {
    let dwellDuration: TimeInterval
    private(set) var enteredAt: TimeInterval?
    private(set) var isArmed = true

    mutating func update(isInside: Bool, at time: TimeInterval) -> Bool {
        guard isInside else {
            enteredAt = nil
            isArmed = true
            return false
        }
        guard isArmed else { return false }
        guard let enteredAt else {
            self.enteredAt = time
            return false
        }
        guard time - enteredAt >= dwellDuration else { return false }
        self.enteredAt = nil
        isArmed = false
        return true
    }

    func remainingDwell(at time: TimeInterval) -> TimeInterval {
        guard let enteredAt else { return dwellDuration }
        return max(0, dwellDuration - (time - enteredAt))
    }
}

final class NotchHoverMonitor {
    static let dwellDuration: TimeInterval = 0.14

    var onActivate: ((NSScreen) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pendingActivation: DispatchWorkItem?
    private var candidateScreenID: ObjectIdentifier?
    private var intent = NotchHoverIntent(dwellDuration: dwellDuration)

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) {
            [weak self] _ in
            DispatchQueue.main.async { self?.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) {
            [weak self] event in
            self?.pointerMoved()
            return event
        }
    }

    func stop() {
        pendingActivation?.cancel()
        pendingActivation = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        candidateScreenID = nil
        _ = intent.update(isInside: false, at: ProcessInfo.processInfo.systemUptime)
    }

    deinit { stop() }

    private func pointerMoved() {
        let now = ProcessInfo.processInfo.systemUptime
        guard let screen = hoveredScreen(at: NSEvent.mouseLocation) else {
            pendingActivation?.cancel()
            pendingActivation = nil
            candidateScreenID = nil
            _ = intent.update(isInside: false, at: now)
            return
        }

        let screenID = ObjectIdentifier(screen)
        if candidateScreenID != screenID {
            pendingActivation?.cancel()
            pendingActivation = nil
            _ = intent.update(isInside: false, at: now)
            candidateScreenID = screenID
        }
        guard !intent.update(isInside: true, at: now) else {
            activate(screen)
            return
        }
        scheduleActivation(after: intent.remainingDwell(at: now))
    }

    private func scheduleActivation(after delay: TimeInterval) {
        guard pendingActivation == nil, intent.isArmed else { return }
        let work = DispatchWorkItem { [weak self] in self?.activationDwellElapsed() }
        pendingActivation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, delay), execute: work)
    }

    private func activationDwellElapsed() {
        pendingActivation = nil
        let now = ProcessInfo.processInfo.systemUptime
        guard let screen = hoveredScreen(at: NSEvent.mouseLocation) else {
            candidateScreenID = nil
            _ = intent.update(isInside: false, at: now)
            return
        }
        let screenID = ObjectIdentifier(screen)
        guard screenID == candidateScreenID else {
            _ = intent.update(isInside: false, at: now)
            candidateScreenID = screenID
            _ = intent.update(isInside: true, at: now)
            scheduleActivation(after: intent.remainingDwell(at: now))
            return
        }
        if intent.update(isInside: true, at: now) {
            activate(screen)
        } else {
            scheduleActivation(after: intent.remainingDwell(at: now))
        }
    }

    private func activate(_ screen: NSScreen) {
        pendingActivation?.cancel()
        pendingActivation = nil
        onActivate?(screen)
    }

    private func hoveredScreen(at point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { screen in
            NotchHoverTarget.rect(
                screenFrame: screen.frame,
                notch: ScreenNotchGeometry(screen: screen)
            ).contains(point)
        }
    }
}
