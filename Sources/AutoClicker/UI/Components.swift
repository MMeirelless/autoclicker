import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Integer text field with a stepper, clamped to a range.
struct IntField: View {
    var label: String? = nil
    @Binding var value: Int
    var range: ClosedRange<Int>
    var width: CGFloat = 64

    var body: some View {
        HStack(spacing: 4) {
            if let label { Text(label) }
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .onChange(of: value) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value = clamped }
                }
            Stepper("", value: $value, in: range).labelsHidden()
        }
    }
}

/// Decimal text field (e.g. milliseconds or seconds).
struct DoubleField: View {
    var label: String? = nil
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1_000_000
    var width: CGFloat = 72
    var suffix: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let label { Text(label) }
            TextField("", value: $value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: width)
                .onChange(of: value) { _, new in
                    let clamped = min(max(new, range.lowerBound), range.upperBound)
                    if clamped != new { value = clamped }
                }
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
    }
}

/// Hours / minutes / seconds editor.
struct HMSPicker: View {
    @Binding var value: HMS

    var body: some View {
        HStack(spacing: 10) {
            IntField(value: $value.hours, range: 0...999, width: 48)
            Text("h").foregroundStyle(.secondary)
            IntField(value: $value.minutes, range: 0...59, width: 44)
            Text("m").foregroundStyle(.secondary)
            IntField(value: $value.seconds, range: 0...59, width: 44)
            Text("s").foregroundStyle(.secondary)
        }
    }
}

/// Time-of-day editor backed by `TimeOfDay`.
struct TimeOfDayPicker: View {
    @Binding var value: TimeOfDay

    private var dateBinding: Binding<Date> {
        Binding<Date>(
            get: {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = value.hour
                comps.minute = value.minute
                return Calendar.current.date(from: comps) ?? Date()
            },
            set: { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                value = TimeOfDay(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            })
    }

    var body: some View {
        DatePicker("", selection: dateBinding, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .datePickerStyle(.stepperField)
    }
}

/// Records a global shortcut. Rejects combinations taken by macOS or by another shortcut in the app and
/// auto-suggests a free "Control + Number" alternative, like TapBot.
struct HotkeyRecorderView: View {
    let title: String
    @Binding var combo: KeyCombo?
    /// Other shortcuts assigned in the app (used for conflict detection).
    var taken: [KeyCombo] = []

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button(action: toggle) {
                    Text(recording ? "Press keys… (Esc cancels)" : (combo?.displayString ?? "Not set"))
                        .frame(minWidth: 110)
                        .foregroundStyle(recording ? Color.accentColor : (combo == nil ? .secondary : .primary))
                }
                if combo != nil && !recording {
                    Button {
                        combo = nil
                        message = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove shortcut")
                }
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.trailing)
            }
        }
        .onDisappear { stopMonitoring() }
    }

    private func toggle() {
        if recording { stopMonitoring() } else { begin() }
    }

    private func begin() {
        recording = true
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape, flags.isEmpty {
            stopMonitoring()
            return
        }
        let candidate = KeyCombo(keyCode: UInt32(event.keyCode), modifiers: event.modifierFlags)
        guard candidate.isValidGlobalHotkey else {
            message = "Add a modifier key (⌃ ⌥ ⇧ ⌘) or use a function key."
            return
        }
        let others = taken.filter { $0 != combo }
        let reason: String?
        if others.contains(candidate) {
            reason = "another shortcut in AutoClicker"
        } else if HotkeyManager.conflictsWithSystem(candidate) {
            reason = "macOS"
        } else if !HotkeyManager.shared.canRegister(candidate) {
            reason = "another app (another autoclicker or a second copy of AutoClicker?)"
        } else {
            reason = nil
        }
        if let reason {
            if let suggestion = HotkeyManager.suggestFreeCombo(avoiding: others, probe: true) {
                combo = suggestion
                message = "\(candidate.displayString) is used by \(reason). Assigned the free combination \(suggestion.displayString) instead — tip: Control + Number combos are usually free."
            } else {
                message = "\(candidate.displayString) is used by \(reason). Try a Control + Number combination."
            }
            stopMonitoring()
            return
        }
        combo = candidate
        message = nil
        stopMonitoring()
    }
}

/// Captures a single key (modifiers optional) for macro key steps.
struct KeyCaptureField: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: toggle) {
            Text(recording ? "Press a key…" : KeyCombo(keyCode: keyCode, modifiers: .init(rawValue: modifiers)).displayString)
                .frame(minWidth: 100)
        }
        .onDisappear { stop() }
    }

    private func toggle() { recording ? stop() : begin() }

    private func begin() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            keyCode = UInt32(event.keyCode)
            modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift, .function]).rawValue
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Small coloured status dot + text.
struct StatusDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}

extension CGPoint {
    var shortDescription: String { "(\(Int(x.rounded())), \(Int(y.rounded())))" }
}

extension CGRect {
    var shortDescription: String {
        "\(Int(minX.rounded())), \(Int(minY.rounded()))  •  \(Int(width.rounded())) × \(Int(height.rounded()))"
    }
}
