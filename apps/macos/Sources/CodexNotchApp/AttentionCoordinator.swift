import AppKit
import Foundation

enum AttentionKind: Equatable {
    case approval
    case input
    case completion
    case update
    case connection
}

struct AttentionEvent: Equatable {
    let id: String
    let kind: AttentionKind
    let groupID: String
    let triggeringEventID: String?

    init(
        id: String,
        kind: AttentionKind,
        groupID: String? = nil,
        triggeringEventID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.groupID = groupID ?? id
        self.triggeringEventID = triggeringEventID
    }
}

enum AttentionDisposition: Equatable {
    case expand(playSound: Bool)
    case glance
    case collectSilently
}

enum AttentionPolicy {
    static func disposition(
        for kind: AttentionKind,
        mode: AttentionMode
    ) -> AttentionDisposition {
        switch mode {
        case .quiet:
            return .collectSilently
        case .glance:
            switch kind {
            case .approval, .input: return .expand(playSound: false)
            case .completion, .update, .connection: return .glance
            }
        case .notify:
            switch kind {
            case .approval, .input: return .expand(playSound: false)
            case .completion: return .expand(playSound: true)
            case .update, .connection: return .glance
            }
        }
    }
}

struct ActiveTaskAttentionTracker {
    private var previousStates: [String: ActiveTaskState] = [:]
    private var didEstablishBaseline = false
    private var sequence: UInt64 = 0

    mutating func events(for tasks: [ActiveTask]) -> [AttentionEvent] {
        let currentStates = Dictionary(uniqueKeysWithValues: tasks.map {
            (key(for: $0), $0.state)
        })
        defer {
            previousStates = currentStates
            didEstablishBaseline = true
        }
        guard didEstablishBaseline else { return [] }

        return tasks.compactMap { task in
            let key = key(for: task)
            let previous = previousStates[key]
            guard previous != .waitingForApproval, previous != .waitingForInput else {
                return nil
            }
            let kind: AttentionKind
            switch task.state {
            case .waitingForApproval: kind = .approval
            case .waitingForInput: kind = .input
            case .running, .unavailable: return nil
            }
            sequence &+= 1
            return AttentionEvent(
                id: "active:\(key):\(sequence)",
                kind: kind,
                groupID: "active:\(key)"
            )
        }
    }

    private func key(for task: ActiveTask) -> String {
        "\(task.sourceID)\u{0}\(task.threadID.lowercased())"
    }
}

struct ConnectionAttentionTracker {
    private var stableSnapshotHadProblem = false
    private var sequence: UInt64 = 0

    mutating func event(for snapshot: RemoteHostHealthSnapshot) -> AttentionEvent? {
        guard !snapshot.isRefreshing, snapshot.checkingCount == 0 else { return nil }
        let hasProblem = snapshot.problemCount > 0
        defer { stableSnapshotHadProblem = hasProblem }
        guard hasProblem, !stableSnapshotHadProblem else { return nil }
        sequence &+= 1
        return AttentionEvent(
            id: "connection:\(sequence)",
            kind: .connection,
            groupID: "connections"
        )
    }
}

final class AttentionCoordinator {
    private static let maximumRememberedEventCount = 128

    private let preferences: AttentionPreferences
    private var rememberedIDs: [String] = []
    private var rememberedIDSet: Set<String> = []
    private var unseenKindsByGroupID: [String: AttentionKind] = [:]
    private var preferenceObserver: NSObjectProtocol?

    var onExpand: ((AttentionEvent) -> Void)?
    var onPlaySound: (() -> Void)?
    var onGlanceCountChanged: ((Int) -> Void)?

    init(preferences: AttentionPreferences = .shared) {
        self.preferences = preferences
        preferenceObserver = NotificationCenter.default.addObserver(
            forName: AttentionPreferences.didChangeNotification,
            object: preferences,
            queue: .main
        ) { [weak self] _ in self?.attentionModeDidChange() }
    }

    deinit {
        if let preferenceObserver { NotificationCenter.default.removeObserver(preferenceObserver) }
    }

    var unseenCount: Int { unseenKindsByGroupID.count }

    func receive(_ event: AttentionEvent, isSurfaceVisible: Bool = false) {
        guard remember(event.id) else { return }
        switch AttentionPolicy.disposition(for: event.kind, mode: preferences.mode) {
        case .expand(let playSound):
            if playSound { onPlaySound?() }
            onExpand?(event)
        case .glance:
            guard !isSurfaceVisible else { return }
            let previousCount = unseenCount
            unseenKindsByGroupID[event.groupID] = event.kind
            if unseenCount != previousCount { publishPresentedCount() }
        case .collectSilently:
            break
        }
    }

    func markSeen() {
        guard !unseenKindsByGroupID.isEmpty else { return }
        unseenKindsByGroupID.removeAll()
        publishPresentedCount()
    }

    func retainCompletionGroups(_ inspectableGroupIDs: Set<String>) {
        let previousCount = unseenCount
        unseenKindsByGroupID = unseenKindsByGroupID.filter { entry in
            entry.value != .completion || inspectableGroupIDs.contains(entry.key)
        }
        if unseenCount != previousCount { publishPresentedCount() }
    }

    private func attentionModeDidChange() {
        publishPresentedCount()
    }

    private func publishPresentedCount() {
        onGlanceCountChanged?(preferences.mode == .quiet ? 0 : unseenCount)
    }

    private func remember(_ id: String) -> Bool {
        guard rememberedIDSet.insert(id).inserted else { return false }
        rememberedIDs.append(id)
        if rememberedIDs.count > Self.maximumRememberedEventCount {
            let overflow = rememberedIDs.count - Self.maximumRememberedEventCount
            let removed = rememberedIDs.prefix(overflow)
            rememberedIDSet.subtract(removed)
            rememberedIDs.removeFirst(overflow)
        }
        return true
    }
}

enum GlanceBadgePlacement {
    static let size = NSSize(width: 50, height: 20)
    static let hardwareAttachmentOverlap: CGFloat = 2

    static func frame(screenFrame: NSRect, notch: ScreenNotchGeometry) -> NSRect {
        let centerX = screenFrame.midX + notch.centerOffset
        let originY = notch.hasHardwareNotch
            ? screenFrame.maxY - notch.height - size.height + hardwareAttachmentOverlap
            : screenFrame.maxY - size.height - 2
        return NSRect(
            x: centerX - size.width / 2,
            y: originY,
            width: size.width,
            height: size.height
        )
    }
}

final class GlanceIndicatorController {
    private let panel: FocuslessPanel
    private let badge: GlanceBadgeButton
    private let screenProvider: () -> NSScreen?

    var onOpen: (() -> Void)? {
        didSet { badge.handler = onOpen }
    }

    init(screenProvider: @escaping () -> NSScreen? = {
        let location = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(location) }) ?? NSScreen.main
    }) {
        self.screenProvider = screenProvider
        badge = GlanceBadgeButton(theme: ThemeStore.shared.activeTheme)
        panel = FocuslessPanel(
            contentRect: NSRect(origin: .zero, size: GlanceBadgePlacement.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.appearance = NSAppearance(named: .darkAqua)
        OverlaySpaceBehavior.configure(panel)
        panel.contentView = badge
    }

    func update(count: Int) {
        guard count > 0 else {
            hide()
            return
        }
        badge.update(count: count, theme: ThemeStore.shared.activeTheme)
        guard !panel.isVisible, let screen = screenProvider() else { return }
        panel.setFrame(
            GlanceBadgePlacement.frame(
                screenFrame: screen.frame,
                notch: ScreenNotchGeometry(screen: screen)
            ),
            display: false
        )
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NotchMotion.reducedMotionFadeDuration
            context.timingFunction = NotchMotion.easeOut
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    var isVisibleForTesting: Bool { panel.isVisible }
    var frameForTesting: NSRect { panel.frame }
    var countForTesting: String { badge.countTextForTesting }
}

final class GlanceBadgeButton: ClosureButton {
    private let symbol = NSImageView()
    private let countLabel = NSTextField(labelWithString: "")

    init(theme: NotchTheme) {
        super.init()
        wantsLayer = true
        layer?.cornerRadius = GlanceBadgePlacement.size.height / 2
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        symbol.image = NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: nil
        )
        symbol.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        countLabel.alignment = .center
        [symbol, countLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 10),
            symbol.heightAnchor.constraint(equalToConstant: 10),
            countLabel.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 4),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
        update(count: 1, theme: theme)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(count: Int, theme: NotchTheme) {
        countLabel.stringValue = count > 99 ? "99+" : "\(count)"
        countLabel.textColor = theme.primaryText
        symbol.contentTintColor = theme.accent
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderColor = theme.accent.withAlphaComponent(0.58).cgColor
        toolTip = "\(count) unseen Codex \(count == 1 ? "signal" : "signals") — click to open"
        setAccessibilityLabel("Unseen Codex signals")
        setAccessibilityValue("\(count)")
    }

    var countTextForTesting: String { countLabel.stringValue }
}
