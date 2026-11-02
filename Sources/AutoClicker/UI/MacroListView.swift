import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MacroListView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var player: MacroPlayer

    @State private var shareTarget: Macro?
    @State private var importMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    MacroEditorWindow.open(macro: Macro(), isNew: true, state: state)
                } label: {
                    Label("Add New Macro", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Menu {
                    Button("From File…") { importFromFile() }
                    Button("From Link in Clipboard") { importFromClipboard() }
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .frame(width: 110)

                Spacer()

                Button {
                    player.stopAll()
                } label: {
                    Label("Stop All", systemImage: "stop.circle")
                }
                .disabled(!player.isAnythingActive)
                .help("Stop all macros\(state.settings.stopAllMacrosHotkey.map { " (\($0.displayString))" } ?? "")")
            }
            .padding(12)

            Divider()

            if state.macros.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No macros yet").font(.title3)
                    Text("A macro is a sequence of actions — clicks, cursor movement, key presses, drag and drop — that can run once or in a loop. Click “Add New Macro”, then Record.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(state.macros) { macro in
                        MacroRow(macro: macro, shareTarget: $shareTarget)
                    }
                }
                .listStyle(.inset)
            }

            if let message = importMessage ?? player.lastMessage {
                Divider()
                Text(message).font(.caption).foregroundStyle(.secondary).padding(8)
            }
        }
        .popover(item: $shareTarget) { macro in
            MacroShareView(macro: macro)
        }
    }

    private func importFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: MacroSharing.fileExtension) ?? .json, .json]
        panel.allowsMultipleSelection = true
        AppDelegate.shared.hideUI()
        let response = panel.runModal()
        AppDelegate.shared.showUI()
        guard response == .OK else { return }
        var imported = 0
        for url in panel.urls {
            if let macro = MacroSharing.decode(url: url) {
                state.importShared(macro)
                imported += 1
            }
        }
        importMessage = imported > 0 ? "Imported \(imported) macro\(imported == 1 ? "" : "s")." : "No valid macro found in the selected file."
    }

    private func importFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            importMessage = "Clipboard is empty."
            return
        }
        if let macro = MacroSharing.decode(text: text) {
            state.importShared(macro)
            importMessage = "Imported “\(macro.name)”."
        } else {
            importMessage = "No autoclicker:// link found in the clipboard."
        }
    }
}

struct MacroRow: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var player: MacroPlayer
    let macro: Macro
    @Binding var shareTarget: Macro?

    private var isRunning: Bool { player.isRunning(macro.id) }
    private var scheduledAt: Date? { player.scheduled[macro.id] }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                player.toggle(macro)
            } label: {
                Image(systemName: isRunning || scheduledAt != nil ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(isRunning ? Color(nsColor: IconRenderer.activeColor) : (scheduledAt != nil ? .orange : .accentColor))
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Stop" : "Play")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(macro.name).font(.headline)
                    if macro.loop.enabled {
                        Image(systemName: "repeat").foregroundStyle(.secondary)
                            .help(macro.loop.infinite ? "Loops until stopped" : "Loops \(macro.loop.count)×")
                    }
                    if macro.timer.dailyRepeatEnabled {
                        Image(systemName: "calendar").foregroundStyle(.secondary)
                            .help("Daily at \(macro.timer.dailyRepeatTime.formatted)")
                    }
                }
                HStack(spacing: 6) {
                    Text("\(macro.steps.count) step\(macro.steps.count == 1 ? "" : "s")")
                    Text("•")
                    Text("≈ \(macro.estimatedDuration.compactDescription)")
                    if let hk = macro.hotkey {
                        Text("•")
                        Text(hk.displayString)
                    }
                    if isRunning {
                        Text("•")
                        Text("Running").foregroundStyle(Color(nsColor: IconRenderer.activeColor))
                    } else if let at = scheduledAt {
                        Text("•")
                        Text("Starts \(at.formatted(date: .omitted, time: .standard))").foregroundStyle(.orange)
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                iconButton("pencil", help: "Edit") {
                    MacroEditorWindow.open(macro: macro, isNew: false, state: state)
                }
                iconButton("doc.on.doc", help: "Duplicate") {
                    let copy = state.duplicate(macro)
                    MacroEditorWindow.open(macro: copy, isNew: false, state: state)
                }
                iconButton("square.and.arrow.up", help: "Share") {
                    shareTarget = macro
                }
                iconButton("trash", help: "Delete") {
                    state.delete(macro.id)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 22, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// Share link, copy-ready message and file export for one macro.
struct MacroShareView: View {
    let macro: Macro
    @State private var copied = false

    private var link: String { MacroSharing.link(for: macro)?.absoluteString ?? "" }
    private var message: String { MacroSharing.message(for: macro) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share “\(macro.name)”").font(.headline)
            Text("Anyone with AutoClicker can open this link to import the macro. The link contains the whole macro — no server involved, so it never expires.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("", text: .constant(link))
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
            HStack {
                Button(copied ? "Copied!" : "Copy Link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                ShareLink(item: message) { Label("Share…", systemImage: "square.and.arrow.up") }
                Spacer()
                Button("Export File…") { exportFile() }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: MacroSharing.fileExtension) ?? .json]
        panel.nameFieldStringValue = macro.name + "." + MacroSharing.fileExtension
        AppDelegate.shared.hideUI()
        if panel.runModal() == .OK, let url = panel.url {
            try? MacroSharing.export(macro, to: url)
        }
        AppDelegate.shared.showUI()
    }
}
