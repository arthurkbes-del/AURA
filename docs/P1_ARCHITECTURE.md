# P1 architecture — application output processing

Implemented development candidate after the Product Owner’s “vamos para o p1” instruction. P0 remains intact. This describes the current implementation; [P1 validation](P1_VALIDATION_REPORT.md) distinguishes evidence from pending qualification.

```text
Supported application output on chosen device
  → private device/stream-scoped process tap
  → one owned private aggregate (physical input channels disabled)
  → bounded stereo Float32 HAL render bridge
  → EqualizerProcessor (4 × 32 bands + input/module/master gains)
  → same chosen physical output
```

## Format and source contract

Use public CATapDescription, AudioHardwareCreateProcessTap, AudioHardwareCreateAggregateDevice and paired HAL ownership APIs. The installed SDK declares process taps from macOS 14.2; deployment remains macOS 15. Actual validation is on macOS 27.0.1, Apple Silicon. Apple’s [Core Audio taps sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) informed feasibility; the implementation does not import sample code or a third-party library.

The first supported topology uses one selected output, stereo native-endian Float32, matching tap/output rates at 8–192 kHz. Callback capacity is bounded at 65,536 frames. Planar and interleaved layouts are tested. Generic stereo mixdown stayed at 48 kHz while this host’s output was 44.1 kHz, so that topology was rejected rather than assuming aggregate-device conversion. Cross-device capture/playback, resampling, multichannel and arbitrary output formats remain unsupported until independently implemented and validated. This is a technical boundary, not an artificial feature restriction.

Applications mode selects all supported processes except AURA, or one refreshed audio process. Global capture excludes the current AURA PID and matching helper bundle identities; a silent never-started physical-output IO registration establishes that PID’s HAL object before creating the tap. Process-list monitoring checks actual HAL object IDs as well as PID/bundle identity. A missing saved application never silently expands to all applications. Persist only stable output UID and bundle hints, not ephemeral PID/HAL IDs. Capture never auto-starts after relaunch.

AppState owns one active source path. Starting capture stops local playback; file loading/playback stops capture and refuses to proceed if cleanup failed. The P0 AVAudioEngine/Audio Unit file path and the P1 HAL path use the same EqualizerProcessor. Version 1/2 saved settings migrate to version 3. Graph/inspector use the active source rate. Editing uses local value copies before assigning to saved state so graph closures may read source/configuration without overlapping Swift inout access.

## Permission, mute and recovery

NSAudioCaptureUsageDescription explains capture; no microphone input is opened. Tap creation alone is not proof of granted permission or useful PCM. Begin unmuted with the processed return gated. A control timer polls actual callback progress and peaks every 100 ms. Verified nonzero input enables mutedWhenTapped and a 20 ms return fade. After 0.5 seconds without signal, gate the return and unmute ordinary playback; after 2 seconds without callback progress, unmute and fail with a retry message. Silence is not labeled permission denial. These policy intervals are not latency measurements, and transitions still need listening qualification.

The coordinator follows idle → preparing → running → stopping → idle, with actionable failed states. Generation tokens invalidate old listener events. Startup rollback and normal stop reverse ownership: stop I/O, remove listeners, destroy I/O registration, destroy private aggregate, destroy tap, release never-started identity registration. Stop failure retains callback resources for explicit retry. Unique UIDs prevent destruction of foreign resources. A vanished/reused physical device retires only its never-started identity registration; uncertain inventory/read/destroy failures remain errors.

Device disappearance, stream/rate changes, default-output changes for the default selection, process identity changes and sleep stop processing. The user refreshes/selects and starts again; automatic profiles/reconnection are P3. No global default-output or volume mutation occurs. Forced-exit restoration and clean-host denial/revocation still require hardware QA; an API name is not proof of crash safety.

## Real-time work and diagnostics

The control producer publishes coefficient plans through the existing preallocated SPSC queue; the HAL consumer performs bounded PCM/filter loops. No UI, file work, coefficient creation, blocking locks or control Task dispatch occurs in the render/overload callbacks. Configure buffers and processor before I/O; release them only after quiescing/destroying I/O. A 20 ms DSP-plan crossfade preserves the existing live-edit policy.

Atomic diagnostics include frames/blocks, invalid buffers, missing input blocks, sample-time discontinuities, HAL processor-overload events when supported, input/output peaks and actual output overrange. Invalid layout/capacity stops the session safely. Missing input, timestamp gaps and overload events are distinct observations, not proven audible dropout counts. Performance numbers cover the stated measurement scope only. No true peak limiter is implemented; P2 owns that work.

## Qualification and future boundaries

Run deterministic lifecycle/rollback, policy, stereo/bounds, DSP, persistence and model regressions separately from native controlled-source experiments and human hearing checks. Preserve all P0 tests and four independent 32-band modules. Native tests must state device/rate/source, permission context, mute transitions, cleanup, counters and elapsed observation. Whole-path latency requires a defined reference/capture experiment, not buffer-size arithmetic.

Intel x86_64 and Universal 2 are required product targets; arm64 runtime evidence does not qualify Intel. After P1 acceptance, the Product Owner brought Universal 2 build preparation forward: see the [dual-architecture artifact and Rosetta evidence](UNIVERSAL2_VALIDATION_REPORT.md). P4 still owns full physical hardware/architecture/distribution qualification. Microphone/video/neural implementation remains deferred. Optional neural processing is recorded only in [the future decision](decisions/2026-10-17-optional-neural-processing.md); no models or heavy dependencies are present.

GPL-3.0-or-later, source/artwork ownership, publication and distribution remain governed by [DISTRIBUTION.md](../DISTRIBUTION.md). No remote publication, binary distribution or notarization upload is authorized or performed.
