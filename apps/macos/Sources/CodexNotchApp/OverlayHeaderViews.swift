import AppKit

final class HostStatusBadgeView: ClosureButton {
    private let countLabel = NSTextField(labelWithString: "")

    override init(handler: (() -> Void)? = nil) {
        super.init(handler: handler)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        countLabel.font = .monospacedSystemFont(ofSize: 10.5, weight: .semibold)
        countLabel.alignment = .center
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(countLabel)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            countLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ overview: HostHealthOverview) {
        countLabel.stringValue = "\(overview.totalCount)"
        let color: NSColor
        if overview.problemCount > 0 {
            color = overview.workingCount > 0 ? .systemOrange : .systemRed
        } else if overview.checkingCount > 0 {
            color = NSColor.white.withAlphaComponent(0.42)
        } else {
            color = NSColor(calibratedRed: 0.40, green: 0.91, blue: 0.71, alpha: 1)
        }
        countLabel.textColor = color
        toolTip = overview.toolTipText
        setAccessibilityLabel(
            "Host status: \(overview.workingCount) of \(overview.totalCount) working"
        )
        setAccessibilityHelp("Open Connections settings")
    }

    var countTextForTesting: String { countLabel.stringValue }
    var countColorForTesting: NSColor? { countLabel.textColor }
}

final class WeeklyUsageHeaderView: ClosureButton {
    private let valueLabel = NSTextField(labelWithString: "")
    private let theme: NotchTheme

    init(
        state: CodexUsageState,
        theme: NotchTheme,
        refresh: @escaping () -> Void
    ) {
        self.theme = theme
        super.init(handler: refresh)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.065).cgColor
        layer?.cornerRadius = 9
        layer?.cornerCurve = .continuous

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            valueLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        update(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ state: CodexUsageState, now: Date = Date()) {
        switch state {
        case .idle:
            valueLabel.stringValue = ""
            valueLabel.textColor = theme.tertiaryText
            toolTip = nil
            isHidden = true
            setAccessibilityLabel("Weekly Codex usage unavailable")
            setAccessibilityValue(nil)
            setAccessibilityHelp(nil)
        case .loading:
            valueLabel.stringValue = "…"
            valueLabel.textColor = theme.tertiaryText
            toolTip = "Checking your weekly Codex limit."
            isHidden = false
            setAccessibilityLabel("Checking weekly Codex account limit")
            setAccessibilityValue(nil)
            setAccessibilityHelp("Refresh weekly usage")
        case .unavailable(let message):
            valueLabel.stringValue = "—%"
            valueLabel.textColor = .systemOrange
            toolTip = "Weekly account limit unavailable — \(message). Click to retry."
            isHidden = false
            setAccessibilityLabel("Weekly Codex account limit unavailable")
            setAccessibilityValue(message)
            setAccessibilityHelp("Retry reading weekly usage")
        case .available(let overview):
            let remaining = overview.limit.remainingPercent
            valueLabel.stringValue = "\(remaining)%"
            if remaining == 0 {
                valueLabel.textColor = .systemRed
            } else if remaining <= 20 {
                valueLabel.textColor = .systemOrange
            } else {
                valueLabel.textColor = theme.accent
            }
            toolTip = Self.toolTip(for: overview, now: now)
            isHidden = false
            setAccessibilityLabel("Weekly Codex account limit")
            setAccessibilityValue("\(remaining) percent remaining")
            setAccessibilityHelp("Refresh weekly usage")
        }
    }

    var valueTextForTesting: String { valueLabel.stringValue }
    var valueColorForTesting: NSColor? { valueLabel.textColor }
    var valueAllocatedWidthForTesting: CGFloat {
        layoutSubtreeIfNeeded()
        return valueLabel.frame.width
    }
    var valueIntrinsicWidthForTesting: CGFloat { valueLabel.intrinsicContentSize.width }
    var valueFitsWithoutTruncationForTesting: Bool {
        valueAllocatedWidthForTesting + 0.5 >= valueIntrinsicWidthForTesting
    }

    private static func toolTip(for overview: CodexUsageOverview, now: Date) -> String {
        var lines = [
            "You have \(overview.limit.remainingPercent)% of your weekly Codex limit remaining.",
            "Account-wide, not task context.",
            forecastText(overview.forecast, now: now),
        ]
        if let resetsAt = overview.limit.resetsAt {
            lines.append("Resets \(shortDate(resetsAt))")
        }
        if let trend = overview.recentTrend {
            let hours = max(1, Int((trend.observedFor / 3_600).rounded()))
            lines.append("Recent change: \(trend.usedPercent)% used over \(hours)h")
        }
        lines.append("")
        lines.append("Click to refresh.")
        return lines.joined(separator: "\n")
    }

    private static func forecastText(_ forecast: CodexUsageForecast, now: Date) -> String {
        switch forecast {
        case .depleted:
            return "Weekly limit reached"
        case .learning:
            return "Learning your pace"
        case .quiet:
            return "No recent usage change"
        case .lastsThroughReset:
            return "At this pace: lasts through reset"
        case .nearReset:
            return "At this pace: close to reset"
        case .exhausts(let estimatedAt, _):
            return "At this pace: \(timeRemaining(until: estimatedAt, now: now))"
        }
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        return formatter.string(from: date)
    }

    private static func timeRemaining(until date: Date, now: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        if remaining < 45 * 60 { return "<1h remaining" }
        if remaining < 48 * 60 * 60 {
            return "~\(max(1, Int((remaining / 3_600).rounded())))h remaining"
        }
        return "~\(max(2, Int((remaining / 86_400).rounded())))d remaining"
    }
}
