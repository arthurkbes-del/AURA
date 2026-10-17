# AURA architecture

## Implemented P0 graph

```text
AVAudioFile → AVAudioPlayerNode → mono/stereo normalization mixer
    → AURA in-process Audio Unit
        input headroom → EQ 1 → EQ 2 → EQ 3 → EQ 4 → master gain
    → AVAudioEngine main mixer → system-selected output
```

`AudioGraphManager` builds the graph only when opening a file or reconnecting after an output/configuration change. Ordinary parameter edits do not rebuild it. AVAudioPlayerNode schedules the file or remaining segment using Apple's supported scheduling API; application code does not decode files inside its render block. The input mixer converts supported mono files to the stereo DSP format. AVAudioEngine handles the final connection to the output device.

A single custom `AUAudioUnit` contains four logical serial modules, each with up to 32 bands. It compacts active non-identity filters into at most 128 biquads. This avoids 128 independent Audio Unit nodes and the assumptions/parameter limitations of Apple's N-band EQ. Module scalar output gains commute through these linear filters and are folded with headroom/master into the scalar plan gain before the filter cascade; the calculated steady response includes all gains. No nonlinear limiter or clipping stage is hidden in that optimization.

The AU supports planar Float32 stereo buses at 8–192 kHz, processing filter state with Double precision. File length is explicitly limited to UInt32.max frames by the segment scheduler; unsupported sample rates/channel counts/empty or longer files produce an error. Compressed format support depends on AVAudioFile decoding and is not universal.

## DSP and response

`BiquadCoefficients` implements normalized digital bell, low/high shelf, high/low-pass and notch coefficients using the [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/) mathematical reference. Q controls damping, including resonant shelves; high-Q shelves need not be monotonic. Pass/notch filters ignore gain, and the UI disables that control. Frequency, gain and Q are finite-clamped to 20…min(20,000, 0.49 × sampleRate), −24…+24 dB and 0.1…30.

The response graph evaluates the exact coefficients used by the processor. It displays the selected module, selected filter and optional whole-chain response with headroom/master gain. It is a steady-state calculation, not a live spectrum or measurement of an external device. Its visible range clips responses outside the plot, and its high-frequency shaded area identifies frequencies above the source's usable Nyquist margin. Before a file loads, 48 kHz is explicitly a preview rate.

The processor uses transposed direct form II with separate left/right histories, flushes extremely small states and prevents nonfinite input/state propagation. Automated tests check literal gain/cutoff expectations, stability inequalities, rendered sine response, all 128 nonflat bands and actual Audio Unit output. These do not prove the absence of audible artifacts.

### Live parameter publication

The main actor is the single control producer; the Audio Unit render thread is the single consumer. Eight preallocated slots contain only POD plan headers and coefficients. Release/acquire atomic indices publish complete snapshots without blocking or transferring ARC-owned configuration arrays to the render thread. The producer retries its latest configuration if full. The consumer takes the newest published plan; configuration/graph reset is permitted only with the engine stopped.

DSP-identical plans are discarded on the control side, so names/preset bookkeeping do not restart filter histories. Changed plans crossfade two complete render banks over 20 ms. Only the coefficient-identical upstream prefix retains its scaled histories; changed poles and downstream filters start with cleared state. This prevents old high-Q histories from exciting unrelated new poles. Repeated extreme changes and phase differences still require listening evaluation; the smoothing mechanism is not a no-artifact guarantee.

Audio buffers, coefficients, states and snapshots are preallocated. The render block performs only PCM pulling, bounded sample/filter loops and an atomic overrange flag. It does not allocate snapshots, compute coefficients, acquire blocking locks, access files/UI, or dispatch work. Independently captured render resources avoid retaining the Audio Unit in its cached render block.

## State and lifecycle

`@MainActor @Observable AppState` owns versioned value models, selection and user presets. It coalesces audio configuration changes to at most about 30 updates/second and debounces persistence by 400 ms. `PersistenceWriter` serializes disk operations on an actor; atomic JSON writes use Application Support. Shutdown flushes the latest settings before normal termination. Corrupted JSON is quarantined, and unsupported future versions/oversized files are preserved rather than overwritten. Version 1 of the same envelope migrates to version 2; there is no claim to migrate arbitrary older third-party schemas.

`AudioEngineManager` coordinates the graph and explicit transport states: empty, ready, playing, paused, stopped, completed, failed. Generation tokens ignore stale completions. The scheduling completion only publishes an atomic token; the main-actor timer consumes it. Pausing records the frame, stops hardware rendering and resumes via a new segment. Stopping rewinds. A timer exists only during playback; completion and errors stop it. Security-scoped file access is released on replacement/shutdown.

AVAudioEngine configuration changes stop playback into a recoverable paused state. Play rebuilds the graph and refreshes output information. AURA never changes macOS's global selected output. Device switching and Bluetooth recovery remain manual validation items.

## Apple EQ investigation

Direct inspection of the installed MacOSX27 SDK found AVAudioUnitEQ frequency 20 Hz…sampleRate/2, octave bandwidth 0.05…5, gain/global gain −96…+24 dB, and filter-specific parameter differences. AudioToolbox declares maximum-band (2201) and five-Float64-per-band coefficient (2203) properties.

Executable probing initially reported 1 from the maximum-band property on a one-band instance. A corrected experiment instantiated 32-band units, observed 32 from that property, then successfully rendered four serial units: unity, four +6 dB bells yielding +24 dB, four cuts yielding −24 dB, bypass, and 128 enabled flat bands. This establishes that the tested configuration works; it does not establish an absolute platform maximum from a property whose observed result varied with configuration. Evidence: `evidence/apple-eq-32-probe.txt`.

Apple's octave-bandwidth interface does not directly implement the entire requested Q contract; at low frequencies the usual bandwidth/Q relation maps Q=0.1 to about 6.67 octaves and Q=30 to about 0.048 octaves, outside 0.05…5. Basic shelves/pass filters also ignore some parameters. AURA therefore uses native coefficients and direct Q, without narrowing the required controls or relying on an unverified approximation of Apple's coefficients.

References: [Apple N-band properties](https://developer.apple.com/documentation/audiotoolbox/1534022-aunbandeq-property-ids), [bandwidth](https://developer.apple.com/documentation/avfaudio/avaudiouniteqfilterparameters/bandwidth), [offline rendering](https://developer.apple.com/documentation/avfaudio/performing-offline-audio-processing).

## Headroom and safety

Input/headroom and master gain reduce or increase amplitude. They are **not** true peak limiters and do not guarantee clipping prevention under arbitrary 128-band boosts or high-Q resonances. Defaults apply −6 dB input and −6 dB master attenuation. Module/global bypass leaves those controls in effect. Actual rendered samples exceeding full scale set a visible warning; float overflow is bounded before output conversion. No automatic system-volume change occurs.

A true limiter needs independently validated peak detection, gain envelopes, lookahead/latency policy and listening tests in a later package.

## Future system audio feasibility — outside P0

Apple's [Core Audio taps sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) requires macOS 14.2 or later. It creates a CATapDescription, uses AudioHardwareCreateProcessTap, and adds the tap to a HAL aggregate device. Descriptions support process lists, mixdown, device/stream selection, visibility and mute behavior. NSAudioCaptureUsageDescription explains capture; recording through the aggregate prompts for permission. Tap/aggregate resources require cleanup.

Engineering assessment for a separate package:

- Resolve and select processes/devices explicitly; exclude AURA's own output to prevent feedback.
- Prevent simultaneous original dry playback and processed playback; investigate mute behavior with reversible cleanup and device-loss/crash recovery. P0 does not exercise these routing changes.
- Prefer a coherent output clock. Measure drift compensation, conversion/buffering and end-to-end latency instead of inferring delay from a nominal buffer size.
- Validate physical/USB outputs separately from Bluetooth, whose buffering, formats and reconnect behavior may differ.
- Protected content may be unavailable or silent. Apple Music, Spotify, browsers and their output modes require individual compatibility validation; universal support is not promised.
- Test permission, signing, sandbox/distribution and supported OS behavior before selecting a shipping capture design. P0 requests no capture permission and creates no aggregate device.

## Licensing and distribution

Project source is designated GPL-3.0-or-later. See LICENSE, CONTRIBUTING.md and THIRD_PARTY_NOTICES.md. No external packages are used; platform-library treatment and the actual linked binary inventory are documented. Copyright ownership remains undetermined before publication. Independent Developer ID signing/notarization is prepared in DISTRIBUTION.md but not performed, and no repository or binary has been published/distributed.

## Output-first roadmap and P1 handoff

The Product Owner prioritizes P1 system output capture/processing, P2 professional DSP, P3 advanced routing and P4 Intel/Apple Silicon/Universal 2 optimization and distribution. See [AURA_OUTPUT_FIRST_ROADMAP.md](AURA_OUTPUT_FIRST_ROADMAP.md). P0 audible processing and menu operation are confirmed; P1 still awaits review of the final P0 report. The proposed [P1 architecture](docs/P1_ARCHITECTURE.md) and [execution package](docs/superpowers/plans/2026-10-17-aura-p1.md) are preparation only. No tap or aggregate device has been created.
