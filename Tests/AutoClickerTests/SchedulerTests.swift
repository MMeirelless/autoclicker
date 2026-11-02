import XCTest
@testable import AutoClicker

final class SchedulerTests: XCTestCase {
    private func seconds(_ a: UInt64, _ b: UInt64) -> Double {
        PreciseClock.seconds(forTicks: b &- a)
    }

    func testFixedModeFiresImmediatelyThenEvenlySpaced() {
        var schedule = ScheduleConfig()
        schedule.clicks = 4
        schedule.intervalValue = 2
        schedule.intervalUnit = .seconds // 4 clicks every 2 s → one every 0.5 s
        var scheduler = ClickScheduler(schedule: schedule, random: RandomScheduleConfig())
        let now = PreciseClock.now()
        scheduler.begin(at: now)

        let first = scheduler.nextDeadline()
        XCTAssertLessThan(seconds(now, first), 0.01, "first click fires immediately")

        var previous = first
        for _ in 0..<5 {
            let next = scheduler.nextDeadline()
            XCTAssertEqual(seconds(previous, next), 0.5, accuracy: 0.0005)
            previous = next
        }
    }

    func testPerClickFloorIsOneMillisecond() {
        var schedule = ScheduleConfig()
        schedule.clicks = 999
        schedule.intervalValue = 100
        schedule.intervalUnit = .microseconds
        XCTAssertEqual(schedule.perClickSeconds, 100e-6 / 999, accuracy: 1e-12)
        XCTAssertEqual(schedule.clicksPerSecond, 1000, accuracy: 0.001)

        var scheduler = ClickScheduler(schedule: schedule, random: RandomScheduleConfig())
        scheduler.begin(at: PreciseClock.now())
        let a = scheduler.nextDeadline()
        let b = scheduler.nextDeadline()
        XCTAssertGreaterThanOrEqual(seconds(a, b), 0.001 - 1e-6)
    }

    func testRandomSpreadKeepsClicksInsideEachWindow() {
        var schedule = ScheduleConfig()
        schedule.clicks = 5
        schedule.intervalValue = 1
        schedule.intervalUnit = .seconds
        var random = RandomScheduleConfig()
        random.enabled = true
        random.spreadWithinInterval = true
        random.components = random.components.map { var c = $0; c.enabled = false; return c }

        var scheduler = ClickScheduler(schedule: schedule, random: random)
        let start = PreciseClock.now()
        scheduler.begin(at: start)

        for window in 0..<3 {
            var offsets: [Double] = []
            for _ in 0..<5 { offsets.append(seconds(start, scheduler.nextDeadline())) }
            XCTAssertEqual(offsets, offsets.sorted(), "clicks inside a window are chronological")
            for offset in offsets {
                XCTAssertGreaterThanOrEqual(offset, Double(window) - 0.001)
                XCTAssertLessThan(offset, Double(window + 1) + 0.001)
            }
        }
    }

    func testExtraRandomDelayCombinesEnabledUnits() {
        var random = RandomScheduleConfig()
        random.enabled = true
        random.components = [
            RandomComponent(unit: .hours, enabled: false, min: 0, max: 1),
            RandomComponent(unit: .minutes, enabled: true, min: 1, max: 1),
            RandomComponent(unit: .seconds, enabled: true, min: 2, max: 4),
            RandomComponent(unit: .milliseconds, enabled: true, min: 0, max: 500),
            RandomComponent(unit: .microseconds, enabled: true, min: 100, max: 100),
        ]
        XCTAssertTrue(random.anyComponentEnabled)
        XCTAssertEqual(random.maximumExtraDelay, 60 + 4 + 0.5 + 0.0001, accuracy: 1e-9)
        for _ in 0..<200 {
            let d = random.sampleExtraDelay()
            XCTAssertGreaterThanOrEqual(d, 60 + 2 + 0.0001 - 1e-9)
            XCTAssertLessThanOrEqual(d, 60 + 4 + 0.5 + 0.0001 + 1e-9)
        }
        random.enabled = false
        XCTAssertEqual(random.sampleExtraDelay(), 0)
    }

    func testExtraDelayIsAddedToFixedSchedule() {
        var schedule = ScheduleConfig()
        schedule.clicks = 1
        schedule.intervalValue = 10
        schedule.intervalUnit = .milliseconds
        var random = RandomScheduleConfig()
        random.enabled = true
        random.spreadWithinInterval = false
        random.components = [RandomComponent(unit: .milliseconds, enabled: true, min: 5, max: 20)]

        var scheduler = ClickScheduler(schedule: schedule, random: random)
        scheduler.begin(at: PreciseClock.now())
        var previous = scheduler.nextDeadline()
        for _ in 0..<50 {
            let next = scheduler.nextDeadline()
            let gap = seconds(previous, next)
            XCTAssertGreaterThanOrEqual(gap, 0.015 - 1e-6)
            XCTAssertLessThanOrEqual(gap, 0.030 + 1e-6)
            previous = next
        }
    }
}
