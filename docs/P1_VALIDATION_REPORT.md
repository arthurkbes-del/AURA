# AURA P1 — development validation and crash correction

Date: 2026-10-17. Branch: `codex/aura-p1`. P0 baseline: `aff3f3a4fd33a43837ae960f93ee8c79540c2393`; capture snapshot: `4530f48`; graph crash correction: `b77c149`; capture-health/recovery hardening: `85ea29a`. **P1 functional acceptance is complete for the tested support envelope, confirmed by the Product Owner.** No publication or distribution occurred.

## Delivered behavior

Native Applications/Local file selection, all-app or explicit process capture, output selection, start/stop/retry, actual peaks and diagnostic counters. Public device-scoped process tap → one private aggregate → bounded HAL callback → existing four independent EQ modules, up to 32 bands each → same selected output. The original P0 file engine, presets and tests remain available. No external driver, microphone, model download or heavy dependency was introduced.

Initially supported capture format: native stereo Float32, planar/interleaved, matching input/output rate at 8–192 kHz on the same selected output. Other layouts/rates/cross-device routes are rejected with errors. Support for every app, protected content or every device is not claimed. See [architecture](P1_ARCHITECTURE.md) and [feasibility](P1_FEASIBILITY.md).

## User-reported crash

The user reported that processing worked but AURA closed after seconds, then reported another fall. Two macOS diagnostic reports at 10:01:45 and 10:02:58 show SIGABRT from Swift exclusive-access enforcement on the main thread. Graph dragging held an inout borrow into saved configuration while its closure read activeSampleRate/sourceMode from that same saved value. This was a UI model access conflict, not evidence of DSP overload.

A graph-style regression reproduced the abort before the fix (`evidence/p1/graph-exclusivity-red.txt`). Edit methods now work on local value copies, normalize, then assign back. The regression and full suite passed afterwards (`graph-exclusivity-green.txt`). A native numerical band edit during live capture also remained operational. Native CUA drag automation timed out, so that gesture is not claimed as a UI automation pass.

After receiving the rebuilt app and a request to retry playback/graph editing, the Product Owner confirmed on 2026-10-17: **“já fiz o teste funciona”**. Record this as a successful human retest following the crash correction. The initial reply did not specify the test details. In the acceptance follow-up, the Product Owner identified **Spotify, all available outputs, about 10 minutes**, confirmed a clear EQ/bypass difference without echo/duplication and ordinary audio continuing after Stop Processing, and confirmed successful restart without crashes/duplication after JBL disconnect/reconnect and physical sleep. These are human-reported results, not instrumented hardware measurements; individual output names/modes and the exact per-output duration were not enumerated. The user subsequently confirmed actual forced GUI termination/reopen/Start with ordinary audio continuing and processing returning without echo. The Product Owner later confirmed the remaining tests as OK; see the acceptance update below.

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
| Human retest after crash correction | Spotify, all available outputs, approximately 10min; no echo, bypass difference and ordinary playback after Stop confirmed | `ui-validation.txt` |
| Performance profile | Time Profiler capture completed; traces remain local under ignored build/P1 | `instruments-128-profile.txt` |
| Licensing/source audit |46 Swift files with SPDX,unchanged GPLv3 SHA-256,zero external package dependencies | `license-audit.json` |

One timestamp discontinuity was observed in each native soak session; its cause has not been isolated. Zero HAL overload events does not prove zero audible dropouts. Independent maxima include startup/transitions, so peak ratios are approximate integration checks, not precision frequency-response measurements.

Soak performance covers the entire validator process including HAL/control/metrics, not the GUI or callback alone: selected-process 1.9392 user-CPU seconds over 31.122 s,peak RSS 17,629,184 bytes; all-app 2.1897 over 31.309 s,peak RSS 18,186,240 bytes. These are measured process figures, not hardware latency or a general CPU guarantee. Time Profiler does not establish zero allocations. No end-to-end latency number is fabricated.

GUI observation also saw active 44.1 kHz application processing on JBL Wave Buds 2 before final hardening. A subsequent unsupported-stereo error occurred during output changes. That initial observation was preliminary Bluetooth evidence. The later human acceptance follow-up confirms JBL disconnect/reconnect, resumed processing and no echo for the tested setup. Other Bluetooth modes/formats and quantified transmission latency remain unqualified. No USB output was tested.

## Review rulings and corrective pass

One independent review covered the P1 snapshot against P0. Critical: the user’s graph exclusivity crash was reproduced/fixed. Important findings were accepted and addressed with regressions:

- Begin capture unmuted and gate return until actual nonzero PCM; return to ordinary playback on signal loss and fail on callback stall. Silence does not imply permission denial. Cost: a 100 ms control poll and 20 ms return fade, plus potentially audible activation transitions requiring listening evaluation.
- Retire only a never-started registration when its physical device is verified absent/reused; retain errors on uncertain ownership or transient failure. Cost: uncertain failures still require retry instead of speculative destruction.
- Compare current process HAL IDs as well as PID/bundle identities; stop on identity changes. Cost: explicit restart when relevant process identity changes.
- Add separate missing-input, timestamp-gap and HAL-overload counters; do not label them measured audible xruns. Cost: actual end-to-end dropout/latency qualification remains pending.
- Preserve source mode and visible cleanup error when switching sources fails. Cost: another source cannot start until owned resources are safely released.

No minor issue was deferred from this review; the source-mode issue was regraded Important and fixed. Same-output/stereo restrictions, unmeasured latency/hardware combinations and deferred microphone/neural/limiter work remain explicit scope/QA boundaries, not silently completed findings. No second review loop was used.

## Current closure status

Confirmed human checks: Spotify across available outputs for about10 minutes, EQ/bypass difference without echo/duplication, ordinary Stop restoration, JBL reconnect, physical sleep/restart and actual forced GUI exit/reopen/Start. Native lifecycle/rate tests,64 deterministic tests and the311.92-second128-band controlled soak pass.

On2026-10-17, in response to the remaining permission and physical-latency checks, the Product Owner stated **“já fiz esses testes e está ok”**. This closes functional acceptance as user-reported success for the tested setup. The agent did not observe the permission toggles, and no physical measurement value/method was supplied. Do not infer a quantified physical delay, a clean-host first-grant pass or universal compatibility. [Acceptance record](../evidence/p1/product-owner-acceptance.json).

The independently measured27.104ms remains a relative digital tap comparison. Instrumented physical end-to-end latency, untested hardware/OS modes and distribution qualification remain explicitly outside the established evidence. Interrupted runs remain incomplete records, never substituted for the successful uninterrupted run.

## Acceptance closure run — 2026-10-17

The validation-only tools added in `5d181da` do not change the production app or its DSP. [Native acceptance results](../evidence/p1/acceptance-native-result.json) cover:

- 20 actual start/stop cycles with128 nonflat bands; each returns the caller-visible private tap/aggregate inventory to its baseline. HAL inventory publication settled after up to100ms in observed cycles. Early harness assertions before publication settled failed; the bounded inventory wait corrected the measurement harness, not a production audio defect. Unknown/foreign resources are never destroyed by the test.
- Actual controlled source process termination triggers the production identity listener, safely stops, releases resources and permits capture of a fresh process.
- Delivery of the native workspace sleep notification exercises the production listener/cleanup. Separately, an un-injected sleep notification stopped the first prolonged run safely (`stability-five-minutes.txt`); that interrupted run is not a stability PASS. The user independently confirms physical sleep/restart.
- SIGKILL of a child executing the actual ProcessTapBackend, followed by successful capture in a fresh session. Private cross-process HAL inventory and audible dry-path restoration cannot be inferred from the fresh session. The GUI itself was not killed in this experiment.
- Actual built-in output44.1→48kHz: failure/recovery listener, successful capture after explicit restart at48kHz, then exact restoration to44.1kHz. Available/settable rates are checked. The global default output and volume are not changed.

### Uninterrupted selected-source stability

The final selected-process run completed **311.92seconds (5min12s),128 active nonflat bands,13,753,344frames** on MacBook Pro44.1kHz. Invalid buffers0,missing input blocks0,HAL overload events0,timestamp discontinuities1. The one observed timestamp gap did not grow during the run; its cause remains unisolated. These counters do not prove zero audible artifacts. Live bypass and ordinary cleanup completed after observation. Evidence: [full log](../evidence/p1/stability-selected-uninterrupted.txt), [result](../evidence/p1/stability-selected-uninterrupted-result.json).

The validator used21.6861 process user-CPU seconds across311.9218wall seconds,peak resident17,760,256bytes. Scope includes HAL/control/metrics and excludes the GUI; no callback-only CPU, energy or physical-latency guarantee follows. Peak maxima include transients, so the+5.64dB peak-ratio check is not a precision frequency-response measurement. Long all-app quiet-fixture attempts were interrupted/level-contaminated; the successful controlled all-app baseline and the user's approximately10-minute Spotify session remain separate evidence.

The native tool reports device latency56frames, safety offset48frames, buffer512frames and stream latency639frames on MacBook Pro44.1kHz. These are separate HAL-reported components, not a measured total. Apple documents the [latency selector](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertylatency) and [safety offset selector](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertysafetyoffset); local SDK declarations were also inspected.

### Controlled digital timing measurement

[Digital marker evidence](../evidence/p1/digital-latency-result.json): a quiet deterministic broadband marker in a separate source process, a unity-gain production-backend return on the same built-in44.1kHz output, and a capture-only private aggregate observing those two process taps at48kHz. No microphone, physical input or audio recording file is used. After stopping observer I/O, offline normalized cross-correlation searches ±100ms over4096-frame windows. Known +37/−23-frame shifts, gain changes, silence, unrelated data and ambiguous periodic tones are checked by three analysis tests. A source handshake verifies the PRBS fixture, and a strong competing non-neighbor correlation peak rejects the measurement. The regression first failed on a periodic1kHz tone before that ambiguity check was added (`latency-ambiguity-red.txt`).

Three repeated-marker windows at1,2,3seconds yielded1301frames, **27.104ms**, correlation approximately0.9550–0.9558, with246,272captured frames and zero invalid observer buffers. This measures the relative displacement of the source tap and unity return tap in this observer topology, including tap/aggregate scheduling and conversion. It excludes DAC, speaker/acoustic and Bluetooth transmission delay; tap aggregation/alignment is part of the observation. The final rerun verified the marker protocol and observer cleanup before completion; it overlapped a separately selected-source soak, so it is not an isolated CPU benchmark. It is not a general end-to-end physical latency number, a limiter delay, or an Intel/other-device qualification.

### Qualification and release limitations after functional acceptance

- Actual macOS permission tests are now **user-reported OK**. Earlier, the user could not toggle permission and the agent preserved it. The later confirmation supersedes that pending human check; the exact sequence and OS responses were not independently observed. A clean-host first grant remains unqualified.
- Physical end-to-end latency requires a defined independent output reference/loopback; no microphone or new hardware capability was added to manufacture this evidence. USB, protected-content modes, oldest supported OS and untested output formats remain unqualified.
- Intel/Apple Silicon/Universal2,accessibility,extensive performance/energy/allocation and Developer ID/notarization qualification remain inP4. Current P1 tests do not authorize P2 or an external release.

GPL-3.0-or-later remains selected, LICENSE is the full unaltered official GPLv3, and source SPDX/notices are retained. Current inventory has no incompatible external package dependency; Apple platform libraries are not vendored. **Copyright ownership, authority to release and icon artwork provenance remain pending before publication.** See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md) and [DISTRIBUTION.md](../DISTRIBUTION.md). Local ad hoc builds are not Developer ID/notarized releases. No remote repository publication, binary distribution or external notarization upload was performed.

Optional Neural Voice/Video remains [documentation only](decisions/2026-10-17-optional-neural-processing.md), preserving conventional Intel features and the future Universal 2/CoreML capability/licensing requirements.

## Reproduction and review disposition

See [P1 acceptance runbook](P1_ACCEPTANCE_RUNBOOK.md) for exact commands and the remaining permission sequence. Existing permissions were inspected read-only and preserved.

The independent validation-tool review found one Important issue: a stale tone fixture could silently ignore --marker and yield an ambiguous correlation peak. Accepted and corrected with a failing periodic-tone regression, explicit marker protocol verification, peak uniqueness and a successful rerun (`digital-latency-reviewed.txt`); observer releases also returned success before completion. Observer cleanup-status reporting and big-endian rejection were also corrected before final evidence. No production source was changed in this acceptance run. The complete package regression run passes 61 core tests plus 3 measurement-analysis tests (64 total), and the Release app still builds; see acceptance-full-suite-final-pass.txt and acceptance-app-build.txt. The updated license audit checks 50 Swift files, zero missing SPDX notices, the unchanged official GPLv3 hash and zero external dependencies.

Review scope rulings: physical latency/dropouts require an independent physical reference; SIGKILL restart does not substitute for hearing (now separately supplied); human Spotify/sleep/reconnect results are reported as human evidence; interrupted/contaminated soaks are never PASS; permission denial/revocation/protected modes and untested USB/Intel/oldest OS/release conditions remain outside measured evidence; unchanged P0 behavior is supported by the full regression run rather than a new broad production review. Costs of these limits are explicit unqualified hardware/instrumentation claims; later Product Owner confirmation closes functional acceptance without upgrading unobserved tests into instrumented evidence. No minor finding remains deferred in this validation-tool pass.

Interrupted soak records are preserved in [stability-interruptions.json](../evidence/p1/stability-interruptions.json). The SIGTERM source is unknown; no final pass or production-crash conclusion is inferred. The all-app level-guard stop also remains unqualified as a quiet fixture, not silently rewritten as a success.

**Closure decision:** P1 functional acceptance is complete for the stated tested support envelope on the Product Owner’s final confirmation. Preserve the distinction between automated/native evidence and user-reported permission/physical checks. Instrumented physical latency, clean-host first grant, Intel/Universal 2, untested hardware/OS and release qualification are not established by this acceptance. The application binary at this P1 handoff was arm64 only. A subsequent Product Owner instruction authorized [Universal 2 build preparation](UNIVERSAL2_VALIDATION_REPORT.md), which records the later dual-architecture artifact and Rosetta evidence separately. Physical Intel qualification remains pending. No publication, binary distribution or P2 start is implied.
