import AppKit
import Combine
import SwiftUI

/// Records mouse clicks, drags, scrolls, keyboard presses (and optionally cursor movement) into macro
/// steps using a listen-only CGEvent tap.
final class MacroRecorder: ObservableObject {
    enum State: Equatable { case idle, recording, paused }

    @Published private(set) var state: State = .idle
    @Published private(set) var steps: [MacroStep] = []
    /// "Remember mouse cursor position": new mouse steps store (and use) their coordinates.
    @Published var rememberCursorPosition = true
    /// Record cursor movement as "Move cursor" steps (sampled every 50 ms).
    @Published var recordMouseMovement = false
    @Published var error: String?

    var isActive: Bool { state != .idle }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Receives the recorded steps, or nil when the recording was cancelled.
    private var onFinish: (([MacroStep]?) -> Void)?
    private var panel: RecorderPanel?

    private var lastStepTicks: UInt64 = 0
    private var lastMoveTicks: UInt64 = 0
    private var pendingDown: (button: MouseButton, position: CGPoint, ticks: UInt64)?
    private var pendingScroll: (dx: Int32, dy: Int32, position: CGPoint, firstTicks: UInt64, lastTicks: UInt64)?

    /// Window frames (CG coordinates) whose events must be ignored (the recorder panel).
    private var ignoredFrames: () -> [CGRect] = { [] }

    // MARK: Control

    func start(initialSteps: [MacroStep] = [], rememberCursorPosition: Bool, onFinish: @escaping ([MacroStep]?) -> Void) {
        guard state == .idle else { return }
        guard Permissions.accessibilityGranted else {
            error = "Accessibility permission is required to record."
            Permissions.requestAccessibility()
            return
        }
        if !Permissions.inputMonitoringGranted {
            // Keyboard events are only delivered once Input Monitoring is granted; mouse works regardless.
            Permissions.requestInputMonitoring()
        }

        let mask: CGEventMask = [
            CGEventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved, .scrollWheel, .keyDown,
        ].reduce(0) { $0 | (1 << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<MacroRecorder>.fromOpaque(userInfo).takeUnretainedValue()
            recorder.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                          eventsOfInterest: mask, callback: callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            error = "Could not start recording. Check Accessibility and Input Monitoring permissions."
            return
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.onFinish = onFinish
        self.rememberCursorPosition = rememberCursorPosition
        steps = initialSteps
        error = nil
        pendingDown = nil
        pendingScroll = nil
        lastStepTicks = PreciseClock.now()
        lastMoveTicks = lastStepTicks
        state = .recording

        let panel = RecorderPanel(recorder: self)
        self.panel = panel
        ignoredFrames = { [weak panel] in
            guard let panel else { return [] }
            return [ScreenCoordinates.cgRect(fromCocoa: panel.frame)]
        }
        panel.show()
    }

    func pause() {
        guard state == .recording else { return }
        flushScroll()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        lastStepTicks = PreciseClock.now()
        pendingDown = nil
        state = .recording
    }

    /// Finishes recording and hands the steps to the caller.
    func stop() {
        guard state != .idle else { return }
        flushScroll()
        tearDown()
        let result = steps
        let finish = onFinish
        onFinish = nil
        finish?(result)
    }

    /// Stops when recording, dropping a key step captured in the last half second (the stop shortcut itself).
    func stopIfRecording() {
        guard state != .idle else { return }
        if let last = steps.last, case .key = last.kind,
           PreciseClock.seconds(forTicks: PreciseClock.now() &- lastStepTicks) < 0.5 {
            steps.removeLast()
        }
        stop()
    }

    /// Aborts; the caller receives nil instead of steps.
    func cancel() {
        guard state != .idle else { return }
        tearDown()
        let finish = onFinish
        onFinish = nil
        finish?(nil)
    }

    func removeLastStep() {
        if !steps.isEmpty { steps.removeLast() }
    }

    private func tearDown() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        panel?.close()
        panel = nil
        state = .idle
    }

    // MARK: Event handling (main run loop)

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard state == .recording else { return }
        let now = PreciseClock.now()
        let location = event.location

        let isMouse = type != .keyDown
        if isMouse, ignoredFrames().contains(where: { $0.contains(location) }) {
            // Clicks on the recorder panel are not part of the macro.
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown { pendingDown = nil }
            return
        }

        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            flushScroll()
            pendingDown = (button(for: type), location, now)

        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            let button = button(for: type)
            guard let down = pendingDown, down.button == button else { return }
            pendingDown = nil
            let distance = hypot(location.x - down.position.x, location.y - down.position.y)
            if distance >= 6 {
                append(kind: .drag(button: button, to: location), position: down.position, at: down.ticks)
            } else {
                let clickState = Int(event.getIntegerValueField(.mouseEventClickState))
                if clickState > 1, let last = steps.last, case .click(let b, let c) = last.kind, b == button, c == clickState - 1,
                   PreciseClock.seconds(forTicks: now &- lastStepTicks) < 1 {
                    steps[steps.count - 1].kind = .click(button: button, count: min(3, clickState))
                } else {
                    append(kind: .click(button: button, count: 1), position: down.position, at: down.ticks)
                }
            }

        case .mouseMoved:
            guard recordMouseMovement, pendingDown == nil else { return }
            if PreciseClock.seconds(forTicks: now &- lastMoveTicks) >= 0.05 {
                lastMoveTicks = now
                append(kind: .move, position: location, at: now, forcePosition: true)
            }

        case .scrollWheel:
            let dy = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
            let dx = Int32(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
            guard dx != 0 || dy != 0 else { return }
            if var pending = pendingScroll, PreciseClock.seconds(forTicks: now &- pending.lastTicks) < 0.25 {
                pending.dx += dx
                pending.dy += dy
                pending.lastTicks = now
                pendingScroll = pending
            } else {
                flushScroll()
                pendingScroll = (dx, dy, location, now, now)
            }

        case .keyDown:
            flushScroll()
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            var mods: NSEvent.ModifierFlags = []
            if event.flags.contains(.maskCommand) { mods.insert(.command) }
            if event.flags.contains(.maskAlternate) { mods.insert(.option) }
            if event.flags.contains(.maskControl) { mods.insert(.control) }
            if event.flags.contains(.maskShift) { mods.insert(.shift) }
            append(kind: .key(keyCode: keyCode, modifiers: mods.rawValue), position: nil, at: now)

        default:
            break
        }
    }

    private func button(for type: CGEventType) -> MouseButton {
        switch type {
        case .rightMouseDown, .rightMouseUp: return .right
        case .otherMouseDown, .otherMouseUp: return .middle
        default: return .left
        }
    }

    private func flushScroll() {
        guard let pending = pendingScroll else { return }
        pendingScroll = nil
        append(kind: .scroll(dx: pending.dx, dy: pending.dy), position: pending.position, at: pending.firstTicks)
    }

    private func append(kind: MacroStepKind, position: CGPoint?, at ticks: UInt64, forcePosition: Bool = false) {
        let delay = ticks >= lastStepTicks ? PreciseClock.seconds(forTicks: ticks &- lastStepTicks) : 0
        lastStepTicks = max(ticks, lastStepTicks)
        var step = MacroStep(kind: kind, delayBefore: (delay * 1000).rounded() / 1000)
        step.position = position
        step.usePosition = position != nil && (rememberCursorPosition || forcePosition)
        steps.append(step)
    }
}

// MARK: - Floating recording control panel

final class RecorderPanel: NSPanel {
    init(recorder: MacroRecorder) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 330, height: 150),
                   styleMask: [.titled, .nonactivatingPanel, .utilityWindow, .hudWindow],
                   backing: .buffered, defer: false)
        title = "Recording macro"
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: RecorderPanelView(recorder: recorder))
    }

    func show() {
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let f = screen.visibleFrame
            setFrameOrigin(NSPoint(x: f.maxX - frame.width - 20, y: f.maxY - frame.height - 20))
        }
        orderFrontRegardless()
    }
}

struct RecorderPanelView: View {
    @ObservedObject var recorder: MacroRecorder

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(recorder.state == .recording ? Color.red : Color.gray)
                    .frame(width: 10, height: 10)
                Text(recorder.state == .recording ? "Recording…" : "Paused")
                    .font(.headline)
                Spacer()
                Text("\(recorder.steps.count) step\(recorder.steps.count == 1 ? "" : "s")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Toggle("Remember mouse cursor position", isOn: $recorder.rememberCursorPosition)
            Toggle("Record mouse movement", isOn: $recorder.recordMouseMovement)
            HStack {
                if recorder.state == .recording {
                    Button("Pause") { recorder.pause() }
                } else {
                    Button("Resume") { recorder.resume() }
                }
                Button("Undo last") { recorder.removeLastStep() }.disabled(recorder.steps.isEmpty)
                Spacer()
                Button("Cancel") { recorder.cancel() }
                Button("Stop") { recorder.stop() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 330)
    }
}
