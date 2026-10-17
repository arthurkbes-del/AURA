# AURA architecture and feasibility

**Status:** proposed P0 architecture. No app, DSP implementation, build, or audio playback has yet been validated. Xcode license acceptance blocks executable development. See VALIDATION_REPORT.md.

## P0 signal and ownership model

```text
AVAudioFile → AVAudioPlayerNode → input headroom
    → EQ 1 → EQ 2 → EQ 3 → EQ 4 → master gain → system-selected output
```

Use four Apple EQ nodes only if executable probing establishes 32 bands per node and the required parameter/transition behavior. Otherwise use native DSP with four logical stages and preallocated processing state. Either approach keeps the four modules independent without creating 128 Audio Unit nodes.

Main-actor application state owns editable value models and user-visible playback status. The audio controller coordinates AVAudioEngine and scheduling. Persistence runs outside audio callbacks. Ordinary parameter edits must not reconstruct the graph. Parameter smoothing and bypass transitions require rendered-sample tests and human listening, rather than assumptions about thread-safe setters.

Headroom and master gain are amplitude controls. They are not true peak limiters, and cannot guarantee clipping prevention for arbitrary combinations of 128 boosted filters. A future limiter needs its own tested DSP, latency policy, and peak-detection specification.

## Installed SDK findings

Read directly from MacOSX27.0.sdk headers on 2026-10-17:

- `AVAudioUnitEQ.h`: frequency 20 Hz…sample-rate/2; gain −96…+24 dB; octave bandwidth 0.05…5; global gain −96…+24 dB. The constructor does not state a maximum band count.
- `AudioUnitProperties.h`: `kAUNBandEQProperty_MaxNumberOfBands` (2201) reports the actual maximum; setting too many bands returns an error. `kAUNBandEQProperty_BiquadCoefficients` (2203) returns five Float64 coefficients per band.
- Filter-specific parameters differ: basic pass filters ignore gain/bandwidth; ordinary shelves ignore bandwidth. Controls must reflect the chosen filter's behavior.

The existence of the coefficient API does not establish coefficient ordering, runtime availability, sign convention, or agreement with rendered response. These remain executable validation gates. Apple's bandwidth range also does not establish full Q 0.1…30 support. Do not claim AVAudioUnitEQ meets the product specification until the probe and extended tests establish it.

Sources: [Apple N-band properties](https://developer.apple.com/documentation/audiotoolbox/1534022-aunbandeq-property-ids), [bandwidth](https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters/bandwidth), [offline processing](https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing).

## Future system-audio feasibility — outside P0

Apple's [Core Audio taps sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) requires macOS 14.2 or later. It creates a `CATapDescription`, uses `AudioHardwareCreateProcessTap`, and adds the tap to a HAL aggregate device. Descriptions support process lists, mixdown, device/stream selection, visibility and mute behavior. Add `NSAudioCaptureUsageDescription`; starting recording through the aggregate device prompts for system-audio permission. Destroy tap and aggregate objects during cleanup.

Engineering assessment, requiring a separate implementation and validation package:

- Resolve process identifiers through HAL and let the user choose explicit processes/devices; keep an exclusion for AURA's own output path to prevent feedback.
- A replacement-EQ path must prevent the original dry audio playing alongside the processed copy. Evaluate tap mute behavior with explicit user authorization, reversible cleanup, and recovery after crashes/device loss.
- Prefer one coherent output clock. Aggregate-device drift compensation, format conversion, buffering, and DSP all affect delay. Measure end-to-end latency and clock drift rather than infer them from nominal buffer size.
- Validate built-in/USB outputs separately from Bluetooth. Wireless buffering, negotiated formats, reconnects and transport changes require dedicated tests; no shared latency promise is justified yet.
- Protected media may be unavailable or silent. Music, Spotify, browsers and individual output modes need separate compatibility checks; no universal support is promised.
- Permissions, signing, distribution and sandbox compatibility must be tested on intended OS versions before choosing a shipping capture architecture. P0 does not request audio-capture permission or create aggregate devices.

This is a feasible investigation path, not evidence of a functioning system-wide equalizer.
