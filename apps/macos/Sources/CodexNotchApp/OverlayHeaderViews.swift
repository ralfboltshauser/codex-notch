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
    private static let minimumWidth: CGFloat = 50
    private static let horizontalContentInset: CGFloat = 8

    private struct StaleContext {
        let observedAt: Date
        let message: String
    }

    private let valueLabel = NSTextField(labelWithString: "")
    private let theme: NotchTheme
    private var preferredValueWidth: CGFloat = 0

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: max(
                Self.minimumWidth,
                preferredValueWidth + (Self.horizontalContentInset * 2)
            ),
            height: 22
        )
    }

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
        valueLabel.maximumNumberOfLines = 2
        valueLabel.lineBreakMode = .byClipping
        valueLabel.usesSingleLineMode = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumWidth),
            valueLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.horizontalContentInset
            ),
            valueLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -Self.horizontalContentInset
            ),
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
            updatePreferredValueWidth()
            valueLabel.textColor = theme.tertiaryText
            toolTip = nil
            isHidden = true
            setAccessibilityLabel("Codex account usage unavailable")
            setAccessibilityValue(nil)
            setAccessibilityHelp(nil)
        case .loading:
            valueLabel.stringValue = "…"
            updatePreferredValueWidth()
            valueLabel.textColor = theme.tertiaryText
            toolTip = "Checking your Codex account limits."
            isHidden = false
            setAccessibilityLabel("Checking Codex account limits")
            setAccessibilityValue(nil)
            setAccessibilityHelp("Refresh account usage")
        case .unavailable(let message):
            valueLabel.stringValue = "—%"
            updatePreferredValueWidth()
            valueLabel.textColor = .systemOrange
            toolTip = "Codex account limits unavailable — \(message). Click to retry."
            isHidden = false
            setAccessibilityLabel("Codex account limits unavailable")
            setAccessibilityValue(message)
            setAccessibilityHelp("Retry reading account usage")
        case .available(let overview):
            render(overview.windows, weeklyOverview: overview, now: now)
        case .availableWindows(let windows):
            render(windows, weeklyOverview: nil, now: now)
        case .stale(let windows, let observedAt, let message):
            render(
                windows,
                weeklyOverview: nil,
                now: now,
                stale: StaleContext(observedAt: observedAt, message: message)
            )
        }
    }

    var valueTextForTesting: String { valueLabel.stringValue }
    var valueColorForTesting: NSColor? { valueLabel.textColor }
    var valueAllocatedWidthForTesting: CGFloat {
        layoutSubtreeIfNeeded()
        return valueLabel.frame.width
    }
    var valueIntrinsicWidthForTesting: CGFloat { valueLabel.intrinsicContentSize.width }
    var valueRequiredWidthForTesting: CGFloat { preferredValueWidth }
    var valueFitsWithoutTruncationForTesting: Bool {
        valueAllocatedWidthForTesting + 0.5 >= valueRequiredWidthForTesting
    }

    private func render(
        _ windows: [CodexRateLimitWindow],
        weeklyOverview: CodexUsageOverview?,
        now: Date,
        stale: StaleContext? = nil
    ) {
        guard !windows.isEmpty else {
            update(.unavailable(message: "Codex returned no account usage windows"), now: now)
            return
        }

        if stale != nil {
            valueLabel.textColor = .systemOrange
        } else if windows.contains(where: \.isReached) {
            valueLabel.textColor = .systemRed
        } else if windows.contains(where: { $0.remainingPercent <= 20 }) {
            valueLabel.textColor = .systemOrange
        } else {
            valueLabel.textColor = theme.accent
        }
        valueLabel.attributedStringValue = compactValue(
            windows,
            labelsSingleWindow: weeklyOverview == nil,
            isStale: stale != nil
        )
        updatePreferredValueWidth()
        toolTip = Self.toolTip(
            for: windows,
            weeklyOverview: weeklyOverview,
            now: now,
            stale: stale
        )
        isHidden = false
        if let stale {
            setAccessibilityLabel("Codex account limits stale")
            setAccessibilityValue(
                "Last updated \(Self.relativeAge(since: stale.observedAt, now: now)); "
                    + windows.map(Self.accessibilityValue).joined(separator: "; ")
            )
            setAccessibilityHelp("Retry reading account usage")
        } else {
            setAccessibilityLabel("Codex account limits")
            setAccessibilityValue(windows.map(Self.accessibilityValue).joined(separator: "; "))
            setAccessibilityHelp("Refresh account usage")
        }
    }

    private func updatePreferredValueWidth() {
        let value = valueLabel.attributedStringValue
        let string = value.string as NSString
        var widest: CGFloat = 0
        var location = 0

        while location < string.length {
            let remaining = NSRange(location: location, length: string.length - location)
            let newline = string.range(of: "\n", options: [], range: remaining)
            let lineEnd = newline.location == NSNotFound ? string.length : newline.location
            let lineRange = NSRange(location: location, length: lineEnd - location)
            widest = max(widest, ceil(value.attributedSubstring(from: lineRange).size().width))
            guard newline.location != NSNotFound else { break }
            location = NSMaxRange(newline)
        }

        preferredValueWidth = widest
        invalidateIntrinsicContentSize()
    }

    private func compactValue(
        _ windows: [CodexRateLimitWindow],
        labelsSingleWindow: Bool,
        isStale: Bool
    ) -> NSAttributedString {
        let multiple = windows.count > 1
        let font = NSFont.monospacedSystemFont(
            ofSize: multiple ? 8 : 10.5,
            weight: .semibold
        )
        let result = NSMutableAttributedString(string: "")

        for (index, window) in windows.prefix(2).enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: [.font: font]))
            }
            if isStale {
                result.append(NSAttributedString(
                    string: "stale ",
                    attributes: [.font: font, .foregroundColor: NSColor.systemOrange]
                ))
            }
            if multiple || labelsSingleWindow {
                result.append(NSAttributedString(
                    string: "\(window.durationLabel) ",
                    attributes: [.font: font, .foregroundColor: theme.tertiaryText]
                ))
            }
            result.append(NSAttributedString(
                string: window.isReached ? "reached" : "\(window.remainingPercent)%",
                attributes: [
                    .font: font,
                    .foregroundColor: statusColor(window, isStale: isStale),
                ]
            ))
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        if multiple {
            paragraph.minimumLineHeight = 9
            paragraph.maximumLineHeight = 9
        }
        result.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: result.length)
        )
        return result
    }

    private func statusColor(_ window: CodexRateLimitWindow, isStale: Bool) -> NSColor {
        if isStale { return .systemOrange }
        if window.isReached { return .systemRed }
        if window.remainingPercent <= 20 { return .systemOrange }
        return theme.accent
    }

    private static func accessibilityValue(_ window: CodexRateLimitWindow) -> String {
        let status = window.isReached
            ? "limit reached"
            : "\(window.remainingPercent) percent remaining"
        return "\(spokenDuration(window.durationMinutes)): \(status)"
    }

    private static func toolTip(
        for windows: [CodexRateLimitWindow],
        weeklyOverview: CodexUsageOverview?,
        now: Date,
        stale: StaleContext?
    ) -> String {
        var lines: [String] = []
        if let stale {
            lines.append("Stale — last updated \(relativeAge(since: stale.observedAt, now: now)).")
            lines.append("Latest refresh failed — \(stale.message).")
        }
        for window in windows {
            if stale != nil, window.isWeekly {
                lines.append(window.isReached
                    ? "Last known weekly Codex limit: reached."
                    : "Last known weekly Codex limit: \(window.remainingPercent)% remaining.")
            } else if stale != nil {
                lines.append(window.isReached
                    ? "Last known \(window.durationLabel) Codex limit: reached."
                    : "Last known \(window.durationLabel): \(window.remainingPercent)% remaining.")
            } else if window.isWeekly {
                lines.append(window.isReached
                    ? "Weekly Codex limit reached."
                    : "You have \(window.remainingPercent)% of your weekly Codex limit remaining.")
            } else {
                lines.append(window.isReached
                    ? "\(window.durationLabel) Codex limit reached."
                    : "\(window.durationLabel): \(window.remainingPercent)% remaining.")
            }
            if let resetsAt = window.resetsAt {
                let prefix = stale == nil ? "" : "Last known "
                lines.append("\(prefix)\(window.durationLabel) resets \(shortDate(resetsAt))")
            }
        }
        lines.append("Account-wide, not task context.")
        if stale == nil, let weeklyOverview {
            if case .depleted = weeklyOverview.forecast {
                // The reached state is already stated beside the seven-day window.
            } else {
                lines.append(forecastText(weeklyOverview.forecast, now: now))
            }
        }
        if stale == nil, let trend = weeklyOverview?.recentTrend {
            let hours = max(1, Int((trend.observedFor / 3_600).rounded()))
            lines.append("Recent change: \(trend.usedPercent)% used over \(hours)h")
        }
        lines.append("")
        lines.append("Click to refresh.")
        return lines.joined(separator: "\n")
    }

    private static func relativeAge(since observedAt: Date, now: Date) -> String {
        let age = max(0, now.timeIntervalSince(observedAt))
        if age < 60 { return "less than a minute ago" }
        if age < 60 * 60 { return "\(max(1, Int(age / 60)))m ago" }
        if age < 24 * 60 * 60 { return "\(max(1, Int(age / 3_600)))h ago" }
        return "\(max(1, Int(age / 86_400)))d ago"
    }

    private static func spokenDuration(_ minutes: Int) -> String {
        if minutes.isMultiple(of: 24 * 60) {
            let days = minutes / (24 * 60)
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return "\(minutes) minutes"
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
