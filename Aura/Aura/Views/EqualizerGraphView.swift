// SPDX-License-Identifier: GPL-3.0-or-later
import AuraCore
import SwiftUI

struct EqualizerGraphView: View {
    @Bindable var model: AppState
    @State private var showAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Filter response", systemImage: "waveform.path").font(.caption.weight(.medium))
                Text("Calculated · not a spectrum analyzer").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Toggle("All 4 + gains", isOn: $showAll).toggleStyle(.checkbox).font(.caption)
            }
            GeometryReader { geometry in
                let rect = plotRect(geometry.size)
                Canvas { context, size in
                    let plot = plotRect(size)
                    for gain in [-24.0, -12, 0, 12, 24] {
                        let y = yPosition(gain, rect: plot)
                        var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y)); line.addLine(to: CGPoint(x: plot.maxX, y: y))
                        context.stroke(line, with: .color(.white.opacity(gain == 0 ? 0.25 : 0.065)), lineWidth: 1)
                        context.draw(Text(String(format: "%+.0f", gain)).font(.system(size: 9)).foregroundColor(.gray),
                                     at: CGPoint(x: plot.minX - 9, y: y), anchor: .trailing)
                    }
                    for frequency in [20.0, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000] {
                        let x = xPosition(frequency, rect: plot)
                        var line = Path(); line.move(to: CGPoint(x: x, y: plot.minY)); line.addLine(to: CGPoint(x: x, y: plot.maxY))
                        context.stroke(line, with: .color(.white.opacity(0.065)), lineWidth: 1)
                        let label = frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))"
                        context.draw(Text(label).font(.system(size: 9)).foregroundColor(.gray),
                                     at: CGPoint(x: x, y: plot.maxY + 14))
                    }
                    let rate = model.activeSampleRate
                    let maximum = min(20_000, rate * 0.49)
                    if maximum < 20_000 {
                        let start = xPosition(maximum, rect: plot)
                        context.fill(Path(CGRect(x: start, y: plot.minY, width: plot.maxX - start, height: plot.height)),
                                     with: .color(.white.opacity(0.07)))
                    }
                    let module = model.module
                    let coefficients = module.enabled && !module.bypassed
                        ? module.bands.map { BiquadCoefficients.make($0, sampleRate: rate) } : []
                    context.drawLayer { layer in
                        layer.clip(to: Path(plot))
                        let path = curve(rect: plot, maximum: maximum) { frequency in
                            guard module.enabled && !module.bypassed else { return 0 }
                            return coefficients.reduce(module.outputGain) { $0 + $1.decibels(at: frequency, sampleRate: rate) }
                        }
                        layer.stroke(path, with: .color(.mint), style: StrokeStyle(lineWidth: 2.3, lineJoin: .round))
                        if let band = model.selectedBand {
                            let coefficient = BiquadCoefficients.make(band, sampleRate: rate)
                            layer.stroke(curve(rect: plot, maximum: maximum) { coefficient.decibels(at: $0, sampleRate: rate) },
                                         with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        }
                        if showAll {
                            let enabled = model.saved.configuration.processingEnabled
                            let config = model.saved.configuration
                            let all = enabled ? config.modules.filter { $0.enabled && !$0.bypassed } : []
                            let filters = all.flatMap(\.bands).map { BiquadCoefficients.make($0, sampleRate: rate) }
                            let gain = config.inputGain + config.masterGain + all.reduce(0) { $0 + $1.outputGain }
                            layer.stroke(curve(rect: plot, maximum: maximum) { frequency in
                                filters.reduce(gain) { $0 + $1.decibels(at: frequency, sampleRate: rate) }
                            }, with: .color(.orange.opacity(0.8)), style: StrokeStyle(lineWidth: 1.4, dash: [6, 3]))
                        }
                    }
                }
                ForEach(Array(model.module.bands.enumerated()), id: \.element.id) { index, band in
                    let selected = model.selectedBand?.id == band.id
                    Text("\(index + 1)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Color.black : Color.white)
                        .frame(width: selected ? 24 : 19, height: selected ? 24 : 19)
                        .background(band.enabled ? (selected ? Color.mint : Color(nsColor: .darkGray)) : Color.gray.opacity(0.35), in: Circle())
                        .overlay(Circle().stroke(.mint.opacity(selected ? 1 : 0.6), lineWidth: 1))
                        .position(x: xPosition(band.frequency, rect: rect), y: yPosition(band.type.supportsGain ? band.gain : 0, rect: rect))
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("response"))
                            .onChanged { gesture in
                                model.selectedBandID = band.id
                                let fraction = min(1, max(0, (gesture.location.x - rect.minX) / rect.width))
                                let gain = min(24, max(-24, (rect.midY - gesture.location.y) / rect.height * 60))
                                model.editBand(band.id) {
                                    $0.frequency = min(model.activeSampleRate * 0.49, 20 * pow(1_000, fraction))
                                    if $0.type.supportsGain { $0.gain = gain }
                                }
                            })
                        .accessibilityLabel("Band \(index + 1), \(band.type.name), \(frequencyText(band.frequency))")
                        .help("Drag to change frequency\(band.type.supportsGain ? " and gain" : ""). Edit Q below.")
                }
            }
            .coordinateSpace(name: "response")
            .padding(6)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: 38, y: 14, width: max(1, size.width - 54), height: max(1, size.height - 42))
    }
    private func xPosition(_ frequency: Double, rect: CGRect) -> Double {
        rect.minX + log10(max(20, frequency) / 20) / 3 * rect.width
    }
    private func yPosition(_ gain: Double, rect: CGRect) -> Double { rect.midY - gain / 60 * rect.height }
    private func curve(rect: CGRect, maximum: Double, response: (Double) -> Double) -> Path {
        var path = Path()
        for index in 0...256 {
            let frequency = 20 * pow(1_000, Double(index) / 256)
            guard frequency <= maximum else { break }
            let point = CGPoint(x: xPosition(frequency, rect: rect), y: yPosition(response(frequency), rect: rect))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
