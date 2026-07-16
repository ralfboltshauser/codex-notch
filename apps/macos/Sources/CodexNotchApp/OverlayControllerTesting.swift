import AppKit

// Test-facing observations live outside the controller's orchestration file so
// its production responsibilities remain reviewable. These are read-only and
// compiled into the executable target for @testable access.
extension OverlayController {
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
            + presentationCompletedTasks.compactMap {
                rowsByEventID[$0.eventID]?.badgeTextForTesting
            }
    }
    var taskRelativeTimesForTesting: [String] {
        presentationCompletedTasks.compactMap {
            rowsByEventID[$0.eventID]?.relativeTimeTextForTesting
        }
    }
    var triggeredTaskEventIDsForTesting: [String] {
        presentationCompletedTasks.compactMap { task in
            rowsByEventID[task.eventID]?.isTriggeredForTesting == true
                ? task.eventID
                : nil
        }
    }
    var rowArrivalAnimationCountForTesting: Int {
        rowsByEventID.values.filter(\.hasArrivalAnimationForTesting).count
    }

    var hasContentAnimationForTesting: Bool {
        rootView?.hasContentAnimationForTesting == true
    }
    var isTriggeredPresentationForTesting: Bool {
        presentationScope.triggeringEventID != nil
    }
    var hasPromotionSpringForTesting: Bool {
        rootView?.hasPromotionSpringForTesting == true
    }
    var promotionDampingRatioForTesting: CGFloat? {
        rootView?.promotionDampingRatioForTesting
    }
    var triggeredRowHasPromotionAnimationForTesting: Bool {
        guard let triggeringEventID else { return false }
        return rowsByEventID[triggeringEventID]?.hasPromotionAnimationForTesting == true
    }
    var headerTopInsetForTesting: CGFloat? { rootView?.headerTopInsetForTesting }
    var headerHasAmbiguousLayoutForTesting: Bool {
        rootView?.headerHasAmbiguousLayoutForTesting == true
    }
    var headerButtonTitlesForTesting: [String] {
        rootView?.headerButtonTitlesForTesting ?? []
    }
}
