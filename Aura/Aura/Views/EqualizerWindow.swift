// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import AuraCore
import SwiftUI

struct EqualizerWindow: View {
    @Bindable var model: AppState
    @State private var destination = "eq"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) { AuraBrandMark(); Text("AURA").tracking(2) }.font(.title2.weight(.semibold))
                        .padding(.bottom, 24).padding(.top, 12)
                    Text("EQUALIZERS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(0..<4, id: \.self) { index in
                        Button {
                            model.selectModule(index); destination = "eq"
                        } label: {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                Text(model.saved.configuration.modules[index].name).lineLimit(1)
                                Spacer(minLength: 0)
                                Circle().fill(moduleColor(index)).frame(width: 6, height: 6)
                            }.padding(.vertical, 10).padding(.horizontal, 10).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(destination == "eq" && model.selectedModule == index ? Color.white.opacity(0.09) : .clear,
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    Divider().padding(.vertical, 12)
                    sidebarButton("Presets", icon: "square.stack", destination: "presets")
                    sidebarButton("Settings", icon: "gearshape", destination: "settings")
                    Spacer()
                    Text("Precision in every\nfrequency.").font(.caption).foregroundStyle(.tertiary).lineSpacing(4)
                    Text("OUTPUT ENGINE · P1").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(18).frame(width: 180).frame(maxHeight: .infinity)
                .background(.ultraThinMaterial)
                Divider()
                ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AudioSourcePicker(model: model).frame(maxWidth: 350)
                    if model.sourceMode == .systemAudio { SystemAudioControls(model: model) }
                    else { playerBar }
                    if let error = model.activeError { notice(error, symbol: "exclamationmark.triangle") }
                    if let warning = model.persistenceMessage { notice(warning, symbol: "externaldrive.badge.exclamationmark") }
                    if model.activeOverRange { notice("Rendered samples exceeded 0 dBFS. Reduce input, module or master gain. No limiter is active.", symbol: "speaker.badge.exclamationmark") }
                    switch destination {
                    case "presets": PresetView(model: model)
                    case "settings": SettingsView(model: model)
                    default: EqualizerModuleView(model: model)
                    }
                    Spacer(minLength: 0)
                }.padding(24).frame(maxWidth: .infinity, alignment: .topLeading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer.padding(.horizontal, 20).padding(.vertical, 12).background(.bar)
        }
        .frame(minWidth: 1_000, minHeight: 740)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.mint)
        .disabled(!model.isLoaded)
    }

    private var playerBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LOCAL-FILE AUDIO").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(model.audio.fileName).font(.headline).lineLimit(1)
            }
            Spacer()
            Text("\(time(model.audio.position)) / \(time(model.audio.duration))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button { chooseAudioFile(model) } label: { Label("Open File", systemImage: "folder") }
            Button {
                if model.audio.state == .playing { model.audio.pause() } else { model.playLocalAudio() }
            } label: { Image(systemName: model.audio.state == .playing ? "pause.fill" : "play.fill").frame(width: 22) }
                .accessibilityLabel(model.audio.state == .playing ? "Pause" : "Play")
            Button { model.stopAllAudio() } label: { Image(systemName: "stop.fill") }.accessibilityLabel("Stop")
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Image(systemName: model.statusSymbol).foregroundStyle(model.statusColor)
            Text(model.transportDescription)
            Divider().frame(height: 12)
            Text(String(format: "%.1f kHz", model.activeSampleRate / 1_000)
                 + ((model.sourceMode == .systemAudio && model.systemAudio.state == .running)
                    || (model.sourceMode == .localFile && model.audio.duration > 0) ? "" : " preview"))
            Text(model.activeOutputName).lineLimit(1).foregroundStyle(.secondary)
            Spacer()
            Text("Master")
            Slider(value: Binding(get: { model.saved.configuration.masterGain },
                                  set: { value in model.editConfiguration { $0.masterGain = value } }), in: -60...12)
                .frame(width: 120).accessibilityLabel("Master gain")
            Text(dbText(model.saved.configuration.masterGain)).monospacedDigit().frame(width: 66, alignment: .trailing)
        }.font(.caption)
    }

    private func sidebarButton(_ name: String, icon: String, destination value: String) -> some View {
        Button { destination = value } label: {
            Label(name, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        }.buttonStyle(.plain)
            .background(destination == value ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func moduleColor(_ index: Int) -> Color {
        let module = model.saved.configuration.modules[index]
        return module.enabled && !module.bypassed && model.saved.configuration.processingEnabled ? .mint : .secondary
    }
    private func notice(_ message: String, symbol: String) -> some View {
        Label(message, systemImage: symbol).font(.caption).foregroundStyle(.orange)
    }
    private func time(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60) }
}
