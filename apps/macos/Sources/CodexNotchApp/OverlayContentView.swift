import AppKit
import CoreGraphics
import QuartzCore

final class HUDContentView: NSView {
    private static let pitchBlack = CGColor(gray: 0, alpha: 1)
    private let backgroundGradient = CAGradientLayer()

    var onHoverChanged: ((Bool) -> Void)?
    var controls: [NSView] = []
    var bodyInset: CGFloat = 34 { didSet { needsLayout = true } }
    var notchWidth: CGFloat = 128 { didSet { needsLayout = true } }
    var notchHeight: CGFloat = 28 { didSet { needsLayout = true } }
    var notchCenterOffset: CGFloat = 0 { didSet { needsLayout = true } }

    private var tracking: NSTrackingArea?
    private let shapeMask = CAShapeLayer()
    private var targetExpansion: CGFloat = 0
    private weak var contentHost: NSView?
    private weak var headerView: NSView?
    private var taskRows: [TaskRowView] = []
    private var promotionRevealViews: [NSView] = []

    init(theme: NotchTheme) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Self.pitchBlack
        layer?.opacity = 1
        backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0)
        backgroundGradient.endPoint = CGPoint(x: 0.5, y: 1)
        backgroundGradient.colors = [
            theme.hudBottom.cgColor,
            theme.hudTop.cgColor,
            Self.pitchBlack,
        ]
        layer?.addSublayer(backgroundGradient)
        shapeMask.fillColor = Self.pitchBlack
        layer?.mask = shapeMask
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configureMotion(
        contentHost: NSView,
        header: NSView,
        rows: [TaskRowView],
        promotionRevealViews: [NSView]
    ) {
        self.contentHost = contentHost
        headerView = header
        taskRows = rows
        self.promotionRevealViews = promotionRevealViews
        contentHost.wantsLayer = true
        header.wantsLayer = true
        rows.forEach { $0.wantsLayer = true }
        promotionRevealViews.forEach { $0.wantsLayer = true }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backgroundGradient.frame = bounds
        let blackBlendStart = max(0.62, 1 - (notchHeight + 18) / max(1, bounds.height))
        backgroundGradient.locations = [
            NSNumber(value: 0),
            NSNumber(value: blackBlendStart),
            NSNumber(value: 1),
        ]
        shapeMask.frame = bounds
        shapeMask.path = islandPath(in: bounds, expansion: targetExpansion)
        CATransaction.commit()
    }

    func setInitialState(expanded: Bool) {
        targetExpansion = expanded ? 1 : 0
        layoutSubtreeIfNeeded()
        let opacity: Float = expanded ? 1 : 0
        let transform = expanded
            ? CATransform3DIdentity
            : CATransform3DMakeTranslation(0, 6, 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.removeAllAnimations()
        shapeMask.path = islandPath(in: bounds, expansion: targetExpansion)
        contentHost?.layer?.removeAllAnimations()
        contentHost?.layer?.opacity = opacity
        contentHost?.layer?.transform = transform
        CATransaction.commit()
    }

    func animateExpansion(expanded: Bool, duration: TimeInterval) {
        layoutSubtreeIfNeeded()
        let target: CGFloat = expanded ? 1 : 0
        let targetPath = islandPath(in: bounds, expansion: target)
        let currentPath = shapeMask.presentation()?.path ?? shapeMask.path ?? targetPath
        targetExpansion = target

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = targetPath
        CATransaction.commit()

        shapeMask.removeAnimation(forKey: "notchShape")
        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = currentPath
        animation.toValue = targetPath
        animation.duration = duration
        animation.timingFunction = NotchMotion.easeOut
        shapeMask.add(animation, forKey: "notchShape")
    }

    var currentShapePathForPromotion: CGPath? {
        shapeMask.presentation()?.path ?? shapeMask.path
    }

    func animatePromotion(
        fromExpandedHeight compactHeight: CGFloat,
        sourcePath: CGPath?
    ) {
        layoutSubtreeIfNeeded()
        let visibleCompactHeight = min(
            bounds.height,
            max(notchHeight, compactHeight)
        )
        let compactRect = NSRect(
            x: bounds.minX,
            y: bounds.maxY - visibleCompactHeight,
            width: bounds.width,
            height: visibleCompactHeight
        )
        let fallbackStartPath = islandPath(in: compactRect, expansion: 1)
        var translation = CGAffineTransform(
            translationX: 0,
            y: bounds.height - visibleCompactHeight
        )
        let startPath = sourcePath?.copy(using: &translation) ?? fallbackStartPath
        let targetPath = islandPath(in: bounds, expansion: 1)
        targetExpansion = 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.path = targetPath
        CATransaction.commit()

        shapeMask.removeAnimation(forKey: "notchShape")
        shapeMask.removeAnimation(forKey: "notchPromotion")
        let spring = CASpringAnimation(keyPath: "path")
        spring.mass = NotchMotion.promotionMass
        spring.stiffness = NotchMotion.promotionStiffness
        spring.damping = NotchMotion.promotionDamping
        spring.initialVelocity = 0
        spring.fromValue = startPath
        spring.toValue = targetPath
        spring.duration = NotchMotion.promotionDuration
        shapeMask.add(spring, forKey: "notchPromotion")

        for (index, view) in promotionRevealViews.enumerated() {
            animatePromotionReveal(
                view,
                delay: min(0.03 + Double(index) * 0.018, 0.10)
            )
        }
    }

    func prepareReducedMotionPromotion() {
        setInitialState(expanded: true)
        guard let layer = contentHost?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    func setControlsVisible(_ visible: Bool, animated: Bool) {
        let target: CGFloat = visible ? 1 : 0
        guard animated else {
            controls.forEach { $0.alphaValue = target }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? 0.12 : 0.14
            context.timingFunction = NotchMotion.ease
            controls.forEach { $0.animator().alphaValue = target }
        }
    }

    func animateContentIn(duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: 1,
            transform: CATransform3DIdentity,
            duration: duration
        )
    }

    func animateContentOut(duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: 0,
            transform: CATransform3DMakeTranslation(0, 4, 0),
            duration: duration
        )
    }

    func prepareReducedMotionOpen() {
        setInitialState(expanded: true)
        guard let layer = contentHost?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 0
        layer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    func animateReducedMotionContent(visible: Bool, duration: TimeInterval) {
        guard let contentHost else { return }
        animate(
            view: contentHost,
            opacity: visible ? 1 : 0,
            transform: CATransform3DIdentity,
            duration: duration
        )
    }

    var hasContentAnimationForTesting: Bool {
        contentHost?.layer?.animation(forKey: "notchContent") != nil
    }

    var hasPromotionSpringForTesting: Bool {
        shapeMask.animation(forKey: "notchPromotion") is CASpringAnimation
    }

    var promotionDampingRatioForTesting: CGFloat? {
        guard let spring = shapeMask.animation(forKey: "notchPromotion")
            as? CASpringAnimation else { return nil }
        return spring.damping / (2 * sqrt(spring.stiffness * spring.mass))
    }

    var headerTopInsetForTesting: CGFloat? {
        guard let headerView else { return nil }
        layoutSubtreeIfNeeded()
        let frame = headerView.convert(headerView.bounds, to: self)
        return bounds.maxY - frame.maxY
    }

    var headerHasAmbiguousLayoutForTesting: Bool {
        guard let headerView else { return false }
        layoutSubtreeIfNeeded()
        return ([headerView] + descendantViews(in: headerView)).contains(
            where: \.hasAmbiguousLayout
        )
    }

    var headerButtonTitlesForTesting: [String] {
        guard let headerView else { return [] }
        return ([headerView] + descendantViews(in: headerView)).compactMap {
            ($0 as? NSButton)?.title
        }
    }

    private func descendantViews(in view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap(descendantViews(in:))
    }

    func animateLaunch(selectedRow: TaskRowView?) {
        if let headerView {
            animate(
                view: headerView,
                opacity: 0,
                transform: CATransform3DMakeTranslation(0, 3, 0),
                duration: 0.07
            )
        }
        taskRows.forEach { $0.animateForLaunch(selected: $0 === selectedRow) }
    }

    private func animate(
        view: NSView,
        opacity: Float,
        transform: CATransform3D,
        duration: TimeInterval
    ) {
        guard let layer = view.layer else { return }
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        layer.transform = transform
        CATransaction.commit()

        layer.removeAnimation(forKey: "notchContent")
        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = currentOpacity
        opacityAnimation.toValue = opacity
        let transformAnimation = CABasicAnimation(keyPath: "transform")
        transformAnimation.fromValue = currentTransform
        transformAnimation.toValue = transform

        let group = CAAnimationGroup()
        group.animations = [opacityAnimation, transformAnimation]
        group.duration = duration
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "notchContent")
    }

    private func animatePromotionReveal(_ view: NSView, delay: TimeInterval) {
        guard let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        layer.removeAnimation(forKey: "notchPromotionReveal")
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        let transform = CABasicAnimation(keyPath: "transform")
        transform.fromValue = CATransform3DMakeTranslation(0, 5, 0)
        transform.toValue = CATransform3DIdentity
        let group = CAAnimationGroup()
        group.animations = [opacity, transform]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = NotchMotion.rowArrivalDuration
        group.fillMode = .backwards
        group.timingFunction = NotchMotion.easeOut
        layer.add(group, forKey: "notchPromotionReveal")
    }

    private func islandPath(in rect: NSRect, expansion: CGFloat) -> CGPath {
        let progress = min(1, max(0, expansion))
        let width = rect.width
        // Keep the mathematical edge outside the clipped layer. An edge exactly
        // at maxY gets anti-aliased into a one-pixel seam on bright desktops.
        let top = rect.maxY + 2
        let center = min(
            rect.maxX - notchWidth / 2 - 12,
            max(rect.minX + notchWidth / 2 + 12, rect.midX + notchCenterOffset)
        )
        let neckHalfWidth = min(notchWidth / 2, width / 2 - 20)
        let neckLeft = center - neckHalfWidth
        let neckRight = center + neckHalfWidth
        let neckBottom = max(rect.minY, rect.maxY - notchHeight)
        let closedRadius = min(CGFloat(10), min(notchHeight * 0.38, neckHalfWidth / 2))
        let expandedRadius = min(CGFloat(28), (width - bodyInset * 2) / 4)
        let bottomRadius = interpolate(closedRadius, expandedRadius, progress)
        let bodyLeft = interpolate(neckLeft, rect.minX + bodyInset, progress)
        let bodyRight = interpolate(neckRight, rect.maxX - bodyInset, progress)
        let bodyBottom = interpolate(neckBottom, rect.minY, progress)
        let neckEdgeBottom = interpolate(neckBottom + closedRadius, neckBottom + 4, progress)
        let topLeft = interpolate(neckLeft, rect.minX, progress)
        let topRight = interpolate(neckRight, rect.maxX, progress)
        let shoulderStartY = interpolate(neckEdgeBottom, top, progress)
        let shoulderBottom = interpolate(
            neckBottom + closedRadius,
            max(rect.minY + 32, rect.maxY - notchHeight),
            progress
        )
        let expandedShoulderControlY = rect.maxY - notchHeight * 0.46
        let shoulderControlY = interpolate(
            shoulderBottom,
            expandedShoulderControlY,
            progress
        )

        // Expanded, the whole top edge is black and clipped by the display
        // boundary. The body narrows through the shoulders like one oversized
        // notch. The extra zero-length lines preserve path compatibility with
        // the compact hardware-notch shape during interruptible animation.
        let path = CGMutablePath()
        path.move(to: CGPoint(x: topLeft, y: top))
        path.addLine(to: CGPoint(x: topRight, y: top))
        path.addLine(to: CGPoint(x: topRight, y: shoulderStartY))
        path.addCurve(
            to: CGPoint(x: bodyRight, y: shoulderBottom),
            control1: CGPoint(
                x: interpolate(neckRight, rect.maxX - bodyInset * 0.52, progress),
                y: shoulderStartY
            ),
            control2: CGPoint(
                x: bodyRight,
                y: shoulderControlY
            )
        )
        path.addLine(to: CGPoint(x: bodyRight, y: bodyBottom + bottomRadius))
        path.addCurve(
            to: CGPoint(x: bodyRight - bottomRadius, y: bodyBottom),
            control1: CGPoint(x: bodyRight, y: bodyBottom + bottomRadius * 0.45),
            control2: CGPoint(x: bodyRight - bottomRadius * 0.45, y: bodyBottom)
        )
        path.addLine(to: CGPoint(x: bodyLeft + bottomRadius, y: bodyBottom))
        path.addCurve(
            to: CGPoint(x: bodyLeft, y: bodyBottom + bottomRadius),
            control1: CGPoint(x: bodyLeft + bottomRadius * 0.45, y: bodyBottom),
            control2: CGPoint(x: bodyLeft, y: bodyBottom + bottomRadius * 0.45)
        )
        path.addLine(to: CGPoint(x: bodyLeft, y: shoulderBottom))
        path.addCurve(
            to: CGPoint(x: topLeft, y: shoulderStartY),
            control1: CGPoint(
                x: bodyLeft,
                y: shoulderControlY
            ),
            control2: CGPoint(
                x: interpolate(neckLeft, rect.minX + bodyInset * 0.52, progress),
                y: shoulderStartY
            )
        )
        path.addLine(to: CGPoint(x: topLeft, y: top))
        path.closeSubpath()
        return path
    }

    private func interpolate(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
        setControlsVisible(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
        setControlsVisible(false, animated: true)
    }
}
