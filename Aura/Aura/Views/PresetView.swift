// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct PresetView: View {
    @Bindable var model: AppState
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Presets").font(.largeTitle.weight(.medium))
            Text("Apply a preset to \(model.module.name). Each module keeps its own configuration.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                TextField("New preset name", text: $name).textFieldStyle(.roundedBorder)
                Button("Save Current Module") { model.savePreset(name: name); name = "" }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("FACTORY").font(.caption).foregroundStyle(.secondary)
                    ForEach(EqualizerPreset.factory) { preset in
                        HStack {
                            Text(preset.name); Spacer()
                            Text("\(preset.bands.count) bands").font(.caption).foregroundStyle(.secondary)
                            Button("Apply") { model.applyPreset(id: preset.id) }
                        }.padding(10).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Text("YOUR PRESETS").font(.caption).foregroundStyle(.secondary).padding(.top, 12)
                    if model.saved.presets.isEmpty { Text("Save a module to create your first preset.").font(.callout).foregroundStyle(.secondary) }
                    ForEach(model.saved.presets) { preset in
                        HStack {
                            TextField("Preset name", text: Binding(get: { model.saved.presets.first { $0.id == preset.id }?.name ?? "" },
                                                                   set: { model.renamePreset(id: preset.id, name: $0) }))
                                .textFieldStyle(.roundedBorder)
                            Button("Apply") { model.applyPreset(id: preset.id) }
                            Button(role: .destructive) { model.deletePreset(id: preset.id) } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Delete preset \(preset.name)")
                        }.padding(8)
                    }
                }
            }
        }
    }
}
