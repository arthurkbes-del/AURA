// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct EqualizerModuleView: View {
    @Bindable var model: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TextField("Module name", text: Binding(get: { model.module.name },
                                                       set: { value in model.editModule { $0.name = value } }))
                    .textFieldStyle(.plain).font(.title.weight(.medium)).frame(maxWidth: 240)
                    .accessibilityLabel("Module name")
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { model.module.enabled },
                                                  set: { value in model.editModule { $0.enabled = value } }))
                    .toggleStyle(.switch).controlSize(.small)
                Toggle("Bypass", isOn: Binding(get: { model.module.bypassed },
                                                 set: { value in model.editModule { $0.bypassed = value } }))
                    .toggleStyle(.button)
            }
            HStack {
                Text("\(model.module.bands.count) of 32 bands").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(model.presets) { preset in
                        Button(preset.name) { model.applyPreset(id: preset.id) }
                    }
                } label: { Label(model.module.presetName, systemImage: "square.stack") }
                    .frame(width: 170)
                Button("Reset") {
                    model.editModule { $0.reset() }; model.selectedBandID = model.module.bands.first?.id
                }
            }
            EqualizerGraphView(model: model).frame(height: 285)
            HStack {
                Text("BANDS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { model.addBand() } label: { Label("Add Band", systemImage: "plus") }
                    .disabled(model.module.bands.count >= 32)
                Button { model.removeSelectedBand() } label: { Image(systemName: "minus") }
                    .disabled(model.module.bands.count <= 1).accessibilityLabel("Remove selected band")
            }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.module.bands.enumerated()), id: \.element.id) { index, band in
                        Button { model.selectedBandID = band.id } label: {
                            HStack {
                                Text(String(format: "%02d", index + 1)).monospacedDigit().foregroundStyle(.secondary).frame(width: 26)
                                Text(band.type.name).frame(width: 95, alignment: .leading)
                                Text(frequencyText(band.frequency)).frame(width: 80, alignment: .trailing)
                                Spacer()
                                Text(band.type.supportsGain ? dbText(band.gain) : "—").frame(width: 75, alignment: .trailing)
                                Text(String(format: "Q %.2f", band.q)).frame(width: 65, alignment: .trailing)
                                Image(systemName: band.enabled ? "checkmark.circle.fill" : "circle").foregroundStyle(band.enabled ? .mint : .secondary)
                            }.font(.caption).padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .background(model.selectedBand?.id == band.id ? Color.white.opacity(0.08) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }
                }
            }.frame(height: 96)
            BandInspectorView(model: model)
            HStack {
                Text("Module output").font(.caption)
                Slider(value: Binding(get: { model.module.outputGain },
                                      set: { value in model.editModule { $0.outputGain = value } }), in: -24...24)
                    .accessibilityLabel("Module output gain")
                Text(dbText(model.module.outputGain)).font(.caption.monospacedDigit()).frame(width: 70)
            }
        }
    }
}
