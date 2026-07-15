import CodexNotchCore
import Foundation

struct CodexUsageSample: Codable, Equatable {
    let recordedAt: Date
    let remainingPercent: Int
    let resetsAt: Date?
}

struct CodexUsageTrend: Equatable {
    let usedPercent: Int
    let observedFor: TimeInterval
}

enum CodexUsageForecast: Equatable {
    case depleted
    case learning(observedFor: TimeInterval)
    case quiet(observedFor: TimeInterval)
    case lastsThroughReset(pacePercentPerDay: Double)
    case nearReset(pacePercentPerDay: Double)
    case exhausts(estimatedAt: Date, pacePercentPerDay: Double)
}

struct CodexUsageOverview: Equatable {
    let limit: CodexWeeklyLimit
    let forecast: CodexUsageForecast
    let recentTrend: CodexUsageTrend?
}

enum CodexUsageEstimator {
    static let lookback: TimeInterval = 24 * 60 * 60
    static let minimumForecastSpan: TimeInterval = 60 * 60
    static let quietSpan: TimeInterval = 3 * 60 * 60
    static let minimumForecastChange = 2

    static func overview(
        limit: CodexWeeklyLimit,
        samples: [CodexUsageSample],
        now: Date = Date()
    ) -> CodexUsageOverview {
        let segment = currentTrendSegment(limit: limit, samples: samples, now: now)
        return CodexUsageOverview(
            limit: limit,
            forecast: forecast(limit: limit, segment: segment, now: now),
            recentTrend: recentTrend(in: segment)
        )
    }

    private static func forecast(
        limit: CodexWeeklyLimit,
        segment: [CodexUsageSample],
        now: Date
    ) -> CodexUsageForecast {
        if limit.remainingPercent == 0 { return .depleted }
        guard let first = segment.first, let last = segment.last else {
            return .learning(observedFor: 0)
        }

        let observedFor = max(0, last.recordedAt.timeIntervalSince(first.recordedAt))
        let consumed = max(0, first.remainingPercent - last.remainingPercent)
        guard observedFor >= minimumForecastSpan else {
            return .learning(observedFor: observedFor)
        }
        guard consumed >= minimumForecastChange else {
            if consumed == 0, observedFor >= quietSpan {
                return .quiet(observedFor: observedFor)
            }
            return .learning(observedFor: observedFor)
        }

        let observedHours = observedFor / 3_600
        let pointRate = Double(consumed) / observedHours
        let fastestPlausibleRate = Double(consumed + 1) / observedHours
        let slowestPlausibleRate = Double(max(0, consumed - 1)) / observedHours
        let pacePerDay = pointRate * 24
        let estimatedAt = now.addingTimeInterval(
            Double(limit.remainingPercent) / pointRate * 3_600
        )

        guard let resetsAt = limit.resetsAt, resetsAt > now else {
            return .exhausts(estimatedAt: estimatedAt, pacePercentPerDay: pacePerDay)
        }

        // The server exposes whole percentages. Treat the observed change as having
        // a one-point boundary ambiguity instead of presenting a false exact ETA.
        let earliestAt = now.addingTimeInterval(
            Double(limit.remainingPercent) / fastestPlausibleRate * 3_600
        )
        let latestAt = slowestPlausibleRate > 0
            ? now.addingTimeInterval(
                Double(limit.remainingPercent) / slowestPlausibleRate * 3_600
            )
            : nil

        if earliestAt >= resetsAt {
            return .lastsThroughReset(pacePercentPerDay: pacePerDay)
        }
        if latestAt == nil || latestAt! >= resetsAt {
            return .nearReset(pacePercentPerDay: pacePerDay)
        }
        return .exhausts(estimatedAt: estimatedAt, pacePercentPerDay: pacePerDay)
    }

    private static func recentTrend(in segment: [CodexUsageSample]) -> CodexUsageTrend? {
        guard let first = segment.first, let last = segment.last else { return nil }
        let observedFor = last.recordedAt.timeIntervalSince(first.recordedAt)
        let consumed = first.remainingPercent - last.remainingPercent
        guard observedFor >= minimumForecastSpan, consumed > 0 else { return nil }
        return CodexUsageTrend(usedPercent: consumed, observedFor: observedFor)
    }

    private static func currentTrendSegment(
        limit: CodexWeeklyLimit,
        samples: [CodexUsageSample],
        now: Date
    ) -> [CodexUsageSample] {
        let cutoff = now.addingTimeInterval(-lookback)
        var candidates = samples.filter {
            $0.recordedAt >= cutoff
                && $0.recordedAt <= now
                && sameWindow($0.resetsAt, limit.resetsAt)
        }.sorted { $0.recordedAt < $1.recordedAt }

        let current = CodexUsageSample(
            recordedAt: now,
            remainingPercent: limit.remainingPercent,
            resetsAt: limit.resetsAt
        )
        if let last = candidates.last, last.recordedAt == now {
            candidates[candidates.count - 1] = current
        } else {
            candidates.append(current)
        }

        // If remaining capacity rises without the reset timestamp changing, the
        // previous downward trend no longer describes this budget. Start again.
        var segmentStart = 0
        if candidates.count > 1 {
            for index in 1..<candidates.count
            where candidates[index].remainingPercent > candidates[index - 1].remainingPercent {
                segmentStart = index
            }
        }
        return Array(candidates[segmentStart...])
    }

    static func sameWindow(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.some(lhs), .some(rhs)):
            return abs(lhs.timeIntervalSince(rhs)) < 60
        default: return false
        }
    }
}

final class CodexUsageHistoryStore {
    static let idleCheckpointInterval: TimeInterval = 60 * 60
    static let retentionInterval: TimeInterval = 8 * 7 * 24 * 60 * 60
    static let maximumSampleCount = 2_048

    private let fileURL: URL
    private var samples: [CodexUsageSample]

    init(
        fileURL: URL = AppPaths.applicationSupport.appendingPathComponent("usage-history.json")
    ) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.codexNotch.decode([CodexUsageSample].self, from: data) {
            samples = decoded
                .filter { (0...100).contains($0.remainingPercent) }
                .sorted { $0.recordedAt < $1.recordedAt }
        } else {
            samples = []
        }
    }

    var storedSamples: [CodexUsageSample] { samples }

    @discardableResult
    func observe(_ limit: CodexWeeklyLimit, at now: Date = Date()) throws -> [CodexUsageSample] {
        let current = CodexUsageSample(
            recordedAt: now,
            remainingPercent: limit.remainingPercent,
            resetsAt: limit.resetsAt
        )
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        var updated = samples.filter { $0.recordedAt >= cutoff && $0.recordedAt <= now }
        let last = updated.last
        let shouldPersist = last == nil
            || last?.remainingPercent != current.remainingPercent
            || !CodexUsageEstimator.sameWindow(last?.resetsAt ?? nil, current.resetsAt)
            || now.timeIntervalSince(last?.recordedAt ?? .distantPast) >= Self.idleCheckpointInterval

        if shouldPersist {
            updated.append(current)
            updated = Array(updated.suffix(Self.maximumSampleCount))
            try persist(updated)
            samples = updated
        } else if updated.count != samples.count {
            try persist(updated)
            samples = updated
        }

        var observed = currentWindowSamples(for: limit)
        if observed.last?.recordedAt != now { observed.append(current) }
        return observed
    }

    func currentWindowSamples(for limit: CodexWeeklyLimit) -> [CodexUsageSample] {
        samples.filter { CodexUsageEstimator.sameWindow($0.resetsAt, limit.resetsAt) }
    }

    private func persist(_ value: [CodexUsageSample]) throws {
        try AppPaths.prepareDirectory(fileURL.deletingLastPathComponent())
        let data = try JSONEncoder.codexNotch.encode(value)
        try data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }
}
