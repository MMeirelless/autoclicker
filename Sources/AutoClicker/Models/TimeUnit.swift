import Foundation

/// Time units used by the clicker schedule and the random-delay configuration.
enum TimeUnit: String, Codable, CaseIterable, Identifiable {
    case microseconds, milliseconds, seconds, minutes, hours

    var id: String { rawValue }

    /// Multiplier that converts a value in this unit to seconds.
    var seconds: Double {
        switch self {
        case .microseconds: return 1e-6
        case .milliseconds: return 1e-3
        case .seconds: return 1
        case .minutes: return 60
        case .hours: return 3600
        }
    }

    var label: String {
        switch self {
        case .microseconds: return "microseconds"
        case .milliseconds: return "milliseconds"
        case .seconds: return "seconds"
        case .minutes: return "minutes"
        case .hours: return "hours"
        }
    }

    var shortLabel: String {
        switch self {
        case .microseconds: return "µs"
        case .milliseconds: return "ms"
        case .seconds: return "s"
        case .minutes: return "min"
        case .hours: return "h"
        }
    }

    /// Range of values the interval picker allows for this unit (mirrors TapBot's ranges,
    /// extended with microseconds and 1–99 ms rapid mode).
    var intervalRange: ClosedRange<Int> {
        switch self {
        case .microseconds: return 100...999
        case .milliseconds: return 1...999
        case .seconds: return 1...999
        case .minutes: return 1...999
        case .hours: return 1...24
        }
    }

    /// Range used by the random-delay sliders/fields for this unit.
    var randomRange: ClosedRange<Int> {
        switch self {
        case .microseconds: return 0...999
        case .milliseconds: return 0...999
        case .seconds: return 0...59
        case .minutes: return 0...59
        case .hours: return 0...24
        }
    }
}

/// Hours / minutes / seconds triple used by delayed start and work duration timers.
struct HMS: Codable, Equatable, Hashable {
    var hours: Int = 0
    var minutes: Int = 0
    var seconds: Int = 0

    var totalSeconds: TimeInterval { TimeInterval(hours * 3600 + minutes * 60 + seconds) }
    var isZero: Bool { totalSeconds == 0 }

    init(hours: Int = 0, minutes: Int = 0, seconds: Int = 0) {
        self.hours = hours; self.minutes = minutes; self.seconds = seconds
    }

    init(totalSeconds: TimeInterval) {
        let t = max(0, Int(totalSeconds.rounded()))
        hours = t / 3600; minutes = (t % 3600) / 60; seconds = t % 60
    }

    var formatted: String {
        if hours > 0 { return String(format: "%dh %02dm %02ds", hours, minutes, seconds) }
        if minutes > 0 { return String(format: "%dm %02ds", minutes, seconds) }
        return "\(seconds)s"
    }
}

/// A wall-clock time of day (used by "daily repeat").
struct TimeOfDay: Codable, Equatable, Hashable {
    var hour: Int = 9
    var minute: Int = 0

    var formatted: String { String(format: "%02d:%02d", hour, minute) }

    /// The next `Date` (strictly after `now`) at which this time of day occurs.
    func nextOccurrence(after now: Date = Date(), calendar: Calendar = .current) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour; comps.minute = minute; comps.second = 0
        guard let today = calendar.date(from: comps) else { return now.addingTimeInterval(86_400) }
        if today > now { return today }
        return calendar.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)
    }
}

extension TimeInterval {
    /// Human readable, e.g. "1.5 ms", "250 µs", "2.00 s", "3m 05s".
    var compactDescription: String {
        if self == 0 { return "0" }
        if self < 1e-3 { return String(format: "%.0f µs", self * 1e6) }
        if self < 1 { return String(format: "%.1f ms", self * 1e3) }
        if self < 60 { return String(format: "%.2f s", self) }
        return HMS(totalSeconds: self).formatted
    }
}
