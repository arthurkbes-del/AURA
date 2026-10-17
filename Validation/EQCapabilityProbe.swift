// Standalone SDK feasibility experiment. This is not the AURA application.
// Run after Xcode setup: swift Validation/EQCapabilityProbe.swift
// Offline rendering only; no output-device or system-routing modifications.
import AVFoundation
import AudioToolbox
import Foundation

enum ProbeFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String {
        switch self { case .failed(let message): return message }
    }
}

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ProbeFailure.failed(message) }
}

func maximumBands(of equalizer: AVAudioUnitEQ) throws -> UInt32 {
    var maximum: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioUnitGetProperty(
        equalizer.audioUnit, kAUNBandEQProperty_MaxNumberOfBands,
        kAudioUnitScope_Global, 0, &maximum, &size
    )
    try require(status == noErr, "Maximum-band query failed: OSStatus \(status)")
    try require(size == MemoryLayout<UInt32>.size, "Unexpected maximum-band property size")
    return maximum
}

// Measures the real graph at 1 kHz, ignoring the first quarter-second to
// exclude filter startup transients. The expected gains below are literal,
// independently specified values, not computed by a response-preview helper.
func renderedGain(stageGain: Float, bypass: Bool, allBands: Bool = false) throws -> Double {
    let sampleRate = 48_000.0
    guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
          let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96_000),
          let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096),
          let sourceChannels = source.floatChannelData else {
        throw ProbeFailure.failed("Could not allocate offline stereo buffers")
    }
    source.frameLength = source.frameCapacity
    for channel in 0..<2 {
        for frame in 0..<Int(source.frameLength) {
            sourceChannels[channel][frame] = Float(0.01 * sin(2 * .pi * 1_000 * Double(frame) / sampleRate))
        }
    }

    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    let stages = (0..<4).map { _ in AVAudioUnitEQ(numberOfBands: 32) }
    engine.attach(player)
    var previous: AVAudioNode = player
    for (index, stage) in stages.enumerated() {
        try require(stage.bands.count == 32, "Stage \(index + 1) did not allocate 32 bands")
        engine.attach(stage)
        engine.connect(previous, to: stage, format: format)
        for (bandIndex, band) in stage.bands.enumerated() {
            band.filterType = .parametric
            band.frequency = 1_000
            band.bandwidth = 1
            band.gain = bandIndex == 0 ? stageGain : 0
            band.bypass = bypass || (!allBands && bandIndex != 0)
        }
        previous = stage
    }
    engine.connect(previous, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 1
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4_096)
    defer {
        player.stop()
        engine.stop()
        engine.disableManualRenderingMode()
    }
    player.scheduleBuffer(source)
    try engine.start()
    player.play()

    var outputEnergy = 0.0
    var inputEnergy = 0.0
    var sampleCount = 0
    var retries = 0
    while engine.manualRenderingSampleTime < AVAudioFramePosition(source.frameLength) {
        let start = engine.manualRenderingSampleTime
        let remaining = AVAudioFramePosition(source.frameLength) - start
        let count = AVAudioFrameCount(min(4_096, remaining))
        let status = try engine.renderOffline(count, to: result)
        switch status {
        case .success:
            retries = 0
            try require(result.frameLength > 0, "Offline render made no progress")
            guard let output = result.floatChannelData else {
                throw ProbeFailure.failed("Missing rendered float channels")
            }
            for frame in 0..<Int(result.frameLength) {
                let position = Int(start) + frame
                guard position >= 12_000, position < Int(source.frameLength) else { continue }
                for channel in 0..<2 {
                    let value = Double(output[channel][frame])
                    try require(value.isFinite, "Nonfinite rendered sample at \(position)")
                    outputEnergy += value * value
                    let input = Double(sourceChannels[channel][position])
                    inputEnergy += input * input
                    sampleCount += 1
                }
            }
        case .cannotDoInCurrentContext:
            retries += 1
            try require(retries <= 100, "Offline rendering could not progress after 100 attempts")
        case .insufficientDataFromInputNode:
            throw ProbeFailure.failed("Offline graph reported insufficient input")
        case .error:
            throw ProbeFailure.failed("Offline graph returned a rendering error")
        @unknown default:
            throw ProbeFailure.failed("Unknown manual-rendering status")
        }
    }
    try require(sampleCount > 0 && inputEnergy > 0 && outputEnergy > 0, "No measurable rendered signal")
    return 10 * log10(outputEnergy / inputEnergy)
}

do {
    print("AURA Apple EQ capability probe — offline, stereo, 48 kHz, 1 kHz sine")
    let maximum = try maximumBands(of: AVAudioUnitEQ(numberOfBands: 1))
    print("Reported maximum bands per Apple EQ: \(maximum)")
    try require(maximum >= 32, "Apple EQ does not support 32 bands; native DSP alternative required")

    let fixtures: [(name: String, gain: Float, bypass: Bool, allBands: Bool, expectedDB: Double)] = [
        ("four-stage unity", 0, false, false, 0),
        ("four stages × +6 dB bell", 6, false, false, 24),
        ("four stages × −6 dB bell", -6, false, false, -24),
        ("bypassed boosted bands", 6, true, false, 0),
        ("128 enabled flat bands", 0, false, true, 0)
    ]
    for fixture in fixtures {
        let measured = try renderedGain(
            stageGain: fixture.gain, bypass: fixture.bypass, allBands: fixture.allBands
        )
        print(String(format: "%@: measured %.4f dB; expected %.1f ±0.25 dB",
                     fixture.name, measured, fixture.expectedDB))
        try require(abs(measured - fixture.expectedDB) <= 0.25,
                    "Rendered gain outside tolerance: \(fixture.name)")
    }
    print("Capability fixtures passed. Q range, other filters, coefficients, smoothing, UI and audible playback remain unverified.")
} catch {
    print("PROBE FAILED: \(error)")
    exit(1)
}
