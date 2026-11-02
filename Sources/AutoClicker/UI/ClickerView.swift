import SwiftUI

struct ClickerView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var clicker: ClickerEngine

    private var config: Binding<ClickerConfig> { $state.settings.clicker }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                actionSection
                scheduleSection
                randomSection
                locationSection
                timerSection
            }
            .formStyle(.grouped)
            .disabled(clicker.isActive)

            Divider()
            controlBar
        }
    }

    // MARK: Sections

    private var actionSection: some View {
        Section("Action") {
            Picker("Click type", selection: config.action) {
                ForEach(ClickAction.allCases) { action in
                    Label(action.label, systemImage: action.symbol).tag(action)
                }
            }

            if config.wrappedValue.action.isClick && config.wrappedValue.action != .both {
                Picker("Clicks per action", selection: config.clickCount) {
                    ForEach(ClickCount.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if config.wrappedValue.action.isClick {
                HStack {
                    Text("Press duration")
                    Spacer()
                    DoubleField(value: config.holdDurationMs, range: 0...10_000, suffix: "ms")
                }
            }

            if config.wrappedValue.action == .scroll {
                Picker("Direction", selection: config.scroll.direction) {
                    ForEach(ScrollDirection.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Amount per scroll")
                    Spacer()
                    IntField(value: config.scroll.amount, range: 1...100)
                    Text("lines").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scheduleSection: some View {
        Section {
            HStack(spacing: 8) {
                IntField(value: config.schedule.clicks, range: 1...999, width: 56)
                Text(config.wrappedValue.action == .scroll ? "scrolls every" : "clicks every")
                IntField(value: config.schedule.intervalValue, range: config.wrappedValue.schedule.intervalUnit.intervalRange, width: 56)
                Picker("", selection: config.schedule.intervalUnit) {
                    ForEach(TimeUnit.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 120)
            }
            .onChange(of: config.wrappedValue.schedule.intervalUnit) { _, unit in
                let r = unit.intervalRange
                config.schedule.intervalValue.wrappedValue = min(max(config.wrappedValue.schedule.intervalValue, r.lowerBound), r.upperBound)
            }

            LabeledContent("Rate") {
                Text(rateDescription).foregroundStyle(.secondary)
            }

            if config.wrappedValue.schedule.intervalUnit == .milliseconds || config.wrappedValue.schedule.intervalUnit == .microseconds {
                Label("Rapid click mode — very high speeds can make macOS lag. Use your shortcut to stop; the per-click floor is 1 ms (max ≈ 99 clicks / 100 ms).",
                      systemImage: "bolt.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("Example: 4 clicks every 7 minutes. Without random mode, 2 clicks per minute fire strictly every 30 seconds.")
        }
    }

    private var rateDescription: String {
        let s = config.wrappedValue.schedule
        let per = max(s.perClickSeconds, ScheduleConfig.minimumPerClickSeconds)
        if per < 1 {
            return String(format: "≈ %.1f per second (one every %@)", 1 / per, per.compactDescription)
        }
        return "one every \(per.compactDescription)"
    }

    private var randomSection: some View {
        Section {
            Toggle("Random schedule mode", isOn: config.random.enabled)
            if config.wrappedValue.random.enabled {
                Toggle("Spread clicks randomly within each interval", isOn: config.random.spreadWithinInterval)
                Text("Add a random delay after every click, combining any of the units below:")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(config.random.components) { $component in
                    HStack(spacing: 8) {
                        Toggle(isOn: $component.enabled) {
                            Text(component.unit.label.capitalized).frame(width: 100, alignment: .leading)
                        }
                        Spacer()
                        IntField(value: $component.min, range: component.unit.randomRange, width: 52)
                        Text("to").foregroundStyle(.secondary)
                        IntField(value: $component.max, range: component.unit.randomRange, width: 52)
                        Text(component.unit.shortLabel).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                    }
                    .opacity(component.enabled ? 1 : 0.55)
                }
                if config.wrappedValue.random.anyComponentEnabled {
                    LabeledContent("Extra delay per click") {
                        Text("0 – \(config.wrappedValue.random.maximumExtraDelay.compactDescription)").foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Random mode")
        } footer: {
            Text("Imitates natural, non-robotic clicking: with random mode on, clicks may happen at any moment inside the interval — e.g. after 7 s, then 25 s…")
        }
    }

    private var locationSection: some View {
        Section {
            Picker("Click location", selection: config.location.mode) {
                ForEach(LocationMode.allCases) { Text($0.label).tag($0) }
            }

            switch config.wrappedValue.location.mode {
            case .cursor:
                EmptyView()
            case .fixedPoint:
                HStack {
                    Text("Point")
                    Spacer()
                    Text(config.wrappedValue.location.fixedPoint?.shortDescription ?? "Not set")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button("Pick…") { pickPoint() }
                }
            case .area:
                HStack {
                    Text("Area")
                    Spacer()
                    Text(config.wrappedValue.location.area?.shortDescription ?? "Not selected")
                        .foregroundStyle(.secondary).monospacedDigit()
                    Button(config.wrappedValue.location.area == nil ? "Select…" : "Edit…") { selectArea() }
                    if config.wrappedValue.location.area != nil {
                        Button("Clear") { config.location.area.wrappedValue = nil }
                    }
                }
            }

            if config.wrappedValue.location.mode != .fixedPoint {
                Toggle(isOn: config.location.randomMove) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Randomly move")
                        Text(config.wrappedValue.location.mode == .area
                             ? "Each click lands on a different random point inside the area."
                             : "Each click lands on a random point of the screen — limit it with an area to avoid opening things by accident.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if config.wrappedValue.location.mode == .area {
                Toggle("Pause while the cursor is outside the area", isOn: config.location.pauseWhenCursorLeavesArea)
                    .disabled(config.wrappedValue.location.randomMove)
                Toggle("Show area outline while running", isOn: config.location.showAreaOverlay)
            }
        } header: {
            Text("Location")
        } footer: {
            if config.wrappedValue.location.mode == .area && !config.wrappedValue.location.randomMove {
                Text("Start with the cursor inside the area. If it leaves, clicking pauses (the icon stays active) and resumes when it returns.")
            }
        }
    }

    private var timerSection: some View {
        Section("Timers") {
            Toggle("Delayed start", isOn: config.timers.delayedStartEnabled)
            if config.wrappedValue.timers.delayedStartEnabled {
                HMSPicker(value: config.timers.delayedStart)
            }

            Toggle("Work duration (stop after)", isOn: config.timers.workDurationEnabled)
            if config.wrappedValue.timers.workDurationEnabled {
                HMSPicker(value: config.timers.workDuration)
            }

            Toggle("Number of clicks before stop", isOn: config.timers.clickLimitEnabled)
            if config.wrappedValue.timers.clickLimitEnabled {
                HStack {
                    Spacer()
                    IntField(value: config.timers.clickLimit, range: 1...100_000_000, width: 110)
                    Text("clicks").foregroundStyle(.secondary)
                }
            }

            Toggle("Daily repeat", isOn: config.timers.dailyRepeatEnabled)
            if config.wrappedValue.timers.dailyRepeatEnabled {
                HStack {
                    Text("Start every day at")
                    Spacer()
                    TimeOfDayPicker(value: config.timers.dailyRepeatTime)
                }
                if let next = clicker.nextDailyRun {
                    Text("Next run: \(next.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Control bar

    private var controlBar: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                statusLine(now: context.date)
            }
            HStack {
                if let hk = state.settings.clickerHotkey {
                    Text("Shortcut: \(hk.displayString)").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No shortcut set — add one in Settings.").font(.caption).foregroundStyle(.orange)
                }
                Spacer()
                if case .waiting = clicker.status {
                    Button("Start now") { clicker.startNow() }
                }
                Button(action: { state.toggleClicker() }) {
                    Label(clicker.isActive ? "Stop" : "Start",
                          systemImage: clicker.isActive ? "stop.fill" : "play.fill")
                        .frame(minWidth: 90)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(clicker.isActive ? .red : .accentColor)
            }
            if let message = clicker.lastMessage {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func statusLine(now: Date) -> some View {
        switch clicker.status {
        case .idle:
            HStack {
                StatusDot(color: .gray, text: "Idle")
                Spacer()
                if clicker.clicksPerformed > 0 {
                    Text("Last run: \(clicker.clicksPerformed.formatted()) clicks").foregroundStyle(.secondary)
                }
            }
        case .waiting(let startAt):
            HStack {
                StatusDot(color: .orange, text: "Starting in \(HMS(totalSeconds: max(0, startAt.timeIntervalSince(now))).formatted)")
                Spacer()
            }
        case .running(let since):
            HStack {
                StatusDot(color: Color(nsColor: IconRenderer.activeColor),
                          text: clicker.pausedOutsideArea ? "Paused — cursor outside area" : "Running")
                Spacer()
                Text(runningDetail(since: since, now: now)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func runningDetail(since: Date, now: Date) -> String {
        let elapsed = HMS(totalSeconds: now.timeIntervalSince(since)).formatted
        var parts = [elapsed, "\(clicker.clicksPerformed.formatted()) clicks"]
        let t = state.settings.clicker.timers
        if t.workDurationEnabled {
            let remaining = max(0, t.workDuration.totalSeconds - now.timeIntervalSince(since))
            parts.append("\(HMS(totalSeconds: remaining).formatted) left")
        }
        if t.clickLimitEnabled { parts.append("limit \(t.clickLimit.formatted())") }
        return parts.joined(separator: "  •  ")
    }

    // MARK: Actions

    private func selectArea() {
        AppDelegate.shared.hideUI()
        SelectionOverlay.selectArea { rect in
            if let rect { state.settings.clicker.location.area = rect }
            AppDelegate.shared.showUI()
        }
    }

    private func pickPoint() {
        AppDelegate.shared.hideUI()
        SelectionOverlay.pickPoint { point in
            if let point { state.settings.clicker.location.fixedPoint = point }
            AppDelegate.shared.showUI()
        }
    }
}
