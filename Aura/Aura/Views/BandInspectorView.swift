// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct BandInspectorView: View {
    @Bindable var model: AppState

    var body: some View {
        if let band = model.selectedBand {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("FILTER").font(.caption2).foregroundStyle(.secondary)
                    Picker("Filter", selection: Binding(get: { model.selectedBand?.type ?? .bell },
                                                         set: { value in model.editBand(band.id) { $0.type = value } })) {
                        ForEach(FilterType.allCases) { Text($0.name).tag($0) }
                    }.labelsHidden().frame(width: 125)
                    Toggle("Active", isOn: binding(band, \.enabled)).font(.caption)
                }
                parameter("FREQUENCY", value: binding(band, \.frequency), range: 20...min(20_000, model.activeSampleRate * 0.49), logarithmic: true)
                parameter("GAIN · dB", value: binding(band, \.gain), range: -24...24)
                    .disabled(!band.type.supportsGain)
                    .help(band.type.supportsGain ? "Band gain" : "Gain does not apply to pass and notch filters.")
                parameter("Q", value: binding(band, \.q), range: 0.1...30, logarithmic: true)
            }.padding(14).background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func binding<Value>(_ band: EqualizerBand, _ keyPath: WritableKeyPath<EqualizerBand, Value>) -> Binding<Value> {
        Binding(get: { (model.selectedBand ?? band)[keyPath: keyPath] },
                set: { value in model.editBand(band.id) { $0[keyPath: keyPath] = value } })
    }

    private func parameter(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, logarithmic: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).font(.callout.monospacedDigit())
            if logarithmic {
                Slider(value: Binding(get: { log10(max(range.lowerBound, value.wrappedValue)) },
                                      set: { value.wrappedValue = pow(10, $0) }),
                       in: log10(range.lowerBound)...log10(range.upperBound)).accessibilityLabel(title)
            } else {
                Slider(value: value, in: range).accessibilityLabel(title)
            }
        }.frame(maxWidth: .infinity)
    }
}
