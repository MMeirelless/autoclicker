import XCTest
import Carbon.HIToolbox
@testable import AutoClicker

final class ModelTests: XCTestCase {
    func testKeyComboDisplayAndCarbonModifiers() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_0), modifiers: [.control, .shift])
        XCTAssertEqual(combo.displayString, "⌃⇧0")
        XCTAssertEqual(combo.carbonModifiers, UInt32(controlKey | shiftKey))
        XCTAssertTrue(combo.isValidGlobalHotkey)
        XCTAssertFalse(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: []).isValidGlobalHotkey)
        XCTAssertTrue(KeyCombo(keyCode: UInt32(kVK_F5), modifiers: []).isValidGlobalHotkey)
        XCTAssertEqual(KeyCombo.defaultStopAllMacros.displayString, "⌃0")
    }

    func testSystemShortcutConflictAndSuggestion() {
        let spotlight = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: [.command])
        XCTAssertTrue(HotkeyManager.conflictsWithSystem(spotlight))
        let taken = [KeyCombo.defaultClicker, KeyCombo.defaultStopAllMacros]
        let suggestion = HotkeyManager.suggestFreeCombo(avoiding: taken)
        XCTAssertNotNil(suggestion)
        XCTAssertFalse(taken.contains(suggestion!))
        XCTAssertFalse(HotkeyManager.conflictsWithSystem(suggestion!))
    }

    /// ISO-8601 drops sub-second precision, so round-trip tests use whole-second timestamps.
    private var wholeSecond: Date { Date(timeIntervalSince1970: 1_700_000_000) }

    func testMacroSharingRoundTripThroughLinkAndMessage() throws {
        var macro = Macro()
        macro.createdAt = wholeSecond
        macro.modifiedAt = wholeSecond
        macro.name = "Login flow"
        macro.loop = LoopConfig(enabled: true, infinite: false, count: 3)
        macro.hotkey = KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: [.control])
        macro.steps = [
            MacroStep(kind: .click(button: .left, count: 2), delayBefore: 0.25, position: CGPoint(x: 100, y: 200), usePosition: true),
            MacroStep(kind: .drag(button: .left, to: CGPoint(x: 300, y: 400)), delayBefore: 1, position: CGPoint(x: 10, y: 20)),
            MacroStep(kind: .key(keyCode: UInt32(kVK_Return), modifiers: NSEvent.ModifierFlags.command.rawValue), delayBefore: 0.1),
            MacroStep(kind: .scroll(dx: 0, dy: -3), delayBefore: 0.5, position: CGPoint(x: 5, y: 5), usePosition: false),
            MacroStep(kind: .wait(seconds: 2), delayBefore: 0),
            MacroStep(kind: .move, delayBefore: 0.05, position: CGPoint(x: 1, y: 1)),
        ]

        let link = try XCTUnwrap(MacroSharing.link(for: macro))
        XCTAssertEqual(link.scheme, "autoclicker")
        XCTAssertEqual(MacroSharing.decode(url: link), macro)

        let message = MacroSharing.message(for: macro)
        XCTAssertTrue(message.contains("Login flow"))
        XCTAssertEqual(MacroSharing.decode(text: "hey, try this:\n" + message), macro)
        XCTAssertNil(MacroSharing.decode(text: "no link here"))
    }

    func testMacroFileRoundTrip() throws {
        var macro = Macro()
        macro.createdAt = wholeSecond
        macro.modifiedAt = wholeSecond
        macro.name = "File"
        macro.steps = [MacroStep(kind: .click(button: .right, count: 1), delayBefore: 0.3, position: .zero)]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test.\(MacroSharing.fileExtension)")
        try MacroSharing.export(macro, to: url)
        XCTAssertEqual(MacroSharing.decode(url: url), macro)
        try? FileManager.default.removeItem(at: url)
    }

    func testDuplicateGetsFreshIdentityAndNoHotkey() {
        var macro = Macro()
        macro.name = "Orig"
        macro.hotkey = .defaultClicker
        macro.steps = [MacroStep(kind: .wait(seconds: 1))]
        let copy = macro.duplicated()
        XCTAssertNotEqual(copy.id, macro.id)
        XCTAssertEqual(copy.name, "Orig copy")
        XCTAssertNil(copy.hotkey)
        XCTAssertNotEqual(copy.steps[0].id, macro.steps[0].id)
        XCTAssertEqual(copy.steps[0].kind, macro.steps[0].kind)
    }

    func testEstimatedDurationHonoursIntervalMode() {
        var macro = Macro()
        macro.prestartDelay = 1
        macro.steps = [MacroStep(kind: .wait(seconds: 2), delayBefore: 1), MacroStep(kind: .move, delayBefore: 3)]
        macro.intervalMode = .recorded
        macro.speedMultiplier = 2
        XCTAssertEqual(macro.estimatedDuration, 1 + 0.5 + 2 + 1.5, accuracy: 1e-9)
        macro.intervalMode = .fixed
        macro.fixedInterval = 0.25
        XCTAssertEqual(macro.estimatedDuration, 1 + 0.25 + 2 + 0.25, accuracy: 1e-9)
    }

    func testTimeOfDayNextOccurrenceIsInTheFuture() {
        let now = Date()
        let t = TimeOfDay(hour: 7, minute: 30)
        let next = t.nextOccurrence(after: now)
        XCTAssertGreaterThan(next, now)
        XCTAssertLessThanOrEqual(next.timeIntervalSince(now), 86_400 + 3_600) // allow a DST shift
        let comps = Calendar.current.dateComponents([.hour, .minute], from: next)
        XCTAssertEqual(comps.hour, 7)
        XCTAssertEqual(comps.minute, 30)
    }

    func testHMSFormattingAndConversion() {
        XCTAssertEqual(HMS(hours: 1, minutes: 5, seconds: 9).formatted, "1h 05m 09s")
        XCTAssertEqual(HMS(minutes: 8).formatted, "8m 00s")
        XCTAssertEqual(HMS(seconds: 5).formatted, "5s")
        XCTAssertEqual(HMS(totalSeconds: 3725), HMS(hours: 1, minutes: 2, seconds: 5))
        XCTAssertEqual((0.0015).compactDescription, "1.5 ms")
        XCTAssertEqual((0.00025).compactDescription, "250 µs")
    }

    func testIconVisibilityMapping() {
        XCTAssertEqual(IconVisibility.from(dock: true, menuBar: true), .both)
        XCTAssertEqual(IconVisibility.from(dock: false, menuBar: true), .menuBarOnly)
        XCTAssertEqual(IconVisibility.from(dock: true, menuBar: false), .dockOnly)
        XCTAssertEqual(IconVisibility.from(dock: false, menuBar: false), .hidden)
    }

    func testSettingsRoundTripThroughJSON() throws {
        var settings = AppSettings()
        settings.clicker.action = .scroll
        settings.clicker.random.enabled = true
        settings.clicker.location.area = CGRect(x: 1, y: 2, width: 3, height: 4)
        settings.clicker.timers.dailyRepeatEnabled = true
        settings.iconStyle = .sunset
        let data = try Store.encoder.encode(settings)
        XCTAssertEqual(try Store.decoder.decode(AppSettings.self, from: data), settings)
    }
}

final class HotkeyProbeTests: XCTestCase {
    func testProbeDoesNotKeepTheCombinationAndHeldCombosStayRegistrable() {
        let combo = KeyCombo(keyCode: UInt32(kVK_F18), modifiers: [.control, .option, .shift, .command])
        let manager = HotkeyManager.shared
        XCTAssertTrue(manager.canRegister(combo))
        XCTAssertFalse(manager.isRegistered(combo), "probing must release the combination")
        guard let id = manager.register(combo, handler: {}) else {
            return XCTFail("registration failed: \(manager.lastError ?? "unknown")")
        }
        XCTAssertTrue(manager.isRegistered(combo))
        XCTAssertTrue(manager.canRegister(combo), "a combination we already hold is still ours")
        manager.unregister(id)
        XCTAssertFalse(manager.isRegistered(combo))
        XCTAssertFalse(manager.canRegister(KeyCombo(keyCode: UInt32(kVK_ANSI_A), modifiers: [])))
    }
}
