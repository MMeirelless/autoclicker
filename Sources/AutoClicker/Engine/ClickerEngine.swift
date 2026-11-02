import AppKit
import Combine

/// Produces the deadline of the next click according to the schedule and random settings.
struct ClickScheduler {
    let schedule: ScheduleConfig
    let random: RandomScheduleConfig

    private var last: UInt64 = 0
    private var windowStart: UInt64 = 0
    private var pending: [UInt64] = []
    private var first = true

    init(schedule: ScheduleConfig, random: RandomScheduleConfig) {
        self.schedule = schedule
        self.random = random
    }

    mutating func begin(at now: UInt64) {
        last = now
        windowStart = now
        pending = []
        first = true
    }

    /// Returns the absolute tick at which the next click should fire.
    mutating func nextDeadline() -> UInt64 {
        let now = PreciseClock.now()
        let intervalTicks = PreciseClock.ticks(forSeconds: schedule.intervalSeconds)
        let floorTicks = PreciseClock.ticks(forSeconds: ScheduleConfig.minimumPerClickSeconds)
        let n = max(1, schedule.clicks)
        var deadline: UInt64

        if random.enabled && random.spreadWithinInterval {
            // Random mode: N clicks at random moments inside each interval window.
            if pending.isEmpty {
                if first {
                    windowStart = now
                } else {
                    windowStart = max(windowStart &+ intervalTicks, last)
                }
                let width = max(1, intervalTicks)
                pending = (0..<n).map { _ in UInt64.random(in: 0..<width) }.sorted()
            }
            deadline = windowStart &+ pending.removeFirst()
        } else {
            // Fixed mode: evenly spaced clicks, the first one immediately.
            if first {
                deadline = now
            } else {
                let per = max(schedule.perClickSeconds, ScheduleConfig.minimumPerClickSeconds)
                deadline = last &+ PreciseClock.ticks(forSeconds: per)
            }
        }

        // Extra random delay composed of hours / minutes / seconds / ms / µs components.
        if random.enabled {
            deadline = deadline &+ PreciseClock.ticks(forSeconds: random.sampleExtraDelay())
        }

        if !first, deadline < last &+ floorTicks { deadline = last &+ floorTicks }
        if deadline < now { deadline = now }

        first = false
        last = deadline
        return deadline
    }
}

/// Runs the clicker on a dedicated high-priority thread and publishes its status on the main thread.
final class ClickerEngine: ObservableObject {
    enum Status: Equatable {
        case idle
        case waiting(startAt: Date)
        case running(since: Date)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var clicksPerformed: Int = 0
    @Published private(set) var pausedOutsideArea = false
    @Published private(set) var nextDailyRun: Date?
    @Published var lastMessage: String?

    /// Supplies the current configuration for hotkey / daily-repeat starts.
    var configProvider: () -> ClickerConfig = { ClickerConfig() }
    /// Called when the clicker transitions between active and idle (menu-bar icon colour).
    var onActiveChanged: ((Bool) -> Void)?
    /// Called with the active area while running (area overlay window).
    var onAreaOverlayChanged: ((CGRect?) -> Void)?

    var isActive: Bool { status != .idle }

    private var worker: Thread?
    private var cancel = AtomicFlag()
    private var startTimer: Timer?
    private var dailyTimer: Timer?
    private var activeConfig: ClickerConfig?

    // MARK: Control

    func toggle() {
        if isActive { stop() } else { start(config: configProvider()) }
    }

    func start(config: ClickerConfig) {
        guard !isActive else { return }
        guard Permissions.accessibilityGranted else {
            lastMessage = "Accessibility permission is required."
            Permissions.requestAccessibility()
            return
        }
        lastMessage = nil
        clicksPerformed = 0
        pausedOutsideArea = false
        activeConfig = config

        if config.timers.delayedStartEnabled, !config.timers.delayedStart.isZero {
            let delay = config.timers.delayedStart.totalSeconds
            status = .waiting(startAt: Date().addingTimeInterval(delay))
            onActiveChanged?(true)
            startTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                self?.beginRunning()
            }
        } else {
            beginRunning()
        }
    }

    /// Skips a pending delayed start and runs immediately (TapBot: "use your shortcut").
    func startNow() {
        if case .waiting = status {
            startTimer?.invalidate()
            startTimer = nil
            beginRunning()
        }
    }

    func stop() {
        startTimer?.invalidate()
        startTimer = nil
        cancel.set()
        worker = nil
        activeConfig = nil
        if status != .idle {
            status = .idle
            onActiveChanged?(false)
            onAreaOverlayChanged?(nil)
        }
        pausedOutsideArea = false
    }

    private func beginRunning() {
        guard let config = activeConfig else { return }
        let token = AtomicFlag()
        cancel = token
        status = .running(since: Date())
        onActiveChanged?(true)
        if config.location.mode == .area, config.location.showAreaOverlay, let area = config.location.area {
            onAreaOverlayChanged?(area)
        }
        let thread = Thread { [weak self] in
            self?.run(config: config, token: token)
        }
        thread.name = "AutoClicker.Clicker"
        thread.qualityOfService = .userInteractive
        thread.threadPriority = 1.0
        worker = thread
        thread.start()
    }

    // MARK: Worker loop

    private func run(config: ClickerConfig, token: AtomicFlag) {
        var scheduler = ClickScheduler(schedule: config.schedule, random: config.random)
        let startTicks = PreciseClock.now()
        scheduler.begin(at: startTicks)

        let durationTicks: UInt64? = config.timers.workDurationEnabled && !config.timers.workDuration.isZero
            ? PreciseClock.ticks(forSeconds: config.timers.workDuration.totalSeconds) : nil
        let limit: Int? = config.timers.clickLimitEnabled ? max(1, config.timers.clickLimit) : nil

        var performed = 0
        var lastPublishTicks: UInt64 = 0
        let publishEvery = PreciseClock.ticks(forSeconds: 0.1)
        var wasPaused = false

        while !token.isSet {
            if let limit, performed >= limit { break }
            if let d = durationTicks, PreciseClock.now() &- startTicks >= d { break }

            let deadline = scheduler.nextDeadline()
            if let d = durationTicks, deadline &- startTicks >= d {
                PreciseClock.sleep(until: startTicks &+ d, cancel: token)
                break
            }
            guard PreciseClock.sleep(until: deadline, cancel: token) else { break }

            let clicked = performOnce(config, cancel: token)
            if clicked {
                performed += 1
                if wasPaused {
                    wasPaused = false
                    DispatchQueue.main.async { [weak self] in self?.pausedOutsideArea = false }
                }
                let now = PreciseClock.now()
                if now &- lastPublishTicks > publishEvery || config.schedule.clicksPerSecond < 20 {
                    lastPublishTicks = now
                    let count = performed
                    DispatchQueue.main.async { [weak self] in self?.clicksPerformed = count }
                }
            } else if !wasPaused {
                wasPaused = true
                DispatchQueue.main.async { [weak self] in self?.pausedOutsideArea = true }
            }
        }

        let finalCount = performed
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.clicksPerformed = finalCount
            if !token.isSet { // finished on its own (limit / duration)
                self.stop()
            }
        }
    }

    /// Performs one scheduled action. Returns `false` when skipped because the cursor is outside the area.
    private func performOnce(_ config: ClickerConfig, cancel: AtomicFlag) -> Bool {
        let current = EventSynthesizer.cursorPosition()
        var target = current
        let loc = config.location

        switch loc.mode {
        case .cursor:
            if loc.randomMove {
                target = EventSynthesizer.randomPoint(in: EventSynthesizer.displayBounds(containing: current))
            }
        case .fixedPoint:
            target = loc.fixedPoint ?? current
        case .area:
            if let area = loc.area, area.width > 0, area.height > 0 {
                if loc.randomMove {
                    target = EventSynthesizer.randomPoint(in: area)
                } else if !area.contains(current) && loc.pauseWhenCursorLeavesArea {
                    return false
                }
            } else if loc.randomMove {
                target = EventSynthesizer.randomPoint(in: EventSynthesizer.displayBounds(containing: current))
            }
        }

        if target != current || config.action == .moveOnly {
            EventSynthesizer.move(to: target)
        }

        let hold = max(0, config.holdDurationMs) / 1000
        switch config.action {
        case .left:
            EventSynthesizer.click(button: .left, at: target, count: config.clickCount.rawValue, hold: hold, cancel: cancel)
        case .right:
            EventSynthesizer.click(button: .right, at: target, count: config.clickCount.rawValue, hold: hold, cancel: cancel)
        case .middle:
            EventSynthesizer.click(button: .middle, at: target, count: config.clickCount.rawValue, hold: hold, cancel: cancel)
        case .both:
            EventSynthesizer.clickBoth(at: target, hold: hold, cancel: cancel)
        case .moveOnly:
            break
        case .scroll:
            let v = config.scroll.direction.vector
            let amount = Int32(max(1, config.scroll.amount))
            EventSynthesizer.scroll(dx: v.dx * amount, dy: v.dy * amount, at: nil)
        }
        return true
    }

    // MARK: Daily repeat

    /// (Re)arms the daily repeat timer from the current configuration.
    func scheduleDailyRepeat(_ timers: TimerConfig) {
        dailyTimer?.invalidate()
        dailyTimer = nil
        guard timers.dailyRepeatEnabled else { nextDailyRun = nil; return }
        let next = timers.dailyRepeatTime.nextOccurrence()
        nextDailyRun = next
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            if !self.isActive { self.start(config: self.configProvider()) }
            self.scheduleDailyRepeat(self.configProvider().timers)
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        dailyTimer = timer
    }
}
