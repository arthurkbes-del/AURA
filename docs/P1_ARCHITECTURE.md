# Proposed P1 architecture — system output processing

**Preparation only; not implemented.** Authority: [output-first roadmap](../AURA_OUTPUT_FIRST_ROADMAP.md). Start only after P0 completion and review of its validation report. No tap, aggregate device, capture permission request or routing mutation has been introduced in P0.

## Proposed path and boundaries

```text
Selected supported application outputs
  → private Core Audio process tap
  → AURA-owned aggregate device / HAL I/O
  → validated format conversion and bounded preallocated buffering
  → existing EqualizerProcessor (4 × 32 bands + headroom/master)
  → explicitly selected physical/Bluetooth output
```

This is an engineering proposal. First test a tap and selected output in a coherent HAL clock domain. If separate input/output clocks are necessary, validate a bounded producer/consumer ring, drift compensation and sample-rate conversion; do not assume nominally equal rates remain synchronized. The diagram does not assert that an aggregate device alone solves playback, synchronization or latency.

Retain the P0 local-file path for regression checks and diagnostics. A main-actor coordinator should own exactly one source session at a time. Both paths use the same normalized four-module configuration and coefficient implementation. Device/control operations, allocation and cleanup remain off the real-time callback. Do not route captured audio through an allocating AVAudioPlayerNode scheduling loop.

## Public API feasibility and unresolved evidence

Apple's [Core Audio taps sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) describes creating a process tap and using it as aggregate-device input. The installed SDK declares the relevant APIs. Its setup instructions specify macOS 14.2 or later, while current sample-page metadata lists newer SDK/OS availability; verify individual symbols and actual runtime behavior before setting a P1 deployment target. P0 currently targets macOS 15.

Investigate `CATapDescription`, `AudioHardwareCreateProcessTap`, tap UID properties, `AudioHardwareCreateAggregateDevice`, HAL I/O callbacks and their paired teardown APIs. Resolve process AudioObjectIDs from a refreshed inventory rather than persisting ephemeral IDs. Confirm all selectors, property sizes, muting and aggregate dictionary keys against the SDK/sample used by the experiment.

The future app must explain capture with `NSAudioCaptureUsageDescription` and handle the macOS permission flow. Denial or revocation must leave the ordinary output usable. Permission availability and protected content cannot be inferred from successful tap creation.

## Safety and lifecycle design

- **Session state:** idle → preparing → running → stopping → idle; failures return an actionable failed state after rollback. A generation identifier invalidates callbacks from previous sessions. Repeated start/stop is idempotent.
- **Feedback:** exclude AURA's own output from capture; verify the actual exclusion at runtime. Begin experiments with an explicitly selected process, rather than broad capture that might capture the processed return.
- **Dry duplication:** evaluate tap mute behavior, preferably muting only while the tap is consumed. Do not mute the source before the processed path is ready. Prove teardown/crash recovery restores ordinary output; an API name is not evidence of crash safety.
- **Ownership:** keep a registry of IDs and unique UIDs created by this session. Stop I/O, remove listeners, destroy callback registrations, destroy owned aggregate, then destroy owned tap. Roll back every partial-start failure. Never destroy a user's existing audio device.
- **Device changes:** stop/fade safely, invalidate stale callbacks, re-query stream format/clock and reconnect only to a valid chosen output. Handle removal, sleep/wake, default-output changes and Bluetooth reconnect. Do not silently change the global default output.
- **Sample rates:** reuse model clamping and republish coefficients after a rate change. Explicitly define supported formats/channels; report unsupported modes. Keep state/buffers bounded under underrun/overrun.
- **Levels:** retain headroom and overrange indication. P1 does not inherit a true peak limiter from P0; independently validated limiter development belongs to P2. No automatic volume changes or promise of clipping prevention.

## Validation and release boundaries

Tests must separate deterministic state/buffering/DSP behavior from hardware integration and listening. Capture a known signal from a controlled source; compare dry and processed spectra/gain, channels, timing and silence. Confirm no doubled dry path and no recursive feedback. Keep P0's 32 tests and 128-band rendered checks passing.

Measure end-to-end delay using a defined captured/output reference and a reproducible method. Record device, OS, stream rates, buffer sizes, dropout counts, CPU and memory. Compare internal speakers, wired/USB and Bluetooth separately; do not derive audible latency from buffer size or kernel benchmark throughput. Record protected/unavailable sources as unsupported or unverified, without promising universal compatibility.

Plan Intel-compatible code paths and build checks now. P4 owns full x86_64/arm64/Universal 2 and distribution qualification; P1 evidence on arm64 cannot prove Intel hardware behavior.

Source publication, distribution, Developer ID identity, notarization and ownership remain governed by [DISTRIBUTION.md](../DISTRIBUTION.md). No experiments in this document have been run as P1 work.
