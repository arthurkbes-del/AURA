import Foundation
import Synchronization

private struct FilterState {
    var l1 = 0.0, l2 = 0.0, r1 = 0.0, r2 = 0.0
}

private struct PlanHeader {
    var count = 0
    var gain = 1.0
}

private struct RenderBank {
    let coefficients = UnsafeMutablePointer<BiquadCoefficients>.allocate(capacity: 128)
    let states = UnsafeMutablePointer<FilterState>.allocate(capacity: 128)
    var header = PlanHeader()

    init() {
        coefficients.initialize(repeating: .identity, count: 128)
        states.initialize(repeating: FilterState(), count: 128)
    }

    func clear() { states.update(repeating: FilterState(), count: 128) }
    func release() {
        coefficients.deinitialize(count: 128); coefficients.deallocate()
        states.deinitialize(count: 128); states.deallocate()
    }

    @inline(__always) func render(_ left: Double, _ right: Double) -> (Double, Double) {
        var l = left * header.gain, r = right * header.gain
        for index in 0..<header.count {
            let c = coefficients[index]
            let state = states.advanced(by: index)
            let yl = c.b0 * l + state.pointee.l1
            let yr = c.b0 * r + state.pointee.r1
            let l1 = c.b1 * l - c.a1 * yl + state.pointee.l2
            let r1 = c.b1 * r - c.a1 * yr + state.pointee.r2
            let l2 = c.b2 * l - c.a2 * yl
            let r2 = c.b2 * r - c.a2 * yr
            // Flush denormals; corrupted/nonfinite input cannot poison state.
            state.pointee.l1 = l1.isFinite && abs(l1) > 1e-25 ? l1 : 0
            state.pointee.r1 = r1.isFinite && abs(r1) > 1e-25 ? r1 : 0
            state.pointee.l2 = l2.isFinite && abs(l2) > 1e-25 ? l2 : 0
            state.pointee.r2 = r2.isFinite && abs(r2) > 1e-25 ? r2 : 0
            l = yl.isFinite ? yl : 0; r = yr.isFinite ? yr : 0
        }
        return (l, r)
    }
}

/// Single control-thread producer, single render-thread consumer. Eight fixed
/// snapshots transfer POD coefficients with acquire/release publication. No
/// locks, ARC-owned snapshots, allocation or file/UI operations in beginBlock
/// or processStereo. configureImmediately/reset are only legal while stopped.
public final class EqualizerProcessor: @unchecked Sendable {
    public private(set) var sampleRate: Double
    private var current = RenderBank()
    private var next = RenderBank()
    private let headers = UnsafeMutablePointer<PlanHeader>.allocate(capacity: 8)
    private let plans = UnsafeMutablePointer<BiquadCoefficients>.allocate(capacity: 8 * 128)
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)
    private var fadePosition = 0
    private var fading = false
    private var fadeFrames: Int { max(1, Int(sampleRate * 0.02)) }

    public init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        headers.initialize(repeating: PlanHeader(), count: 8)
        plans.initialize(repeating: .identity, count: 8 * 128)
    }

    deinit {
        current.release(); next.release()
        headers.deinitialize(count: 8); headers.deallocate()
        plans.deinitialize(count: 8 * 128); plans.deallocate()
    }

    private func prepare(_ input: AudioConfiguration, into destination: UnsafeMutablePointer<BiquadCoefficients>) -> PlanHeader {
        var config = input; config.normalize(sampleRate: sampleRate)
        var header = PlanHeader(count: 0, gain: pow(10, (config.inputGain + config.masterGain) / 20))
        if config.processingEnabled {
            for module in config.modules where module.enabled && !module.bypassed {
                header.gain *= pow(10, module.outputGain / 20)
                for band in module.bands where band.enabled {
                    // Gain-zero bell/shelves are exact identity, saving idle DSP.
                    if band.type.supportsGain && band.gain == 0 { continue }
                    destination[header.count] = .make(band, sampleRate: sampleRate)
                    header.count += 1
                }
            }
        }
        return header
    }

    public func configureImmediately(_ configuration: AudioConfiguration, sampleRate: Double? = nil) {
        if let sampleRate { self.sampleRate = sampleRate }
        current.header = prepare(configuration, into: current.coefficients)
        current.clear(); next.clear(); fading = false; fadePosition = 0
        readIndex.store(writeIndex.load(ordering: .relaxed), ordering: .releasing)
    }

    /// False means the producer must retry its newest configuration later.
    @discardableResult public func submit(_ config: AudioConfiguration) -> Bool {
        let write = writeIndex.load(ordering: .relaxed)
        guard write - readIndex.load(ordering: .acquiring) < 8 else { return false }
        let slot = write % 8
        headers[slot] = prepare(config, into: plans.advanced(by: slot * 128))
        writeIndex.store(write + 1, ordering: .releasing)
        return true
    }

    public func beginBlock() {
        guard !fading else { return }
        let write = writeIndex.load(ordering: .acquiring)
        guard readIndex.load(ordering: .relaxed) < write else { return }
        let slot = (write - 1) % 8
        next.header = headers[slot]
        for index in 0..<next.header.count { next.coefficients[index] = plans[slot * 128 + index] }
        next.clear()
        readIndex.store(write, ordering: .releasing)
        fadePosition = 0; fading = true
    }

    @inline(__always) public func processStereo(_ left: Double, _ right: Double) -> (Double, Double) {
        let old = current.render(left.isFinite ? left : 0, right.isFinite ? right : 0)
        guard fading else { return old }
        let new = next.render(left, right)
        fadePosition += 1
        let t = Double(fadePosition) / Double(fadeFrames)
        let result = (old.0 + (new.0 - old.0) * t, old.1 + (new.1 - old.1) * t)
        if fadePosition >= fadeFrames {
            swap(&current, &next); fading = false
        }
        return result
    }
}
