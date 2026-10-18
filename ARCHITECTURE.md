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

The response graph evaluates the exact coefficients used by the processor. It displays the selected module, selected filter and optional whole-chain response with headroom/master gain. It is a steady-state calculation, not a live spectrum or measurement of an external device. Its visible range clips responses outside the plot, and its high-frequency shaded area identifies frequencies above the source's usable Nyquist margin. Before either source starts, 48 kHz is a preview rate. During capture the graph follows its actual session rate. Value-copy editing prevents overlapping Swift access to saved configuration during graph gestures.

The processor uses transposed direct form II with separate left/right histories, flushes extremely small states and prevents nonfinite input/state propagation. Automated tests check literal gain/cutoff expectations, stability inequalities, rendered sine response, all 128 nonflat bands and actual Audio Unit output. These do not prove the absence of audible artifacts.

### Live parameter publication

The main actor is the single control producer; the Audio Unit render thread is the single consumer. Eight preallocated slots contain only POD plan headers and coefficients. Release/acquire atomic indices publish complete snapshots without blocking or transferring ARC-owned configuration arrays to the render thread. The producer retries its latest configuration if full. The consumer takes the newest published plan; configuration/graph reset is permitted only with the engine stopped.

DSP-identical plans are discarded on the control side, so names/preset bookkeeping do not restart filter histories. Changed plans crossfade two complete render banks over 20 ms. Only the coefficient-identical upstream prefix retains its scaled histories; changed poles and downstream filters start with cleared state. This prevents old high-Q histories from exciting unrelated new poles. Repeated extreme changes and phase differences still require listening evaluation; the smoothing mechanism is not a no-artifact guarantee.

Audio buffers, coefficients, states and snapshots are preallocated. The render block performs only PCM pulling, bounded sample/filter loops and an atomic overrange flag. It does not allocate snapshots, compute coefficients, acquire blocking locks, access files/UI, or dispatch work. Independently captured render resources avoid retaining the Audio Unit in its cached render block.

## State and lifecycle

`@MainActor @Observable AppState` owns versioned value models, selection and user presets. It coalesces audio configuration changes to at most about 30 updates/second and debounces persistence by 400 ms. `PersistenceWriter` serializes disk operations on an actor; atomic JSON writes use Application Support. Shutdown flushes the latest settings before normal termination. Corrupted JSON is quarantined, and unsupported future versions/oversized files are preserved rather than overwritten. Versions 1 and 2 of the same envelope migrate to version 3 with default capture preferences; there is no claim to migrate arbitrary older third-party schemas.

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

## P1 application output processing

The implemented [P1 architecture](docs/P1_ARCHITECTURE.md) uses public process taps and a single private aggregate at a common rate on the selected output. The local-file Audio Unit path remains available; the main-actor source coordinator prevents simultaneous playback paths. Both share EqualizerProcessor and the four-module configuration.

Capture begins unmuted with AURA’s output gated. The control-side health policy verifies nonzero PCM before switching to mutedWhenTapped and fading in the processed return. After 0.5 seconds without signal it gates the return and unmutes ordinary playback; after 2 seconds without callback progress it stops with a recovery message. Silence alone is not classified as denied permission. These thresholds are recovery policy, not measured hardware latency. Clean-host permission/revocation still needs qualification. The user confirmed ordinary audio continuing after actual forced GUI termination and successful reopen/Start without echo in the tested Spotify setup; this is not a universal crash-restoration guarantee.

A silent never-started output registration establishes AURA’s own HAL identity before exclusive capture. Own PID/helper bundle identities are excluded and monitored; selected sources are also checked against current HAL object IDs. Device/rate/stream/default-output/sleep changes stop the session for explicit restart. Reverse cleanup retains resources on uncertain failure, checks ownership UIDs, and can retire a never-started registration whose device disappeared or object ID was reused without touching a foreign device.

The render callback validates bounded planar/interleaved stereo Float32 buffers, processes the existing EQ, and publishes atomic peaks/overrange, missing-input, timestamp-gap and HAL overload-event counters. Counters do not establish audible dropout counts. No resampling, cross-device queue or microphone path is implemented. See the [validation report](docs/P1_VALIDATION_REPORT.md) for measured scope and pending tests.

## Universal 2 build

The shared conventional audio implementation builds for arm64 and x86_64 with a macOS 15 minimum. The Xcode project uses standard architectures; Debug builds the active architecture and Release sets `ONLY_ACTIVE_ARCH=NO`. `Scripts/generate-project.py` preserves those settings when regenerating the project. `Scripts/build-universal.sh` builds a generic macOS Release destination and verifies all bundled Mach-O files, deployment minima, license resources and the local ad hoc signature.

The [Universal 2 report](docs/UNIVERSAL2_VALIDATION_REPORT.md) records native arm64 tests and x86_64 tests plus real capture under Rosetta. Physical Intel hardware and oldest-OS qualification remain pending. Architecture selection adds no feature restrictions or separate DSP path.

## Licensing and distribution

Project source is designated GPL-3.0-or-later. See LICENSE, CONTRIBUTING.md and THIRD_PARTY_NOTICES.md. No external packages are used; platform-library treatment and the actual linked binary inventory are documented. Arthur Bes explicitly declared rights and authority to publish the code and icon on 2026-10-18; see COPYRIGHT.md and the [publication decision](docs/decisions/2026-10-18-source-publication.md). Source publication to arthurkbes-del/AURA is authorized. Independent Developer ID signing/notarization is prepared in DISTRIBUTION.md but not performed; binary distribution still requires separate authorization.

## Output-first roadmap and P1 handoff

The Product Owner prioritizes P1 system output capture/processing, P2 professional DSP, P3 advanced routing and P4 Intel/Apple Silicon/Universal 2 optimization and distribution. See [AURA_OUTPUT_FIRST_ROADMAP.md](AURA_OUTPUT_FIRST_ROADMAP.md). P0 audible processing and menu operation are confirmed; The subsequent instruction “vamos para o p1” authorized P1 execution. Its [architecture](docs/P1_ARCHITECTURE.md) and [execution package](docs/superpowers/plans/2026-10-17-aura-p1.md) now describe an implemented development candidate, not a qualified release.
