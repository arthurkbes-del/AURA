// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct SystemAudioControls: View {
    @Bindable var model: AppState
    @State private var outputs: [SystemOutputDevice] = []
    @State private var applications: [SystemAudioApplication] = []
    @State private var outputUID = SystemAudioInventory.defaultOutputUID
    @State private var applicationID: UInt32 = 0
    @State private var inventoryError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("APPLICATION AUDIO").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Picker("Output", selection: $outputUID) {
                Text("System default output").tag(SystemAudioInventory.defaultOutputUID)
                ForEach(outputs) { Text($0.name).tag($0.uid) }
                if outputUID != SystemAudioInventory.defaultOutputUID && !outputs.contains(where: { $0.uid == outputUID }) {
                    Text("Saved output unavailable").tag(outputUID)
                }
            }
            Picker("Source", selection: $applicationID) {
                Text("All applications").tag(UInt32(0))
                ForEach(applications) { Text("\($0.name) · \($0.pid)").tag($0.id) }
                if applicationID == .max { Text("Saved application not running").tag(UInt32.max) }
            }
            Text("Processes supported application audio on this output. macOS may ask for system audio recording access. No microphone is used.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(model.systemAudio.state == .running ? "Stop Processing" : "Start Processing") {
                    if model.systemAudio.state == .running { model.stopAllAudio() }
                    else {
                        let application = applications.first { $0.id == applicationID }
                        Task {
                            await model.startSystemAudio(selection: SystemAudioSelection(deviceUID: outputUID,
                                applicationPID: application?.pid,
                                applicationBundleID: application.flatMap { $0.bundleID.isEmpty ? nil : $0.bundleID }))
                        }
                    }
                }
                .disabled(applicationID == .max && model.systemAudio.state != .running)
                Button("Refresh") { refresh() }
                Spacer(minLength: 0)
                Text(model.systemAudio.state.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
            }
            if model.systemAudio.state == .running {
                Text(model.systemAudio.metrics.processingOutputActive
                     ? String(format: "Input peak %.1f dBFS · Output peak %.1f dBFS", 20 * log10(max(1e-12, model.systemAudio.metrics.inputPeak)), 20 * log10(max(1e-12, model.systemAudio.metrics.outputPeak)))
                     : "Waiting for capture signal · ordinary audio remains active. If audio is playing, check capture permission.")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                let metrics = model.systemAudio.metrics
                Text("Diagnostics · missing input blocks: \(metrics.missingInputBlocks) · timestamp gaps: \(metrics.timingDiscontinuities) · HAL overload events: \(metrics.overloadMonitoringAvailable ? String(metrics.overloadEvents) : "unavailable")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let inventoryError { Text(inventoryError).font(.caption).foregroundStyle(.orange) }
        }
        .disabled(model.systemAudio.state == .preparing || model.systemAudio.state == .stopping)
        .task { refresh(restoreHints: true) }
    }

    private func refresh(restoreHints: Bool = false) {
        do {
            outputs = try SystemAudioInventory.outputs()
            applications = try SystemAudioInventory.applications().filter { !$0.belongsToAura && $0.pid != ProcessInfo.processInfo.processIdentifier }
            if restoreHints {
                outputUID = model.saved.systemAudioPreferences.outputUID
                if let bundle = model.saved.systemAudioPreferences.applicationBundleID {
                    applicationID = applications.first { $0.bundleID == bundle }?.id ?? .max
                }
            } else if applicationID != 0 && !applications.contains(where: { $0.id == applicationID }) {
                if let bundle = model.saved.systemAudioPreferences.applicationBundleID {
                    applicationID = applications.first { $0.bundleID == bundle }?.id ?? .max
                } else { applicationID = .max }
            }
            inventoryError = nil
        } catch { inventoryError = error.localizedDescription }
    }
}

struct AudioSourcePicker: View {
    @Bindable var model: AppState
    var body: some View {
        Picker("Audio source", selection: Binding(get: { model.sourceMode }, set: { model.setSourceMode($0) })) {
            Text("Applications").tag(AudioSourceMode.systemAudio)
            Text("Local file").tag(AudioSourceMode.localFile)
        }.pickerStyle(.segmented)
    }
}
