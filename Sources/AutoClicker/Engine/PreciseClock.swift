import Darwin
import os

/// Thread-safe boolean used as a cancellation token by the engine threads.
final class AtomicFlag {
    private let lock = OSAllocatedUnfairLock(initialState: false)
    var isSet: Bool { lock.withLock { $0 } }
    func set() { lock.withLock { $0 = true } }
    func reset() { lock.withLock { $0 = false } }
}

/// High-resolution monotonic clock based on `mach_absolute_time`, used for sub-millisecond
/// click scheduling (up to 99 clicks per 100 ms).
enum PreciseClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    static func now() -> UInt64 { mach_absolute_time() }

    static func ticks(forSeconds seconds: Double) -> UInt64 {
        guard seconds > 0, seconds.isFinite else { return 0 }
        return UInt64(seconds * 1e9 * Double(timebase.denom) / Double(timebase.numer))
    }

    static func seconds(forTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    /// Sleeps until `deadline`, waking every 50 ms to honour cancellation.
    /// - Returns: `true` when the deadline was reached, `false` when cancelled.
    @discardableResult
    static func sleep(until deadline: UInt64, cancel: AtomicFlag) -> Bool {
        let chunk = ticks(forSeconds: 0.05)
        while true {
            if cancel.isSet { return false }
            let current = now()
            if current >= deadline { return true }
            let remaining = deadline - current
            if remaining > chunk {
                mach_wait_until(current + chunk)
            } else {
                mach_wait_until(deadline)
                return !cancel.isSet
            }
        }
    }

    @discardableResult
    static func sleep(seconds: Double, cancel: AtomicFlag) -> Bool {
        guard seconds > 0 else { return !cancel.isSet }
        return sleep(until: now() + ticks(forSeconds: seconds), cancel: cancel)
    }
}
