// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import AuraCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor func chooseAudioFile(_ model: AppState) {
    let panel = NSOpenPanel()
    panel.title = "Open local audio file"
    panel.allowedContentTypes = [.audio]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.begin { response in
        guard response == .OK, let url = panel.url else { return }
        MainActor.assumeIsolated { try? model.loadAudio(url) }
    }
}

struct AppCommands: Commands {
    let model: AppState
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Audio File…") { chooseAudioFile(model) }.keyboardShortcut("o")
                .disabled(!model.isLoaded)
        }
        CommandMenu("Playback") {
            Button(model.sourceMode == .systemAudio ? (model.engineRunning ? "Stop Processing" : "Start Processing") : (model.audio.state == .playing ? "Pause" : "Play")) {
                if model.sourceMode == .systemAudio {
                    if model.engineRunning { model.stopAllAudio() } else { Task { await model.startPreferredSystemAudio() } }
                } else if model.audio.state == .playing { model.audio.pause() } else { model.playLocalAudio() }
            }.keyboardShortcut("p", modifiers: [.command, .option])
            Button("Stop") { model.stopAllAudio() }.keyboardShortcut(".")
        }
    }
}

extension AppState {
    var statusSymbol: String {
        if activeError != nil { return "exclamationmark.triangle.fill" }
        if !engineRunning { return "stop.circle" }
        return saved.configuration.processingEnabled ? "waveform.circle.fill" : "slash.circle"
    }
    var statusColor: Color {
        if activeError != nil { return .red }
        if !engineRunning { return .secondary }
        return saved.configuration.processingEnabled ? .mint : .orange
    }
}

func dbText(_ value: Double) -> String { String(format: "%+.1f dB", value) }
func frequencyText(_ value: Double) -> String {
    value >= 1_000 ? String(format: "%.2f kHz", value / 1_000) : String(format: "%.0f Hz", value)
}
