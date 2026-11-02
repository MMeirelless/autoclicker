# AutoClicker for macOS

A native, open-source menu-bar autoclicker and macro recorder for macOS (Swift / SwiftUI, no
dependencies). It reproduces the full feature set of commercial clickers such as TapBot — with no
time limits, no premium tier — and adds a few extras (middle click, double/triple click, scroll,
per-unit random delays down to microseconds).

## Features

### Clicker
- **Actions:** left, right, middle, both buttons, cursor movement only, or scroll (up/down/left/right, N lines).
- **Single / double / triple** clicks and an adjustable press (hold) duration.
- **Schedule:** *N clicks every V unit* — microseconds, milliseconds (rapid click mode), seconds, minutes
  or hours (e.g. "4 clicks every 7 minutes"). A 1 ms per-click floor keeps macOS responsive
  (≈ 99 clicks / 100 ms).
- **Random schedule mode:** clicks fall at random moments inside each interval, plus an extra random delay
  built from any combination of **hours, minutes, seconds, milliseconds and microseconds** ranges.
- **Location:** current cursor position, a fixed point, or a **selected screen area** (drag to select on any
  display). **Randomly move** lands every click on a different point of the area (or of the whole screen).
  Without random move, clicking pauses while the cursor is outside the area and resumes when it returns.
  An optional dashed outline shows the area while running.
- **Timers:** delayed start (h/m/s), work duration, *number of clicks before stop*, and daily repeat at a
  chosen time.
- Global **start/stop shortcut** (default ⌃1) so a fast clicker can always be stopped.
- Menu-bar icon turns **turquoise** while the clicker runs, gray when idle.

### Macros
- **Record** mouse clicks, drag & drop, scrolling, keyboard presses and (optionally) cursor movement.
  Pause / resume / undo-last / stop from a floating panel.
- **Review and edit** every step: reorder, delete, change delays and hold time, or add steps by hand
  (click, move, drag, scroll, key, wait) with an on-screen point picker.
- **Remember mouse cursor position** switch + per-step **target icon**: replay at the saved point or at the
  current cursor position (the saved point is always kept).
- **Prestart delay, key press duration, time intervals** (as recorded with a speed multiplier, or a fixed
  interval between steps).
- **Loop** forever or a set number of times.
- **Delayed start** and **daily repeat** per macro.
- Per-macro **shortcut**; **Stop all macros** shortcut (default ⌃0); several macros can run at once.
- **Duplicate**, **delete**, **share**: a self-contained `autoclicker://` link (works via AirDrop,
  Messages, "Copy Link" message…) or a `.autoclickermacro` file. Import from file or from a link in the
  clipboard. Links never expire — there is no server.

### App
- Lives in the **menu bar**; the window hides when you click outside it.
- **App Icon** section: pick an icon style, show the icon in the Dock, the Menu Bar, both, or neither;
  shortcuts to toggle each. Guide for renaming the app.
- Editable shortcuts everywhere; combinations taken by macOS or by another shortcut are rejected and a
  free *Control + Number* alternative is suggested automatically.
- Launch at login, settings/macros stored as JSON in `~/Library/Application Support/AutoClicker/`.

## Building

Requirements: macOS 14+, Xcode 15+ (Swift 5.10 toolchain or newer).

```sh
make cert       # once: local signing certificate, so rebuilds keep the Accessibility grant
make install    # builds build/AutoClicker.app, quits any running copy, installs to /Applications, launches
make run        # builds and launches build/AutoClicker.app instead (development)
swift test      # unit tests (scheduler, sharing, models, hotkeys)
```

`Package.swift` can also be opened directly in Xcode. Only one copy of the app runs at a time: launching
a second one (say from `build/` while `/Applications` is running) just brings the running copy forward.

### Signing

macOS ties the Accessibility grant to the app's **code signature**. An ad-hoc signature changes with every
rebuild, so the app would stay listed as allowed while the permission silently stops working. `make cert`
creates a self-signed certificate in a private keychain
(`~/Library/Application Support/AutoClicker/signing/`, nothing is added to the login keychain or to the
trust settings) and `make app` / `make install` sign with it automatically; the signature then stays the
same across builds. A real identity can be used instead: `CODESIGN_IDENTITY="Developer ID Application: …"
make install`, and any Apple Development identity in the default keychains is picked up on its own.

## Permissions

| Permission | Needed for | Where |
|---|---|---|
| **Accessibility** | posting clicks, moves, scrolls and keys | System Settings → Privacy & Security → Accessibility (called *Device Control and Data Access* on newer macOS) |
| **Input Monitoring** | recording keyboard presses in macros | System Settings → Privacy & Security → Input Monitoring |

**Listed and enabled, but the app still says the permission is missing?** The grant belongs to an older
build. Click **Reset & re-request…** in the app's banner (or in Settings → Permissions): it runs
`tccutil reset Accessibility com.mmeirelless.autoclicker`, shows the system prompt again, and the app
is registered afresh. Removing the app from the list with “−” and adding it again does the same. Use
`make cert` so this only happens once.

## Troubleshooting

- **The clicker stops quickly or doesn't click** — check the permissions above, a delayed-start timer,
  "number of clicks before stop", or a click area the cursor has left.
- **My Mac lags at very high speeds** — press the stop shortcut; use a lower speed (the app enforces a 1 ms
  floor per click, but macOS still has to process every event).
- **The menu-bar icon is missing** — macOS hides menu-bar items that don't fit. Free some space in the menu
  bar, or just relaunch the app: the UI opens in a window whenever the icon is off-screen.
- **I can't set the shortcut I want** — macOS reserves it (Spotlight, screenshots, Mission Control…) or
  another app already holds it system-wide (another autoclicker such as TapBot, for instance). The app
  tells you which, proposes a free *Control + Number* combination, and a **Retry** button re-registers
  the shortcuts once the other app releases them.

## Layout

```
Sources/AutoClicker
├── App/        main.swift, AppDelegate (status item, popover/window), AppState (settings, macros, hotkeys)
├── Models/     ClickerConfig, Macro, KeyCombo, AppSettings, time units
├── Engine/     PreciseClock, EventSynthesizer (CGEvent), ClickerEngine + ClickScheduler,
│               MacroPlayer, MacroRecorder (event tap), HotkeyManager (Carbon), MacroSharing, Permissions
├── UI/         SwiftUI views: Clicker, Macros (list, editor, step editor), App Icon, Settings,
│               overlays (area selection, point picker, running outline), icon renderer
└── Persistence/ JSON store
```

## License

MIT — see [LICENSE](LICENSE).
