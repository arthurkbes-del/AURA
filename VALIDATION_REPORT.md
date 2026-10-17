# AURA P0 validation report

Date: 2026-10-17 (America/Sao_Paulo). Scope: native local-file processing on Apple Silicon.

**Overall result: P0 COMPLETE against its stated Definition of Done.** The Product Owner confirmed both menu icon visibility/panel opening and audible processing: “consegui escutar ele muda o som”. This confirms hearing an EQ-related sound change; it does not certify artifact-free operation, every output device or every filter combination.

**P1 NOT STARTED.** The output-first roadmap and proposed P1 architecture/execution package are prepared. Review of this final P0 report remains the entry gate for P1.

## 1. Implemented features

- Exactly four independent serial modules, each with 1–32 bands, for 128 configurable bands total. Independent names, enable/bypass, output gains, presets and resets.
- Bell, low/high shelf, high/low-pass and notch; finite frequency 20…min(20,000, 0.49 × sampleRate), gain −24…+24 dB and Q 0.1…30. Gain is disabled for pass/notch filters because those filters do not use it.
- Real local-file loading, play, pause/resume, stop/rewind, natural completion, live parameter changes, global/module bypass, headroom and master gain. Supported source contract: mono/stereo, 8–192 kHz, 1…UInt32.max frames, formats AVAudioFile can decode.
- SwiftUI MenuBarExtra panel, focusable editor, four-module sidebar, native file picker, logarithmic Canvas response editor, draggable bands, exact selected-filter/module/whole-chain response and actual playback/output status.
- Seven parameterized factory presets; custom save/apply/rename/delete; versioned Codable configuration, atomic writes, debounce, corrupt-file quarantine and protection of unsupported future data.
- Generated native wave identity, macOS app icon and four status assets. After the Product Owner reported a missing menu icon, the custom SwiftUI shape label was replaced by the native named-image MenuBarExtra initializer. Release was rebuilt/relaunched; the Product Owner confirmed “Sim, aparece e abre o painel”.
- No permanent Dock icon, external package, server, network requirement, driver, global routing change or system capture in P0.

## 2. Files delivered

The complete repository inventory is recorded in [evidence/delivery-files.txt](evidence/delivery-files.txt). Main groups:

| Paths | Responsibility |
|---|---|
| Package.swift; Aura/Aura.xcodeproj/ | Local library, app, validation tools, shared Xcode app/test scheme |
| Aura/Aura/App/ | Lifecycle, observable state, native file commands and shortcuts |
| Aura/Aura/Models/; Aura/Aura/Persistence/ | Four-module models, factory/user presets, validation and durable storage |
| Aura/Aura/Audio/ | Graph, transport, output inspection, Audio Unit, biquads, real-time processor and response |
| Aura/Aura/Views/ | Menu, editor, graph, band inspector, presets and settings |
| Aura/Aura/Branding/; Aura/Aura/Resources/ | Shared vector wave, app/status assets, Info.plist |
| Aura/AuraTests/ | Six deterministic test suites |
| Validation/ | Apple EQ probe, hardware/kernel validator and native asset generator |
| LICENSE; CONTRIBUTING.md; THIRD_PARTY_NOTICES.md; DISTRIBUTION.md | GPL designation, contribution rules, dependency audit and future release preparation |
| README.md; ARCHITECTURE.md; docs/; evidence/ | Build/use instructions, implementation decisions, plans and actual evidence |
| AURA_OUTPUT_FIRST_ROADMAP.md; docs/P1_ARCHITECTURE.md | Product Owner roadmap and gated P1 handoff |

The original master prompt is preserved unchanged in docs/MASTER_EXECUTION_PROMPT.md. The supplied icon reference was not altered or bundled.

## 3. Audio architecture

AVAudioFile → AVAudioPlayerNode → mono/stereo normalization mixer → one in-process AURA Audio Unit → main mixer → macOS-selected output.

The unit implements four logical serial EQ modules. Loading/reconnecting builds the graph; ordinary EQ edits do not rebuild it. Pause stops rendering and resumes from a saved frame; stop rewinds; natural completion stops the engine/timer. Generation-safe atomic completion signals prevent stale schedules from completing new playback. Output/configuration changes enter a recoverable paused state; Play reconnects. The app reads the system output and never changes its global selection.

Scheduling/decoding use Apple's supported APIs. Application callbacks do not perform disk I/O, UI work, blocking locks or configuration allocation. Resources and security-scoped file access are released on replacement/shutdown.

## 4. DSP architecture

One custom AUAudioUnit contains up to 128 active native Double-precision biquads with planar Float32 stereo I/O. Direct Q controls and the response graph use the same coefficients. Headroom, master and enabled-module scalar gains are combined before the linear filter cascade; this preserves steady-state transfer response.

A preallocated eight-slot POD snapshot queue publishes coefficients using acquire/release atomics. A 20 ms crossfade between two preallocated render banks smooths changes. DSP-identical metadata edits preserve histories; only a coefficient-identical upstream prefix carries scaled histories into a changed plan. Nonfinite samples and denormals are handled defensively.

The Apple EQ experiment successfully rendered four 32-band AVAudioUnitEQ stages. Its observed maximum-band property changed with configured band count; the experiment proves the tested capacity, not an absolute platform maximum. AURA's processor was selected to meet the full direct-Q contract and coefficient-exact visualization. See [ARCHITECTURE.md](ARCHITECTURE.md) and evidence/apple-eq-32-probe.txt.

Headroom/master gain and overrange indication are **not a true peak limiter**. Arbitrary cascaded boosts/resonances can clip. The graph is calculated filter response, not measured spectrum.

## 5. Build and environment results

| Item | Observed result |
|---|---|
| Host | macOS 27.0.1 (26A434), arm64 |
| Xcode / Swift / SDK | Xcode 27.1 (27A9275), Swift 6.4, macOS 27 SDK |
| Deployment | macOS 15.0, arm64; oldest-OS runtime not separately tested |
| Debug app and XCTest target | Built successfully by final xcodebuild test |
| Release app | BUILD SUCCEEDED; evidence/build-release-menu-icon.txt |
| Project/scheme | Valid Aura project/shared scheme; evidence/xcode-project-list.txt |
| Signing | Local ad hoc signature, no team/Developer ID/notarization |

Initial license and first-launch component blockers were resolved after the Product Owner performed Apple's setup actions. Historical failed attempts remain in evidence/environment-initial.txt, toolchain-recheck.txt and capability-probe-attempt.txt; they are not current blockers. Verified compiler/SDK output is in evidence/toolchain-ready.txt.

The benign AppIntents metadata warning does not prevent the build. No paid identity was fabricated and no notarization upload was performed.

## 6. Tests and acceptance evidence

**32 deterministic tests passed, zero failures**, in both SwiftPM and Xcode. Latest final UI/asset build plus tests: [evidence/xcode-tests-menu-icon.txt](evidence/xcode-tests-menu-icon.txt). SwiftPM result: evidence/swift-tests-handoff.txt. Local Xcode result bundle: build/AuraMenuIconFinalTests.xcresult (ignored generated artifact).

| Suite | Count | Coverage |
|---|---:|---|
| ModelTests | 6 | Exactly four modules, capacity/final-band protection, bounds, independence, IDs and concrete presets |
| PresetStoreTests | 4 | Round-trip/bypass, migration, corrupt recovery, future-version preservation |
| DSPTests | 10 | Literal responses, stability extremes, rendered gain, 128 nonflat bands, bypass crossfade, high-Q histories, metadata and nonfinite input |
| OfflineGraphTests | 3 | Actual player → AU processing of all 128 nonflat bands (+12 dB expected), mono-to-stereo, AU release |
| PlaybackStateTests | 5 | Empty/invalid files, real WAV load, stop, duplicate/stale transport and completion ordering |
| AppStateTests | 4 | Preset CRUD/reset/independence, typing spaces, Nyquist rate change, final flush/relaunch |

Hardware integration used a generated four-second stereo WAV, 48 kHz, containing low-level 120/1000/8000 Hz tones. Real graph checks succeeded on MacBook Pro speakers and subsequently JBL Wave Buds 2: duplicate play, pause/resume, live EQ/module bypass, stop/rewind and natural completion with the engine stopped. The final JBL result is [evidence/engine-validation-delivery.txt](evidence/engine-validation-delivery.txt). These are engine observations, not subjective listening claims.

One earlier JBL run failed a fixed 4.5-second natural-completion deadline (evidence/engine-validation-acceptance.txt). The harness was changed to a duration-plus-five-second deadline with actual-state polling and diagnostic errors. Final completion waited 4.534741 seconds. This demonstrates why the earlier timing assumption was too tight; it is **not** an end-to-end latency measurement or proof of the sole cause of that failure. A separately reproduced completion-token overwrite was fixed with an atomic maximum and a regression test.

Review also identified filter-history transients and an Audio Unit retain cycle. Regression tests reproduced the relevant faults before fixes and now pass. Historical red logs remain in evidence/; they do not indicate the final suite is failing.

| Definition of Done condition | Result / evidence |
|---|---|
| App compiles | PASS — Debug tests and Release build |
| Menu bar works | PASS — Product Owner confirms visible icon and panel opening |
| Main interface works | PASS — native UI inspected; four modules, graph, file picker, presets/settings |
| Four independent EQ stages configured | PASS — model, kernel and actual player/AU tests |
| Settings persist | PASS — atomic storage/flush/relaunch tests; normal GUI relaunch inspected |
| Supported file is audibly processed | PASS — Product Owner: “consegui escutar ele muda o som” |

[evidence/ui-validation.txt](evidence/ui-validation.txt) records native UI observations and the two Product Owner confirmations. Human acceptance is a session statement, not a fabricated recording or instrument measurement. Exact headphone/source/parameter details were not supplied with the listening confirmation.

## 7. Performance observations

- Offline kernel: 128 nonflat bands, 480,000 stereo frames (10 seconds at 48 kHz), one thread: **0.261512166 s wall**, **0.260820 s user CPU**, **13,991,936 bytes peak resident** for the validator process. Timing includes its signal generation/checksum loop. It excludes graph/UI/hardware and does not establish audio latency or whole-app CPU.
- Five one-second-spaced ps observations of the Debug GUI reported **0.0% CPU** each, RSS **142,768–142,784 KiB**; CPU time did not increase in that sample. Playback was not deliberately initiated during sampling, but UI state was not recorded at every sample. This is a short idle observation, not an energy guarantee.
- Instruments Time Profiler captured the offline validator successfully. Local trace: build/aura-kernel-profile.trace; transcript/TOC in evidence/instruments-profile*. No hardware xrun, full allocation or end-to-end latency audit is claimed.

## 8. Known limits and pending decisions

- Human hearing of an EQ change is confirmed. Broad artifact-free listening, extreme/rapid settings, long-duration stress and every module/output combination remain further QA.
- In-flight device removal, sleep/wake and Bluetooth recovery need dedicated hardware acceptance. Successful separate output runs do not prove seamless switching.
- AIFF/compressed codecs, unusual files, macOS 15 runtime, Intel and Universal 2 qualification remain unverified. Invalid files are handled; AVAudioFile decoding does not promise universal codec support.
- Menu icon display/opening is confirmed on this machine. All light/dark states and every display/menu-overflow arrangement were not separately qualified.
- There is no limiter, spectrum analyzer, microphone capture, application capture or global routing in P0.
- Free/open-source output-first roadmap is recorded. P1 report-review gate is still pending; later DSP/routing/distribution work has not started.
- Copyright ownership/authority to release and icon-reference artwork provenance remain **undetermined before publication**.
- Developer ID, notarization, Gatekeeper on a clean Mac and GPL source-delivery arrangements remain future release work. No repository/binary publication or external upload occurred.

## 9. Manual validation and reproduction

1. Open Aura/Aura.xcodeproj, shared Aura scheme; build/run arm64, or use README commands. Current Release bundle: build/DerivedData/Build/Products/Release/AURA.app.
2. At conservative system volume, open a supported local file. The generated build/Validation/AURA-Test-Tones.wav is available after running the validator.
3. Play and compare a selected module's Bass Boost or bell/shelf with that module bypass. Global bypass leaves headroom/master active. Hearing a difference is already confirmed; record exact settings/output if extending the listening audit.
4. Test pause/resume, stop/rewind and natural completion. Open each module; inspect 1–32 bands, enable/bypass, output gains and parameter editing.
5. Save, rename, apply/delete a custom preset; quit normally and relaunch to inspect persistence. Audio files are not automatically reopened.
6. For additional device QA, change output yourself in macOS, verify safe paused status and Play-to-reconnect. Exercise Bluetooth separately and record actual recovery.
7. Record audible artifacts, levels, source, OS/device/rate and reproducible steps. Never treat automated pass results as absence of audible artifacts.

## 10. Recommended next execution package

After review of this report, proceed to **P1 — supported macOS application-output processing**, beginning with a scoped public Process Tap/aggregate feasibility and rollback probe. Preserve four EQ modules/32 bands and the P0 regression suite. Proposed architecture: [docs/P1_ARCHITECTURE.md](docs/P1_ARCHITECTURE.md). Gated tasks: [docs/superpowers/plans/2026-10-17-aura-p1.md](docs/superpowers/plans/2026-10-17-aura-p1.md).

The Product Owner's ordered P1–P4 strategy is authoritative in [AURA_OUTPUT_FIRST_ROADMAP.md](AURA_OUTPUT_FIRST_ROADMAP.md). Microphone/video/multitrack/synchronization directions remain deferred, not cancelled.

## 11. Licensing and Git provenance

Adopted designation: **GPL-3.0-or-later**. LICENSE is the entire unmodified official GPL v3 text, byte-compared against a second official download: 35,149 bytes, SHA-256 3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986. All 35 project Swift source/manifest files carry SPDX notices. LICENSE and third-party notices are bundled by Xcode.

The current dependency inventory contains zero external packages; linked libraries are Apple/system paths. No incompatible external dependency was identified within that limited inventory. Platform terms, source obligations and future dependencies require release-specific review. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [CONTRIBUTING.md](CONTRIBUTING.md), [DISTRIBUTION.md](DISTRIBUTION.md) and evidence/license-audit.json. Ownership is pending; no copyright holder was presumed.

Implementation commit: `d9d96d7cc285390e42d0bdac4aa3fee304e34064` (`feat: deliver validated native AURA P0 under GPL-3.0-or-later`). This report is finalized in a subsequent documentation commit that records the verified source/asset commit. The final handoff reports the documentation commit separately. No remote publication is authorized.
