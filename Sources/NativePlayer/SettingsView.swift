// SPDX-License-Identifier: GPL-3.0-or-later
//
// LiPlayer — Native macOS video player built with Swift, AppKit, SwiftUI, and libmpv.
// Copyright (C) 2026 Ali Ahad <https://aliahad.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import SwiftUI
import PlayerCore

struct SettingsView: View {
    @Bindable var session: PlayerSession
    @State private var bindings: [String: String] = [:]
    @State private var query = ""
    @State private var shortcutError: String?
    @State private var saved = false
    var body: some View {
        TabView {
            Form {
                Section("Playback") {
                    Toggle("Continue to the next file", isOn: $session.preferences.autoNext)
                    Toggle("Use hardware decoding when available", isOn: $session.preferences.hardwareDecoding)
                    Picker("Arrow-key seek interval", selection: $session.preferences.seekSeconds) { ForEach([1.0, 5, 10, 15, 30], id: \.self) { Text("\(Int($0)) seconds").tag($0) } }
                }
                Section("History") {
                    Toggle("Keep local playback history", isOn: $session.preferences.rememberHistory)
                    Toggle("Resume unfinished files", isOn: $session.preferences.resumePlayback).disabled(!session.preferences.rememberHistory)
                    HStack { Text("History stays on this Mac, limited to 200 files.").font(.system(size: 12)).foregroundStyle(.secondary); Spacer(); Button("Clear History") { session.clearHistory() } }
                }
                Section("Library and session") {
                    Toggle("Remember folders, queue and open panels", isOn: $session.preferences.rememberWorkspace)
                    Text("Your library stays on this Mac. The last video reopens paused; its position follows the history and resume settings above.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Folders are read in place. Removing one from the library never deletes its files.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Section("Appearance and subtitles") {
                    Picker("Appearance", selection: $session.preferences.appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    TextField("Default subtitle font", text: $session.preferences.subtitleFont)
                    Stepper("Subtitle size: \(Int(session.preferences.subtitleSize))", value: $session.preferences.subtitleSize, in: 16...80, step: 2)
                }
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "slider.horizontal.3") }
                .onChange(of: session.preferences) { previous, current in
                    var compared = current; compared.volume = previous.volume
                    if compared != previous { session.savePreferences(); session.applyPreferenceChanges(from: previous) }
                }
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search shortcuts", text: $query).textFieldStyle(.roundedBorder)
                Text("Use cmd, ctrl, alt, shift and a key: cmd+shift+s, left, or space. Leave blank to unbind.").font(.system(size: 12)).foregroundStyle(.secondary)
                List(PlayerCommand.allCases.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { command in
                    HStack { Text(command.title).font(.system(size: 13)); Spacer(); TextField("Unbound", text: Binding(get: { bindings[command.rawValue] ?? command.defaultShortcut }, set: { bindings[command.rawValue] = $0; saved = false })).textFieldStyle(.roundedBorder).frame(width: 160).font(.system(.body, design: .monospaced)).accessibilityLabel("Shortcut for \(command.title)") }
                }.listStyle(.plain)
                if let shortcutError { Text(shortcutError).font(.system(size: 12)).foregroundStyle(.red) }
                HStack { Button("Restore Defaults") { bindings = [:]; saved = false }; Spacer(); if saved { Text("Saved").foregroundStyle(.secondary) }; Button("Save Shortcuts") { saveBindings() }.keyboardShortcut("s", modifiers: .command) }
            }.padding(20).tabItem { Label("Shortcuts", systemImage: "keyboard") }
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    LiPlayerBrandMark(size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LiPlayer").font(.system(size: 24, weight: .semibold))
                        Text("A native Mac player with precise playback controls.").foregroundStyle(.secondary)
                    }
                }
                Divider()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development") · Apple Silicon · macOS 27.2 or later")
                Text("Copyright © 2026 Ali Ahad · LI Labs. Built with Swift, AppKit, SwiftUI, libmpv, FFmpeg and libass.").font(.system(size: 13)).foregroundStyle(.secondary)
                Text("Licensed under the GNU General Public License v3.0 (GPLv3). Distributed derivatives must remain open source under GPLv3 with attribution preserved. Native dependency notices and source locations are bundled with the app.").font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Video presentation uses OpenGL. HDR input is tone mapped to SDR; native HDR presentation and system Picture in Picture are not advertised in this version.").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button("Open Dependency Notices") { if let url = Bundle.main.resourceURL?.appendingPathComponent("Licenses") { NSWorkspace.shared.open(url) } }
                    if let repoURL = URL(string: "https://github.com/LiLabsAI/LiPlayer") {
                        Link("Source & License on GitHub", destination: repoURL)
                    }
                }
                Spacer()
            }.padding(28).tabItem { Label("About", systemImage: "info.circle") }
        }.frame(width: 650, height: 520).padding(12).onAppear { bindings = session.preferences.shortcuts }
    }
    private func saveBindings() {
        if let error = Shortcut.validate(bindings) { shortcutError = error; return }
        shortcutError = nil; session.preferences.shortcuts = bindings; session.savePreferences(); session.bindingsChanged?(); saved = true
    }
}
