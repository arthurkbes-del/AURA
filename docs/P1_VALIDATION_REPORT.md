# AURA P1 — development validation and crash correction

Date: 2026-10-17. Branch: `codex/aura-p1`. P0 baseline: `aff3f3a4fd33a43837ae960f93ee8c79540c2393`; capture snapshot: `4530f48`; graph crash correction: `b77c149`; capture-health/recovery hardening: `85ea29a`. **P1 acceptance remains open.** No publication or distribution occurred.

## Delivered behavior

Native Applications/Local file selection, all-app or explicit process capture, output selection, start/stop/retry, actual peaks and diagnostic counters. Public device-scoped process tap → one private aggregate → bounded HAL callback → existing four independent EQ modules, up to 32 bands each → same selected output. The original P0 file engine, presets and tests remain available. No external driver, microphone, model download or heavy dependency was introduced.

Initially supported capture format: native stereo Float32, planar/interleaved, matching input/output rate at 8–192 kHz on the same selected output. Other layouts/rates/cross-device routes are rejected with errors. Support for every app, protected content or every device is not claimed. See [architecture](P1_ARCHITECTURE.md) and [feasibility](P1_FEASIBILITY.md).

## User-reported crash

The user reported that processing worked but AURA closed after seconds, then reported another fall. Two macOS diagnostic reports at 10:01:45 and 10:02:58 show SIGABRT from Swift exclusive-access enforcement on the main thread. Graph dragging held an inout borrow into saved configuration while its closure read activeSampleRate/sourceMode from that same saved value. This was a UI model access conflict, not evidence of DSP overload.

A graph-style regression reproduced the abort before the fix (`evidence/p1/graph-exclusivity-red.txt`). Edit methods now work on local value copies, normalize, then assign back. The regression and full suite passed afterwards (`graph-exclusivity-green.txt`). A native numerical band edit during live capture also remained operational. Native CUA drag automation timed out, so that gesture is not claimed as a UI automation pass.

After receiving the rebuilt app and a request to retry playback/graph editing, the Product Owner confirmed on 2026-10-17: **“já fiz o teste funciona”**. Record this as a successful human retest following the crash correction. The reply does not specify the application, output, exact duration or individual gestures; it does not establish latency, bypass/echo behavior or forced-exit recovery, and does not close all P1 acceptance conditions.

## Verification evidence

Host: macOS 27.0.1 build 26A434, Apple Silicon arm64, Xcode 27.1/Swift 6.4/macOS 27 SDK. Deployment target 15; oldest-OS and Intel runtime qualification are pending.

| Check | Observed result | Evidence under `evidence/p1/` |
|---|---|---|
| Swift package regressions | 61 tests, zero failures after grouped fixes | `review-fixes-green.txt` |
| Xcode Debug tests | 61 tests, zero failures, TEST SUCCEEDED | `xcode-tests-hardened.txt` |
| Release app build | BUILD SUCCEEDED | `app-final-build.txt` |
| Native selected-process capture,128 nonflat bands | 1,369,600frames,31.12s,44.1kHz MacBook Pro speakers; output active; known1kHz gain approximately+6dB | `native-session-soak.txt` |
| Native all-app capture excluding AURA,128 bands | 1,377,280frames,31.31s,same output/rate; output active; approximately+6dB | `native-session-soak.txt` |
| Native live bypass and ordinary stop cleanup | Both modes stayed running during bypass and returned idle after stop | `native-session-soak.txt` |
| Native diagnostics during soak | Each mode: invalid buffers0,missing input0,HAL overload events0,timestamp discontinuities1 | `native-session-soak.txt` |
| Native GUI | Start/wait/signal/edit/stop and restored settings observed; real input/output peaks | `ui-validation.txt` |
| Human retest after crash correction | Product Owner: “já fiz o teste funciona”; application/output/duration not specified | `ui-validation.txt` |
| Performance profile | Time Profiler capture completed; traces remain local under ignored build/P1 | `instruments-128-profile.txt` |
| Licensing/source audit |46 Swift files with SPDX,unchanged GPLv3 SHA-256,zero external package dependencies | `license-audit.json` |

One timestamp discontinuity was observed in each native soak session; its cause has not been isolated. Zero HAL overload events does not prove zero audible dropouts. Independent maxima include startup/transitions, so peak ratios are approximate integration checks, not precision frequency-response measurements.

Soak performance covers the entire validator process including HAL/control/metrics, not the GUI or callback alone: selected-process 1.9392 user-CPU seconds over 31.122 s,peak RSS 17,629,184 bytes; all-app 2.1897 over 31.309 s,peak RSS 18,186,240 bytes. These are measured process figures, not hardware latency or a general CPU guarantee. Time Profiler does not establish zero allocations. No end-to-end latency number is fabricated.

GUI observation also saw active 44.1 kHz application processing on JBL Wave Buds 2 before final hardening. A subsequent unsupported-stereo error occurred during output changes. This is preliminary Bluetooth evidence only; Bluetooth reconnect/format stability and auditory acceptance are not qualified. No USB output was tested.

## Review rulings and corrective pass

One independent review covered the P1 snapshot against P0. Critical: the user’s graph exclusivity crash was reproduced/fixed. Important findings were accepted and addressed with regressions:

- Begin capture unmuted and gate return until actual nonzero PCM; return to ordinary playback on signal loss and fail on callback stall. Silence does not imply permission denial. Cost: a 100 ms control poll and 20 ms return fade, plus potentially audible activation transitions requiring listening evaluation.
- Retire only a never-started registration when its physical device is verified absent/reused; retain errors on uncertain ownership or transient failure. Cost: uncertain failures still require retry instead of speculative destruction.
- Compare current process HAL IDs as well as PID/bundle identities; stop on identity changes. Cost: explicit restart when relevant process identity changes.
- Add separate missing-input, timestamp-gap and HAL-overload counters; do not label them measured audible xruns. Cost: actual end-to-end dropout/latency qualification remains pending.
- Preserve source mode and visible cleanup error when switching sources fails. Cost: another source cannot start until owned resources are safely released.

No minor issue was deferred from this review; the source-mode issue was regraded Important and fixed. Same-output/stereo restrictions, unmeasured latency/hardware combinations and deferred microphone/neural/limiter work remain explicit scope/QA boundaries, not silently completed findings. No second review loop was used.

## Remaining acceptance and release conditions

- Basic human retest after the crash correction is confirmed above. Application/output, exact duration and gesture coverage remain unspecified; broader sustained-use qualification is pending. Earlier P0 audible acceptance remains valid.
- Human bypass comparison, no dry duplication/echo, ordinary audio continuing after stop and forced process termination. Successful API cleanup/UI states alone do not prove audible restoration.
- Clean-host permission grant/denial/revocation and protected/unavailable content behavior.
- Physical removal/reconnect, sample-rate changes and sleep/wake on actual hardware; USB and Bluetooth qualification beyond preliminary GUI observation.
- Reproducible end-to-end latency, long stability/energy/performance and allocation profiling under stated workloads. The roughly one-minute two-mode soak is a regression check, not prolonged production qualification.
- Intel/Apple Silicon/Universal 2,oldest supported OS, accessibility and release signing/notarization qualification as planned in P4. No P2 feature starts implicitly.

GPL-3.0-or-later remains selected, LICENSE is the full unaltered official GPLv3, and source SPDX/notices are retained. Current inventory has no incompatible external package dependency; Apple platform libraries are not vendored. **Copyright ownership, authority to release and icon artwork provenance remain pending before publication.** See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [DISTRIBUTION.md](../DISTRIBUTION.md). Local ad hoc builds are not Developer ID/notarized releases. No remote repository publication, binary distribution or external notarization upload was performed.

Optional Neural Voice/Video remains [documentation only](decisions/2026-10-17-optional-neural-processing.md), preserving conventional Intel features and the future Universal 2/CoreML capability/licensing requirements.
