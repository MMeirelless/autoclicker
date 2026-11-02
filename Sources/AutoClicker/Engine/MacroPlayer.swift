import AppKit
import Combine

/// Plays macros, each on its own thread, so several can run at once.
final class MacroPlayer: ObservableObject {
    @Published private(set) var runningIDs: Set<UUID> = []
    /// Macros waiting on a delayed start, with the date they will start.
    @Published private(set) var scheduled: [UUID: Date] = [:]
    /// Next daily-repeat run per macro.
    @Published private(set) var nextDailyRuns: [UUID: Date] = [:]
    @Published var lastMessage: String?

    private var tokens: [UUID: AtomicFlag] = [:]
    private var startTimers: [UUID: Timer] = [:]
    private var dailyTimers: [UUID: Timer] = [:]

    /// Supplies the latest version of a macro (daily repeat uses the current definition).
    var macroProvider: (UUID) -> Macro? = { _ in nil }

    var isAnythingActive: Bool { !runningIDs.isEmpty || !scheduled.isEmpty }

    func isRunning(_ id: UUID) -> Bool { runningIDs.contains(id) }
    func isScheduled(_ id: UUID) -> Bool { scheduled[id] != nil }

    // MARK: Control

    func toggle(_ macro: Macro) {
        if isRunning(macro.id) || isScheduled(macro.id) { stop(macro.id) } else { play(macro) }
    }

    func play(_ macro: Macro, ignoreDelayedStart: Bool = false) {
        guard !isRunning(macro.id), !isScheduled(macro.id) else { return }
        guard Permissions.accessibilityGranted else {
            lastMessage = "Accessibility permission is required."
            Permissions.requestAccessibility()
            return
        }
        guard !macro.steps.isEmpty else {
            lastMessage = "“\(macro.name)” has no steps."
            return
        }
        lastMessage = nil
        if !ignoreDelayedStart, macro.timer.delayedStartEnabled, !macro.timer.delayedStart.isZero {
            let delay = macro.timer.delayedStart.totalSeconds
            scheduled[macro.id] = Date().addingTimeInterval(delay)
            startTimers[macro.id] = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.scheduled[macro.id] = nil
                self.startTimers[macro.id] = nil
                self.beginRunning(macro)
            }
        } else {
            beginRunning(macro)
        }
    }

    func stop(_ id: UUID) {
        startTimers[id]?.invalidate()
        startTimers[id] = nil
        scheduled[id] = nil
        tokens[id]?.set()
        tokens[id] = nil
        runningIDs.remove(id)
    }

    /// Stops every running or scheduled macro (the ⌃0 shortcut).
    func stopAll() {
        for id in Set(runningIDs).union(scheduled.keys) { stop(id) }
    }

    private func beginRunning(_ macro: Macro) {
        let token = AtomicFlag()
        tokens[macro.id] = token
        runningIDs.insert(macro.id)
        let thread = Thread { [weak self] in
            self?.run(macro, token: token)
            DispatchQueue.main.async {
                guard let self, self.tokens[macro.id] === token else { return }
                self.tokens[macro.id] = nil
                self.runningIDs.remove(macro.id)
            }
        }
        thread.name = "AutoClicker.Macro.\(macro.name)"
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    // MARK: Worker

    private func run(_ macro: Macro, token: AtomicFlag) {
        guard PreciseClock.sleep(seconds: macro.prestartDelay, cancel: token) else { return }
        var iteration = 0
        repeat {
            for step in macro.steps {
                if token.isSet { return }
                let delay: TimeInterval
                switch macro.intervalMode {
                case .recorded: delay = step.delayBefore / max(0.01, macro.speedMultiplier)
                case .fixed: delay = macro.fixedInterval
                }
                guard PreciseClock.sleep(seconds: delay, cancel: token) else { return }
                perform(step, in: macro, cancel: token)
            }
            iteration += 1
        } while macro.loop.enabled && (macro.loop.infinite || iteration < max(1, macro.loop.count)) && !token.isSet
    }

    private func perform(_ step: MacroStep, in macro: Macro, cancel: AtomicFlag) {
        let hold = step.holdDuration ?? macro.keyPressDuration
        let current = EventSynthesizer.cursorPosition()
        let target = (step.usePosition ? step.position : nil) ?? current

        switch step.kind {
        case .click(let button, let count):
            if target != current { EventSynthesizer.move(to: target) }
            EventSynthesizer.click(button: button, at: target, count: count, hold: hold, cancel: cancel)
        case .move:
            EventSynthesizer.move(to: target)
        case .drag(let button, let to):
            EventSynthesizer.drag(button: button, from: target, to: to, hold: hold, cancel: cancel)
        case .scroll(let dx, let dy):
            EventSynthesizer.scroll(dx: dx, dy: dy, at: step.usePosition ? target : nil)
        case .key(let keyCode, let modifiers):
            EventSynthesizer.keyPress(keyCode: keyCode, modifiers: NSEvent.ModifierFlags(rawValue: modifiers),
                                      hold: hold, cancel: cancel)
        case .wait(let seconds):
            PreciseClock.sleep(seconds: seconds, cancel: cancel)
        }
    }

    // MARK: Daily repeat

    /// Re-arms the daily timers to match the given macro list.
    func syncDailyTimers(_ macros: [Macro]) {
        let wanted = Dictionary(uniqueKeysWithValues: macros.filter { $0.timer.dailyRepeatEnabled }.map { ($0.id, $0) })
        for id in Array(dailyTimers.keys) where wanted[id] == nil {
            dailyTimers[id]?.invalidate()
            dailyTimers[id] = nil
            nextDailyRuns[id] = nil
        }
        for (id, macro) in wanted {
            let next = macro.timer.dailyRepeatTime.nextOccurrence()
            if let existing = dailyTimers[id], abs(existing.fireDate.timeIntervalSince(next)) < 1 { continue }
            dailyTimers[id]?.invalidate()
            arm(id: id, at: next)
        }
    }

    private func arm(id: UUID, at date: Date) {
        nextDailyRuns[id] = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let macro = self.macroProvider(id) {
                if !self.isRunning(id) { self.play(macro, ignoreDelayedStart: true) }
                if macro.timer.dailyRepeatEnabled {
                    self.arm(id: id, at: macro.timer.dailyRepeatTime.nextOccurrence())
                    return
                }
            }
            self.dailyTimers[id] = nil
            self.nextDailyRuns[id] = nil
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        dailyTimers[id] = timer
    }
}
