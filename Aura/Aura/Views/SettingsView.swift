// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppState

    var body: some View {
        Form {
            Section("Audio") {
                Toggle("EQ processing", isOn: Binding(get: { model.saved.configuration.processingEnabled },
                                                     set: { value in model.editConfiguration { $0.processingEnabled = value } }))
                LabeledContent("Input headroom", value: dbText(model.saved.configuration.inputGain))
                Slider(value: Binding(get: { model.saved.configuration.inputGain },
                                      set: { value in model.editConfiguration { $0.inputGain = value } }), in: -48...0)
                    .accessibilityLabel("Input headroom")
                Text("Headroom reduces input level. It is not a peak limiter. Multiple boosts can still cause clipping.")
                    .font(.caption).foregroundStyle(.secondary)
                LabeledContent("Output", value: model.audio.outputName)
                Text("Follows the output selected in macOS. Output changes stop playback safely; press Play to reconnect.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Local-first") {
                Text("AURA processes only the local file you open. Other applications and system audio are not captured.")
                Text("Settings and custom presets are stored in Application Support/com.evoluere.aura. No network connection is used.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = model.persistenceMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            }
            Section("Configuration") {
                Button("Reset All Four Equalizers") { model.resetAll() }
                Text("Custom presets are retained. Module settings, bypass, input headroom and master gain return to defaults.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("AURA · P0 Foundation") {
                Text("Four independent modules · 32 bands each · native Swift DSP")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}
