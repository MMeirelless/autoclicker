import Foundation
import CoreGraphics

/// What the clicker does on each tick.
enum ClickAction: String, Codable, CaseIterable, Identifiable {
    case left, right, middle, both, moveOnly, scroll

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: return "Left click"
        case .right: return "Right click"
        case .middle: return "Middle click"
        case .both: return "Both buttons"
        case .moveOnly: return "Move only"
        case .scroll: return "Scroll"
        }
    }

    var symbol: String {
        switch self {
        case .left: return "cursorarrow.click"
        case .right: return "cursorarrow.click.2"
        case .middle: return "computermouse"
        case .both: return "cursorarrow.click.badge.clock"
        case .moveOnly: return "cursorarrow.motionlines"
        case .scroll: return "arrow.up.and.down"
        }
    }

    var isClick: Bool { self == .left || self == .right || self == .middle || self == .both }
}

/// Single / double / triple click.
enum ClickCount: Int, Codable, CaseIterable, Identifiable {
    case single = 1, double = 2, triple = 3
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .single: return "Single"
        case .double: return "Double"
        case .triple: return "Triple"
        }
    }
}

enum ScrollDirection: String, Codable, CaseIterable, Identifiable {
    case up, down, left, right
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// (horizontal, vertical) sign. Positive vertical scrolls content up (like a wheel roll away from you).
    var vector: (dx: Int32, dy: Int32) {
        switch self {
        case .up: return (0, 1)
        case .down: return (0, -1)
        case .left: return (1, 0)
        case .right: return (-1, 0)
        }
    }
}

struct ScrollConfig: Codable, Equatable {
    var direction: ScrollDirection = .down
    /// Number of wheel "lines" per scroll event.
    var amount: Int = 3
}

/// "N clicks every V unit", e.g. 4 clicks every 7 minutes.
struct ScheduleConfig: Codable, Equatable {
    var clicks: Int = 1
    var intervalValue: Int = 1
    var intervalUnit: TimeUnit = .seconds

    var intervalSeconds: TimeInterval { Double(intervalValue) * intervalUnit.seconds }

    /// Average spacing between two consecutive clicks.
    var perClickSeconds: TimeInterval { intervalSeconds / Double(max(1, clicks)) }

    /// Hard floor so a misconfiguration cannot flood the window server (TapBot caps at
    /// 99 clicks / 100 ms ≈ 1 ms).
    static let minimumPerClickSeconds: TimeInterval = 0.001

    var clicksPerSecond: Double { 1 / max(perClickSeconds, Self.minimumPerClickSeconds) }
}

/// One randomizable component of the random delay (per unit).
struct RandomComponent: Codable, Equatable, Identifiable {
    var unit: TimeUnit
    var enabled: Bool = false
    var min: Int = 0
    var max: Int = 1

    var id: TimeUnit { unit }

    func sample() -> TimeInterval {
        guard enabled else { return 0 }
        let lo = Swift.min(min, max), hi = Swift.max(min, max)
        let v = lo == hi ? Double(lo) : Double.random(in: Double(lo)...Double(hi))
        return v * unit.seconds
    }
}

/// Random schedule mode: imitates natural, non-robotic clicking.
struct RandomScheduleConfig: Codable, Equatable {
    var enabled: Bool = false
    /// TapBot's random mode: clicks fall at random moments inside each interval window
    /// instead of being evenly spaced.
    var spreadWithinInterval: Bool = true
    /// Additional random delay added after every click, built from any combination of units.
    var components: [RandomComponent] = [
        RandomComponent(unit: .hours, min: 0, max: 1),
        RandomComponent(unit: .minutes, min: 0, max: 5),
        RandomComponent(unit: .seconds, min: 0, max: 10),
        RandomComponent(unit: .milliseconds, min: 0, max: 500),
        RandomComponent(unit: .microseconds, min: 0, max: 999),
    ]

    var anyComponentEnabled: Bool { components.contains { $0.enabled } }

    /// Sum of one random sample from every enabled component.
    func sampleExtraDelay() -> TimeInterval {
        guard enabled else { return 0 }
        return components.reduce(0) { $0 + $1.sample() }
    }

    var maximumExtraDelay: TimeInterval {
        components.filter(\.enabled).reduce(0) { $0 + Double(Swift.max($1.min, $1.max)) * $1.unit.seconds }
    }
}

enum LocationMode: String, Codable, CaseIterable, Identifiable {
    case cursor, fixedPoint, area
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cursor: return "Current cursor position"
        case .fixedPoint: return "Fixed point"
        case .area: return "Selected area"
        }
    }
}

struct LocationConfig: Codable, Equatable {
    var mode: LocationMode = .cursor
    /// Stored in CoreGraphics global coordinates (origin top-left of the main display).
    var fixedPoint: CGPoint? = nil
    /// Stored in CoreGraphics global coordinates.
    var area: CGRect? = nil
    /// "Randomly move": clicks land on random points across the screen or inside the area.
    var randomMove: Bool = false
    /// TapBot behaviour: if the cursor leaves the area, clicking pauses until it returns.
    var pauseWhenCursorLeavesArea: Bool = true
    /// Show a translucent outline of the area while the clicker runs.
    var showAreaOverlay: Bool = true
}

struct TimerConfig: Codable, Equatable {
    var delayedStartEnabled: Bool = false
    var delayedStart: HMS = HMS(minutes: 0, seconds: 5)

    var workDurationEnabled: Bool = false
    var workDuration: HMS = HMS(minutes: 8)

    var clickLimitEnabled: Bool = false
    var clickLimit: Int = 10_000

    var dailyRepeatEnabled: Bool = false
    var dailyRepeatTime: TimeOfDay = TimeOfDay()
}

/// Full configuration of the clicker.
struct ClickerConfig: Codable, Equatable {
    var action: ClickAction = .left
    var clickCount: ClickCount = .single
    /// How long the button is held down (key press duration), in milliseconds.
    var holdDurationMs: Double = 0
    var scroll: ScrollConfig = ScrollConfig()
    var schedule: ScheduleConfig = ScheduleConfig()
    var random: RandomScheduleConfig = RandomScheduleConfig()
    var location: LocationConfig = LocationConfig()
    var timers: TimerConfig = TimerConfig()
}
