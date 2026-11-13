import SwiftUI
import TesseraCore

/// Everything the Settings window needs, bundled so views take one dependency.
@MainActor
struct SettingsEnvironment {
    let settings: Settings
    let hotkeys: HotkeyCenter
    let permissions: Permissions
    let recorder: ShortcutRecorder
    let launchAtLogin: LaunchAtLogin
    let updater: Updater
}

struct SettingsView: View {
    let environment: SettingsEnvironment

    var body: some View {
        TabView {
            ShortcutsPane(settings: environment.settings, hotkeys: environment.hotkeys,
                          recorder: environment.recorder)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            GeneralPane(settings: environment.settings, permissions: environment.permissions,
                        launchAtLogin: environment.launchAtLogin, updater: environment.updater)
                .tabItem { Label("General", systemImage: "gearshape") }
            AboutPane()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 580, height: 640)
    }
}

// MARK: - Shortcuts

private struct ShortcutsPane: View {
    @ObservedObject var settings: Settings
    @ObservedObject var hotkeys: HotkeyCenter
    @ObservedObject var recorder: ShortcutRecorder

    var body: some View {
        Form {
            if let message = recorder.message {
                Section { Label(message, systemImage: "info.circle").foregroundStyle(.secondary) }
            }
            ForEach(Command.Group.allCases, id: \.self) { group in
                Section(group.rawValue) {
                    ForEach(Command.allCases.filter { $0.group == group }, id: \.self) { command in
                        LabeledContent(command.title) {
                            ShortcutField(command: command, shortcut: settings.bindings[command],
                                          failed: hotkeys.failedCommands.contains(command),
                                          recorder: recorder) { settings.setShortcut(nil, for: command) }
                        }
                    }
                }
            }
            Section {
                Button("Restore Defaults") {
                    recorder.stop()
                    settings.resetShortcutsToDefaults()
                }
            } footer: {
                Text("Click a shortcut to record a new one. Esc cancels, ⌫ clears.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutField: View {
    let command: Command
    let shortcut: Shortcut?
    let failed: Bool
    @ObservedObject var recorder: ShortcutRecorder
    let clear: () -> Void

    private var isRecording: Bool { recorder.recording == command }

    var body: some View {
        HStack(spacing: 6) {
            if failed && !isRecording {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Couldn't register this shortcut. Another app is probably using it.")
            }
            Button { recorder.toggle(command) } label: {
                Text(label)
                    .foregroundStyle(isRecording || shortcut == nil ? .secondary : .primary)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)

            Button(action: clear) { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help("Clear shortcut")
                .opacity(shortcut != nil && !isRecording ? 1 : 0)
                .disabled(shortcut == nil || isRecording)
        }
    }

    private var label: String {
        if isRecording {
            let held = recorder.heldModifiers.symbols
            return held.isEmpty ? "Type shortcut…" : held
        }
        return shortcut?.description ?? "Record Shortcut"
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var settings: Settings
    @ObservedObject var permissions: Permissions
    @ObservedObject var launchAtLogin: LaunchAtLogin
    @ObservedObject var updater: Updater

    var body: some View {
        Form {
            Section {
                LabeledContent("Accessibility access") {
                    if permissions.isTrusted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { permissions.requestAccess() }
                    }
                }
                Toggle("Open Tessera at login", isOn: Binding(get: { launchAtLogin.isEnabled },
                                                              set: { launchAtLogin.set($0) }))
                if let error = launchAtLogin.lastError {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
            } footer: {
                if !permissions.isTrusted {
                    Text("Moving windows and switching Spaces both need Accessibility access.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Window Layout") {
                Picker("Pressing a layout shortcut again", selection: $settings.repeatBehavior) {
                    ForEach(RepeatBehavior.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                LabeledContent("Gap between windows") {
                    HStack {
                        Slider(value: $settings.gapSize, in: 0...40, step: 2).frame(width: 180)
                        Text("\(Int(settings.gapSize)) pt").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }

            Section {
                Toggle("When no display is in that direction, cycle through displays",
                       isOn: $settings.cycleDisplaysWhenNoNeighbour)
                Toggle("Put windows back when a display reconnects", isOn: $settings.restoreWindowsOnReconnect)
                Toggle("Move the pointer along when focusing another display", isOn: $settings.movePointerWithFocus)
            } header: {
                Text("Displays")
            } footer: {
                Text("Moving a full-screen window takes it out of full screen, moves it, and puts it back in full screen on the other display. Space shortcuts act on the display under the pointer, so moving the pointer when you focus a display makes them act on that display.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Make trackpad swipes between Spaces instant", isOn: $settings.instantTrackpadSwipes)
                Toggle("Show the Space number when switching", isOn: $settings.showSpaceHUD)
                Toggle("Show the current Space number in the menu bar", isOn: $settings.showSpaceNumberInMenuBar)
            } header: {
                Text("Spaces")
            } footer: {
                Text("Space shortcuts switch without the slide animation.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Check for updates automatically", isOn: $settings.automaticallyCheckForUpdates)
                Toggle("Install updates automatically", isOn: $settings.automaticallyInstallUpdates)
                    .disabled(!settings.automaticallyCheckForUpdates)
                UpdateStatusRow(updater: updater)
            } header: {
                Text("Updates")
            } footer: {
                Text("Tessera checks GitHub for a new release once a day. With automatic installs on, it installs the release once you haven't used the keyboard or mouse for two minutes, then restarts, which takes about a second.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateStatusRow: View {
    @ObservedObject var updater: Updater

    var body: some View {
        LabeledContent {
            switch updater.state {
            case .checking, .installing:
                ProgressView().controlSize(.small)
            case .available(let update):
                HStack {
                    Button("Release Notes") { NSWorkspace.shared.open(update.releaseNotesURL) }
                    Button("Install and Restart") { updater.install(update) }
                }
            case .installFailed:
                Button("Check Again") { Task { await updater.check() } }
            default:
                Button("Check Now") { Task { await updater.check() } }
            }
        } label: {
            Text(title)
            if let detail { Text(detail) }
        }
    }

    private var title: String {
        switch updater.state {
        case .checking: "Checking for updates…"
        case .available(let update): "Version \(update.version) is available"
        case .installing(let version): "Installing version \(version)…"
        case .checkFailed: "Couldn't check for updates"
        case .installFailed(let version, _): "Couldn't install version \(version)"
        case .idle, .upToDate: "Version \(updater.currentVersion)"
        }
    }

    private var detail: String? {
        switch updater.state {
        case .checkFailed(let message), .installFailed(_, let message):
            return message
        case .available:
            return "You have version \(updater.currentVersion)."
        default:
            guard let checked = updater.lastChecked else { return "Not checked yet" }
            return "Last checked \(checked.formatted(.relative(presentation: .named)))"
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Tessera").font(.title.weight(.semibold))
            Text("Version \(version)").foregroundStyle(.secondary)
            Text("Window snapping, Space switching without animation, and moving windows between displays, including full-screen windows.")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Divider().frame(maxWidth: 380)
            VStack(spacing: 6) {
                Text("Credits").font(.headline)
                Text("Space switching engine from [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel (MIT).")
                Text("Layouts and default shortcuts follow [Rectangle](https://rectangleapp.com).")
                Text("Display moves follow [Second Display](https://seconddisplay.app)'s behaviour.")
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
