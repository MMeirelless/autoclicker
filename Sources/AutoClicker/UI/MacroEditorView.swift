import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Editable copy of a macro plus editor-only state.
final class MacroEditorModel: ObservableObject {
    @Published var draft: Macro
    let original: Macro
    let isNew: Bool

    init(macro: Macro, isNew: Bool) {
        draft = macro
        original = macro
        self.isNew = isNew
    }

    var isDirty: Bool { draft != original }
}

/// Standalone window hosting the macro editor (one per macro).
final class MacroEditorWindow: NSObject, NSWindowDelegate {
    private static var open: [UUID: MacroEditorWindow] = [:]

    private let window: NSWindow
    private let model: MacroEditorModel
    private let state: AppState

    static func open(macro: Macro, isNew: Bool, state: AppState) {
        AppDelegate.shared.closePopover()
        if let existing = open[macro.id] {
            existing.window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let editor = MacroEditorWindow(macro: macro, isNew: isNew, state: state)
        open[macro.id] = editor
        editor.show()
    }

    private init(macro: Macro, isNew: Bool, state: AppState) {
        self.state = state
        model = MacroEditorModel(macro: macro, isNew: isNew)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = isNew ? "New Macro" : "Edit Macro — \(macro.name)"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 560, height: 520)
        window.delegate = self
        window.center()
        let root = MacroEditorView(model: model, onSave: { [weak self] in self?.save() },
                                   onCancel: { [weak self] in self?.close() },
                                   hideWindow: { [weak self] in self?.window.orderOut(nil) },
                                   showWindow: { [weak self] in self?.show() })
            .environmentObject(state)
            .environmentObject(state.recorder)
        window.contentView = NSHostingView(rootView: root)
    }

    private func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func save() {
        state.upsert(model.draft)
        close()
    }

    private func close() {
        MacroEditorWindow.open[model.draft.id] = nil
        window.delegate = nil
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.isDirty || model.isNew else {
            MacroEditorWindow.open[model.draft.id] = nil
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(model.draft.name)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don't Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            state.upsert(model.draft)
            MacroEditorWindow.open[model.draft.id] = nil
            return true
        case .alertThirdButtonReturn:
            MacroEditorWindow.open[model.draft.id] = nil
            return true
        default:
            return false
        }
    }
}

struct MacroEditorView: View {
    @ObservedObject var model: MacroEditorModel
    @EnvironmentObject var state: AppState
    @EnvironmentObject var recorder: MacroRecorder
    let onSave: () -> Void
    let onCancel: () -> Void
    let hideWindow: () -> Void
    let showWindow: () -> Void

    @State private var editingStep: MacroStep?
    @State private var addingStep = false
    @State private var showSettings = true
    @State private var selection: Set<UUID> = []

    private var draft: Binding<Macro> { $model.draft }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: draft.name)
                    HotkeyRecorderView(title: "Shortcut", combo: draft.hotkey,
                                       taken: state.assignedHotkeys(excluding: model.original.hotkey))
                }

                DisclosureGroup("Logic & timing", isExpanded: $showSettings) {
                    HStack {
                        Text("Prestart delay")
                        Spacer()
                        DoubleField(value: draft.prestartDelay, range: 0...86_400, suffix: "s")
                    }
                    HStack {
                        Text("Key press duration")
                        Spacer()
                        DoubleField(value: msBinding(draft.keyPressDuration), range: 0...10_000, suffix: "ms")
                    }
                    Picker("Time intervals", selection: draft.intervalMode) {
                        ForEach(IntervalMode.allCases) { Text($0.label).tag($0) }
                    }
                    if model.draft.intervalMode == .recorded {
                        HStack {
                            Text("Playback speed")
                            Slider(value: draft.speedMultiplier, in: 0.25...4, step: 0.25)
                            Text(String(format: "%.2f×", model.draft.speedMultiplier)).monospacedDigit().frame(width: 48)
                        }
                    } else {
                        HStack {
                            Text("Interval between steps")
                            Spacer()
                            DoubleField(value: draft.fixedInterval, range: 0...86_400, suffix: "s")
                        }
                    }
                    Toggle("Loop", isOn: draft.loop.enabled)
                    if model.draft.loop.enabled {
                        Picker("", selection: draft.loop.infinite) {
                            Text("Repeat until stopped").tag(true)
                            Text("Repeat a number of times").tag(false)
                        }
                        .pickerStyle(.radioGroup).labelsHidden()
                        if !model.draft.loop.infinite {
                            HStack { Spacer(); IntField(label: "Repeat", value: draft.loop.count, range: 1...1_000_000) }
                        }
                    }
                    Toggle("Delayed start", isOn: draft.timer.delayedStartEnabled)
                    if model.draft.timer.delayedStartEnabled {
                        HMSPicker(value: draft.timer.delayedStart)
                    }
                    Toggle("Daily repeat", isOn: draft.timer.dailyRepeatEnabled)
                    if model.draft.timer.dailyRepeatEnabled {
                        HStack { Text("Run every day at"); Spacer(); TimeOfDayPicker(value: draft.timer.dailyRepeatTime) }
                    }
                    Toggle(isOn: draft.rememberCursorPosition) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Remember mouse cursor position")
                            Text("Affects only steps recorded after changing it. The target icon on each step decides whether the saved point or the current cursor position is used.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: showSettings ? 420 : 150)

            Divider()
            stepsHeader
            stepsList
            Divider()
            bottomBar
        }
        .sheet(item: $editingStep) { step in
            StepEditorView(step: step, isNew: false, hideWindow: hideWindow, showWindow: showWindow) { updated in
                if let i = model.draft.steps.firstIndex(where: { $0.id == updated.id }) {
                    model.draft.steps[i] = updated
                }
            }
        }
        .sheet(isPresented: $addingStep) {
            StepEditorView(step: MacroStep(kind: .click(button: .left, count: 1), delayBefore: 0.5),
                           isNew: true, hideWindow: hideWindow, showWindow: showWindow) { newStep in
                model.draft.steps.append(newStep)
            }
        }
    }

    private var stepsHeader: some View {
        HStack {
            Text("Steps").font(.headline)
            Text("\(model.draft.steps.count)").foregroundStyle(.secondary)
            Spacer()
            Button {
                startRecording()
            } label: {
                Label(model.draft.steps.isEmpty ? "Record" : "Resume recording", systemImage: "record.circle")
                    .foregroundStyle(.red)
            }
            .disabled(recorder.isActive)
            Button { addingStep = true } label: { Label("Add Step", systemImage: "plus") }
            Menu {
                Button("Move Up") { move(by: -1) }.disabled(selection.isEmpty)
                Button("Move Down") { move(by: 1) }.disabled(selection.isEmpty)
                Divider()
                Button("Use saved position for selected") { setUsePosition(true) }.disabled(selection.isEmpty)
                Button("Use current cursor for selected") { setUsePosition(false) }.disabled(selection.isEmpty)
                Divider()
                Button("Delete Selected", role: .destructive) { deleteSelected() }.disabled(selection.isEmpty)
                Button("Delete All Steps", role: .destructive) { model.draft.steps.removeAll() }.disabled(model.draft.steps.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .frame(width: 44)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var stepsList: some View {
        Group {
            if model.draft.steps.isEmpty {
                VStack(spacing: 6) {
                    Text("No steps yet").foregroundStyle(.secondary)
                    Text("Press Record to capture clicks, keys, scrolls and drags, or Add Step to build the macro by hand.")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selection) {
                    ForEach(Array(model.draft.steps.enumerated()), id: \.element.id) { index, step in
                        StepRow(index: index + 1, step: binding(for: step.id)) {
                            editingStep = step
                        } onDelete: {
                            model.draft.steps.removeAll { $0.id == step.id }
                        }
                        .tag(step.id)
                    }
                    .onMove { from, to in model.draft.steps.move(fromOffsets: from, toOffset: to) }
                    .onDelete { offsets in model.draft.steps.remove(atOffsets: offsets) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            if let error = recorder.error {
                Text(error).font(.caption).foregroundStyle(.red)
            } else {
                Text("≈ \(model.draft.estimatedDuration.compactDescription) per run")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
            Button("Save") { onSave() }
                .keyboardShortcut("s", modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(12)
    }

    // MARK: Helpers

    private func binding(for id: UUID) -> Binding<MacroStep> {
        Binding(
            get: { model.draft.steps.first { $0.id == id } ?? MacroStep(kind: .wait(seconds: 0)) },
            set: { new in
                if let i = model.draft.steps.firstIndex(where: { $0.id == id }) { model.draft.steps[i] = new }
            })
    }

    private func msBinding(_ seconds: Binding<TimeInterval>) -> Binding<Double> {
        Binding(get: { seconds.wrappedValue * 1000 }, set: { seconds.wrappedValue = $0 / 1000 })
    }

    private func startRecording() {
        hideWindow()
        AppDelegate.shared.hideUI()
        recorder.start(rememberCursorPosition: model.draft.rememberCursorPosition) { steps in
            if let steps { model.draft.steps.append(contentsOf: steps) }
            model.draft.rememberCursorPosition = recorder.rememberCursorPosition
            showWindow()
        }
        if recorder.error != nil { showWindow() }
    }

    private func move(by delta: Int) {
        let ids = selection
        var steps = model.draft.steps
        let indices = steps.indices.filter { ids.contains(steps[$0].id) }
        let ordered = delta < 0 ? indices : indices.reversed()
        for i in ordered {
            let j = i + delta
            guard steps.indices.contains(j), !ids.contains(steps[j].id) else { continue }
            steps.swapAt(i, j)
        }
        model.draft.steps = steps
    }

    private func setUsePosition(_ use: Bool) {
        for i in model.draft.steps.indices where selection.contains(model.draft.steps[i].id) {
            if model.draft.steps[i].position != nil { model.draft.steps[i].usePosition = use }
        }
    }

    private func deleteSelected() {
        model.draft.steps.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
}

struct StepRow: View {
    let index: Int
    @Binding var step: MacroStep
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(index)").foregroundStyle(.secondary).monospacedDigit().frame(width: 28, alignment: .trailing)
            Image(systemName: step.kind.symbol).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.kind.label)
                HStack(spacing: 6) {
                    Text("after \(step.delayBefore.compactDescription)")
                    if let p = step.position {
                        Text("•")
                        Text(step.usePosition ? "at \(p.shortDescription)" : "at cursor (saved \(p.shortDescription))")
                    }
                    if case .drag(_, let to) = step.kind {
                        Text("→ \(to.shortDescription)")
                    }
                    if let hold = step.holdDuration {
                        Text("•")
                        Text("hold \(hold.compactDescription)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if step.position != nil {
                Button {
                    step.usePosition.toggle()
                } label: {
                    Image(systemName: step.usePosition ? "scope" : "cursorarrow")
                        .foregroundStyle(step.usePosition ? Color.accentColor : Color.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help(step.usePosition ? "Uses the saved point (click to use the current cursor position instead)"
                                        : "Uses the current cursor position (click to use the saved point)")
            }
            Button(action: onEdit) { Image(systemName: "pencil").frame(width: 22, height: 22) }
                .buttonStyle(.borderless).help("Edit step")
            Button(action: onDelete) { Image(systemName: "trash").frame(width: 22, height: 22) }
                .buttonStyle(.borderless).help("Delete step")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Step editor sheet

enum StepKindChoice: String, CaseIterable, Identifiable {
    case click, move, drag, scroll, key, wait
    var id: String { rawValue }
    var label: String {
        switch self {
        case .click: return "Click"
        case .move: return "Move cursor"
        case .drag: return "Drag & drop"
        case .scroll: return "Scroll"
        case .key: return "Key press"
        case .wait: return "Wait"
        }
    }
}

struct StepEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let isNew: Bool
    let hideWindow: () -> Void
    let showWindow: () -> Void
    let onDone: (MacroStep) -> Void

    @State private var id: UUID
    @State private var kind: StepKindChoice
    @State private var button: MouseButton = .left
    @State private var clickCount: Int = 1
    @State private var dragTo: CGPoint = .zero
    @State private var scrollDX: Int = 0
    @State private var scrollDY: Int = -3
    @State private var keyCode: UInt32 = UInt32(kVK_Return)
    @State private var keyModifiers: UInt = 0
    @State private var waitSeconds: Double = 1
    @State private var hasPosition: Bool
    @State private var position: CGPoint
    @State private var usePosition: Bool
    @State private var delayBefore: Double
    @State private var overrideHold: Bool
    @State private var holdMs: Double

    init(step: MacroStep, isNew: Bool, hideWindow: @escaping () -> Void, showWindow: @escaping () -> Void,
         onDone: @escaping (MacroStep) -> Void) {
        self.isNew = isNew
        self.hideWindow = hideWindow
        self.showWindow = showWindow
        self.onDone = onDone
        _id = State(initialValue: step.id)
        _hasPosition = State(initialValue: step.position != nil)
        _position = State(initialValue: step.position ?? EventSynthesizer.cursorPosition())
        _usePosition = State(initialValue: step.usePosition)
        _delayBefore = State(initialValue: step.delayBefore)
        _overrideHold = State(initialValue: step.holdDuration != nil)
        _holdMs = State(initialValue: (step.holdDuration ?? 0.02) * 1000)
        switch step.kind {
        case .click(let b, let c):
            _kind = State(initialValue: .click); _button = State(initialValue: b); _clickCount = State(initialValue: c)
        case .move:
            _kind = State(initialValue: .move)
        case .drag(let b, let to):
            _kind = State(initialValue: .drag); _button = State(initialValue: b); _dragTo = State(initialValue: to)
        case .scroll(let dx, let dy):
            _kind = State(initialValue: .scroll); _scrollDX = State(initialValue: Int(dx)); _scrollDY = State(initialValue: Int(dy))
        case .key(let code, let mods):
            _kind = State(initialValue: .key); _keyCode = State(initialValue: code); _keyModifiers = State(initialValue: mods)
        case .wait(let s):
            _kind = State(initialValue: .wait); _waitSeconds = State(initialValue: s)
        }
    }

    private var kindUsesPosition: Bool { kind == .click || kind == .move || kind == .drag || kind == .scroll }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Action", selection: $kind) {
                        ForEach(StepKindChoice.allCases) { Text($0.label).tag($0) }
                    }
                    .disabled(!isNew)

                    switch kind {
                    case .click:
                        Picker("Button", selection: $button) { ForEach(MouseButton.allCases) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented)
                        Picker("Clicks", selection: $clickCount) {
                            Text("Single").tag(1); Text("Double").tag(2); Text("Triple").tag(3)
                        }
                        .pickerStyle(.segmented)
                    case .drag:
                        Picker("Button", selection: $button) { ForEach(MouseButton.allCases) { Text($0.label).tag($0) } }
                            .pickerStyle(.segmented)
                        pointEditor(title: "Drop at", point: $dragTo)
                    case .scroll:
                        HStack {
                            Text("Vertical (+ up / − down)")
                            Spacer()
                            IntField(value: $scrollDY, range: -1000...1000)
                        }
                        HStack {
                            Text("Horizontal (+ left / − right)")
                            Spacer()
                            IntField(value: $scrollDX, range: -1000...1000)
                        }
                    case .key:
                        HStack {
                            Text("Key")
                            Spacer()
                            KeyCaptureField(keyCode: $keyCode, modifiers: $keyModifiers)
                        }
                    case .wait:
                        HStack {
                            Text("Duration")
                            Spacer()
                            DoubleField(value: $waitSeconds, range: 0...86_400, suffix: "s")
                        }
                    case .move:
                        EmptyView()
                    }
                }

                if kindUsesPosition {
                    Section("Position") {
                        Toggle("Use a saved point (target)", isOn: $usePosition)
                        pointEditor(title: kind == .drag ? "Start at" : "Point", point: $position)
                            .disabled(!usePosition)
                        if !usePosition {
                            Text("The step runs at wherever the cursor is during playback.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Timing") {
                    HStack {
                        Text("Delay before this step")
                        Spacer()
                        DoubleField(value: $delayBefore, range: 0...86_400, suffix: "s")
                    }
                    if kind == .click || kind == .key || kind == .drag {
                        Toggle("Override press duration", isOn: $overrideHold)
                        if overrideHold {
                            HStack { Spacer(); DoubleField(value: $holdMs, range: 0...10_000, suffix: "ms") }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Done") {
                    onDone(buildStep())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
    }

    private func pointEditor(title: String, point: Binding<CGPoint>) -> some View {
        HStack {
            Text(title)
            Spacer()
            DoubleField(label: "x", value: Binding(get: { Double(point.wrappedValue.x) }, set: { point.wrappedValue.x = $0 }),
                        range: -100_000...100_000, width: 64)
            DoubleField(label: "y", value: Binding(get: { Double(point.wrappedValue.y) }, set: { point.wrappedValue.y = $0 }),
                        range: -100_000...100_000, width: 64)
            Button("Pick…") {
                hideWindow()
                AppDelegate.shared.hideUI()
                SelectionOverlay.pickPoint { picked in
                    if let picked { point.wrappedValue = picked }
                    showWindow()
                }
            }
        }
    }

    private func buildStep() -> MacroStep {
        let stepKind: MacroStepKind
        switch kind {
        case .click: stepKind = .click(button: button, count: clickCount)
        case .move: stepKind = .move
        case .drag: stepKind = .drag(button: button, to: dragTo)
        case .scroll: stepKind = .scroll(dx: Int32(scrollDX), dy: Int32(scrollDY))
        case .key: stepKind = .key(keyCode: keyCode, modifiers: keyModifiers)
        case .wait: stepKind = .wait(seconds: waitSeconds)
        }
        var step = MacroStep(id: id, kind: stepKind, delayBefore: delayBefore)
        if kindUsesPosition {
            step.position = position
            step.usePosition = usePosition
        }
        step.holdDuration = overrideHold ? holdMs / 1000 : nil
        return step
    }
}
