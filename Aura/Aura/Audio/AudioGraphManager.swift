import AVFoundation

public final class AudioGraphManager {
    public let engine = AVAudioEngine()
    public let player = AVAudioPlayerNode()
    public let effect: AVAudioUnitEffect
    public let unit: AuraAudioUnit
    public let format: AVAudioFormat
    public var processor: EqualizerProcessor { unit.processor }
    private let inputMixer = AVAudioMixerNode()

    public init(sampleRate: Double, sourceChannels: AVAudioChannelCount = 2) throws {
        guard (8_000...192_000).contains(sampleRate), (1...2).contains(sourceChannels),
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let source = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: sourceChannels) else {
            throw NSError(domain: "AURA", code: 1, userInfo: [NSLocalizedDescriptionKey: "Use mono or stereo audio at 8–192 kHz."])
        }
        self.format = format
        AuraAudioUnit.register()
        effect = AVAudioUnitEffect(audioComponentDescription: AuraAudioUnit.component)
        guard let unit = effect.auAudioUnit as? AuraAudioUnit else {
            throw NSError(domain: "AURA", code: 2, userInfo: [NSLocalizedDescriptionKey: "Native EQ Audio Unit could not be created."])
        }
        self.unit = unit
        try unit.inputBusses[0].setFormat(format)
        try unit.outputBusses[0].setFormat(format)
        processor.configureImmediately(AudioConfiguration(), sampleRate: sampleRate)
        engine.attach(player); engine.attach(inputMixer); engine.attach(effect)
        engine.connect(player, to: inputMixer, fromBus: 0, toBus: 0, format: source)
        engine.connect(inputMixer, to: effect, fromBus: 0, toBus: 0, format: format)
        engine.connect(effect, to: engine.mainMixerNode, fromBus: 0, toBus: 0, format: format)
        inputMixer.outputVolume = 1; engine.mainMixerNode.outputVolume = 1
    }
}
