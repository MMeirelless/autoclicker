import Foundation
import CoreGraphics

enum MouseButton: String, Codable, CaseIterable, Identifiable {
    case left, right, middle
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// One recorded or hand-made action inside a macro.
enum MacroStepKind: Codable, Equatable {
    case click(button: MouseButton, count: Int)
    case move
    case drag(button: MouseButton, to: CGPoint)
    case scroll(dx: Int32, dy: Int32)
    case key(keyCode: UInt32, modifiers: UInt)
    case wait(seconds: TimeInterval)

    var label: String {
        switch self {
        case .click(let button, let count):
            let prefix = count == 2 ? "Double " : count == 3 ? "Triple " : ""
            return "\(prefix)\(button.label) click"
        case .move: return "Move cursor"
        case .drag(let button, _): return "Drag (\(button.label.lowercased()))"
        case .scroll(let dx, let dy):
            var parts: [String] = []
            if dy > 0 { parts.append("up \(dy)") } else if dy < 0 { parts.append("down \(-dy)") }
            if dx > 0 { parts.append("left \(dx)") } else if dx < 0 { parts.append("right \(-dx)") }
            return "Scroll " + (parts.isEmpty ? "0" : parts.joined(separator: ", "))
        case .key(let keyCode, let modifiers):
            return "Key " + KeyCombo(keyCode: keyCode, modifiers: .init(rawValue: modifiers)).displayString
        case .wait(let seconds): return "Wait \(seconds.compactDescription)"
        }
    }

    var symbol: String {
        switch self {
        case .click: return "cursorarrow.click"
        case .move: return "cursorarrow.motionlines"
        case .drag: return "arrow.up.left.and.arrow.down.right"
        case .scroll: return "arrow.up.and.down"
        case .key: return "keyboard"
        case .wait: return "clock"
        }
    }

    var usesPosition: Bool {
        switch self {
        case .click, .move, .drag, .scroll: return true
        case .key, .wait: return false
        }
    }
}

struct MacroStep: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: MacroStepKind
    /// Delay before this step is executed (the "time interval" captured while recording).
    var delayBefore: TimeInterval = 0
    /// Position captured while recording (CoreGraphics coordinates). Always kept, even when
    /// `usePosition` is false, so it can be re-enabled later via the target toggle.
    var position: CGPoint? = nil
    /// The "target icon": replay at the saved point (true) or at the current cursor (false).
    var usePosition: Bool = true
    /// Optional per-step press duration override (seconds). nil → macro default.
    var holdDuration: TimeInterval? = nil
}

struct LoopConfig: Codable, Equatable {
    var enabled: Bool = false
    var infinite: Bool = true
    var count: Int = 5
}

struct MacroTimerConfig: Codable, Equatable {
    var delayedStartEnabled: Bool = false
    var delayedStart: HMS = HMS(seconds: 5)
    var dailyRepeatEnabled: Bool = false
    var dailyRepeatTime: TimeOfDay = TimeOfDay()
}

/// How the delays between steps are replayed.
enum IntervalMode: String, Codable, CaseIterable, Identifiable {
    case recorded, fixed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .recorded: return "As recorded (× speed)"
        case .fixed: return "Fixed interval"
        }
    }
}

struct Macro: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String = "New Macro"
    var steps: [MacroStep] = []
    /// Delay before the first step (seconds).
    var prestartDelay: TimeInterval = 0
    /// Default duration a key / mouse button stays pressed (seconds).
    var keyPressDuration: TimeInterval = 0.02
    var intervalMode: IntervalMode = .recorded
    /// Multiplier applied to recorded delays (2 = twice as fast).
    var speedMultiplier: Double = 1
    /// Used when `intervalMode == .fixed` (seconds).
    var fixedInterval: TimeInterval = 0.5
    var loop: LoopConfig = LoopConfig()
    var hotkey: KeyCombo? = nil
    var timer: MacroTimerConfig = MacroTimerConfig()
    /// Whether newly recorded mouse steps store their coordinates.
    var rememberCursorPosition: Bool = true
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var estimatedDuration: TimeInterval {
        var total = prestartDelay
        for step in steps {
            switch intervalMode {
            case .recorded: total += step.delayBefore / max(0.01, speedMultiplier)
            case .fixed: total += fixedInterval
            }
            if case .wait(let s) = step.kind { total += s }
        }
        return total
    }

    func duplicated() -> Macro {
        var copy = self
        copy.id = UUID()
        copy.name = name + " copy"
        copy.hotkey = nil
        copy.createdAt = Date()
        copy.modifiedAt = Date()
        copy.steps = steps.map { var s = $0; s.id = UUID(); return s }
        return copy
    }
}
