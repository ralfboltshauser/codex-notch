import AppKit
import QuartzCore

struct IslandGeometry {
    let windowWidth: CGFloat
    let bodyInset: CGFloat
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let notchCenterOffset: CGFloat
    let hasHardwareNotch: Bool
}

enum NotchMotion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
    static let ease = CAMediaTimingFunction(controlPoints: 0.25, 0.10, 0.25, 1)
    static let eventOpenDuration: TimeInterval = 0.24
    static let hoverOpenDuration: TimeInterval = 0.32
    static let closeDuration: TimeInterval = 0.17
    static let launchDuration: TimeInterval = 0.18
    static let pressInDuration: TimeInterval = 0.10
    static let pressOutDuration: TimeInterval = 0.14
    static let rowArrivalDuration: TimeInterval = 0.18
    static let rowDismissDuration: TimeInterval = 0.14
    static let reducedMotionFadeDuration: TimeInterval = 0.12
}

enum CompletionRelativeTime {
    static func text(since completedAt: Date, now: Date = Date()) -> String {
        let age = max(0, now.timeIntervalSince(completedAt))
        if age < 60 { return "Just now" }
        if age < 60 * 60 { return "\(Int(age / 60)) min ago" }
        if age < 24 * 60 * 60 { return "\(Int(age / (60 * 60))) hr ago" }
        return "\(Int(age / (24 * 60 * 60))) d ago"
    }
}

final class FocuslessPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

class ClosureButton: NSButton {
    var handler: (() -> Void)?
    private var pointerIsDown = false

    init(handler: (() -> Void)? = nil) {
        self.handler = handler
        super.init(frame: .zero)
        target = self
        action = #selector(pressed)
        isBordered = false
        title = ""
        refusesFirstResponder = true
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func pressed() { handler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        setPointerDown(true)
        super.mouseDown(with: event)
        setPointerDown(false)
    }

    private func setPointerDown(_ isDown: Bool) {
        guard pointerIsDown != isDown, let layer else { return }
        pointerIsDown = isDown
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let target = isDown && !reduceMotion
            ? CATransform3DMakeScale(0.97, 0.97, 1)
            : CATransform3DIdentity
        let current = layer.presentation()?.transform ?? layer.transform
        let duration = isDown
            ? NotchMotion.pressInDuration
            : NotchMotion.pressOutDuration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()

        layer.removeAnimation(forKey: "buttonPress")
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = current
        animation.toValue = target
        animation.duration = duration
        animation.timingFunction = NotchMotion.easeOut
        layer.add(animation, forKey: "buttonPress")
    }
}
