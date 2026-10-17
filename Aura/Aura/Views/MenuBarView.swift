// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import AuraCore
import SwiftUI

struct MenuBarView: View {
    @Bindable var model: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                AuraBrandMark().foregroundStyle(.mint)
                Text("AURA").font(.title2.weight(.semibold)).tracking(3)
                Spacer()
                Image(systemName: model.statusSymbol).foregroundStyle(model.statusColor)
            }
            Text("LOCAL-FILE AUDIO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text("\(model.audio.state.label) · \(model.audio.engineRunning ? "Engine running" : "Engine stopped")")
                .font(.callout)
            Text(model.audio.fileName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Toggle("EQ processing", isOn: Binding(get: { model.saved.configuration.processingEnabled },
                                                 set: { value in model.editConfiguration { $0.processingEnabled = value } }))
                .toggleStyle(.switch)
            Divider()
            ForEach(Array(model.saved.configuration.modules.enumerated()), id: \.element.id) { index, module in
                HStack {
                    Button(module.name) { model.selectModule(index); openEditor() }.buttonStyle(.plain)
                    Spacer()
                    if !module.enabled { Text("Disabled").font(.caption).foregroundStyle(.secondary) }
                    Toggle("Bypass \(module.name)", isOn: Binding(get: { model.saved.configuration.modules[index].bypassed },
                        set: { value in model.editConfiguration { $0.modules[index].bypassed = value } }))
                        .labelsHidden().toggleStyle(.button)
                        .help("Bypass \(module.name)")
                }
            }
            Text("Preset: \(model.module.presetName)").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button { chooseAudioFile(model) } label: { Image(systemName: "folder") }
                    .help("Open local audio file")
                Button {
                    if model.audio.state == .playing { model.audio.pause() } else { model.audio.play() }
                } label: { Image(systemName: model.audio.state == .playing ? "pause.fill" : "play.fill") }
                Button { model.audio.stop() } label: { Image(systemName: "stop.fill") }
            }
            VStack(alignment: .leading) {
                HStack { Text("Master"); Spacer(); Text(dbText(model.saved.configuration.masterGain)).monospacedDigit() }
                Slider(value: Binding(get: { model.saved.configuration.masterGain },
                                      set: { value in model.editConfiguration { $0.masterGain = value } }), in: -60...12)
                    .accessibilityLabel("Master gain")
            }.font(.caption)
            Text("Output: \(model.audio.outputName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            if let error = model.audio.errorMessage { Text(error).font(.caption).foregroundStyle(.orange) }
            Divider()
            Button("Open Equalizer", action: openEditor).frame(maxWidth: .infinity)
            HStack {
                SettingsLink { Text("Settings…") }
                Spacer()
                Button("Quit AURA") { NSApp.terminate(nil) }
            }.font(.caption)
        }
        .padding(20).frame(width: 340).disabled(!model.isLoaded)
        .onAppear { model.audio.refreshOutput() }
    }

    private func openEditor() { openWindow(id: "equalizer"); NSApp.activate() }
}
