# AURA

Native macOS application-audio processor, parametric equalizer and local-file player. Swift 6, SwiftUI, Universal 2 (Apple Silicon arm64 and Intel x86_64). Bundle identifier: `com.evoluere.aura`. License: **[GPL-3.0-or-later](LICENSE)**.

**P0 is complete against its stated acceptance criteria.** The Product Owner confirmed menu icon/panel operation and hearing the EQ change the sound. This does not establish artifact-free operation across all settings/devices. See [VALIDATION_REPORT.md](VALIDATION_REPORT.md) for exact evidence and further checks.

**P1 functional acceptance is complete for the tested support envelope, confirmed by the Product Owner.** Human Spotify use for approximately10 minutes, bypass/ordinary Stop and JBL/sleep recovery are confirmed. See [P1 validation](docs/P1_VALIDATION_REPORT.md) for native fault tests, controlled digital timing, the graph-edit crash fix and the limits of user-reported checks versus instrumented physical measurements.

## Features

- Exactly four independent serial EQ modules, each with 1–32 bands: 128 configurable bands total.
- Native double-precision bell, low/high shelf, high/low-pass and notch filters; frequency 20 Hz–20 kHz with sample-rate-aware clamping, gain −24…+24 dB, Q 0.1…30.
- Module enable/bypass/name/output gain, per-band enable, global EQ bypass, input headroom and master gain. A 20 ms DSP-plan crossfade handles live changes without rebuilding the graph.
- Actual AVAudioEngine file playback: open, play, pause/resume, stop/rewind and completion. Mono/stereo sources at 8–192 kHz; WAV and other files AVAudioFile can decode. Unsupported files show an error. Maximum scheduled file length is 4,294,967,295 frames.
- MenuBarExtra window, focusable editor, draggable logarithmic response graph, individual/combined curves, band inspector, presets and settings. The graph is a calculated filter response, not an analyzer.
- Native vector wave identity based on the supplied visual concept, four state-aware menu bar assets, and a generated macOS app icon. Rebuild the ten app-icon sizes and 1×/2×/3× menu images with `swift run AuraIconGenerator`; the original reference image is not altered or bundled.
- Seven real factory presets and local custom preset save/apply/rename/delete. Versioned Codable persistence, atomic writes, corrupt-file quarantine and preservation of unsupported future versions.
- Actual output-overrange indication. **No true peak limiter.** Headroom/master gain cannot guarantee protection from arbitrary boosts across 128 filters.

Choose **Applications** to process supported application output through public Core Audio Process Taps and a private aggregate device. Select all applications or one running audio process, choose the output, then **Start Processing**. The initial capture path requires native stereo Float32 at one matching rate on the same output; unsupported layouts/rates are rejected. AURA excludes its own return, never changes the global default output or volume, and uses no microphone or installed driver. Capture stays unmuted until useful PCM is verified; missing signal returns to ordinary playback.

Choose **Local file** for the preserved P0 file player. Only one source path runs at a time. No network is needed during normal use. Protected content and every application/device combination are not guaranteed.

## Build and run

Development validated with macOS 27.0.1, Xcode 27.1, Swift 6.4 and the macOS 27 SDK. Deployment target: macOS 15.0. Release builds contain arm64 and x86_64; Debug builds the active architecture. Native arm64 tests and x86_64 tests/capture under Rosetta passed. Physical Intel hardware and the oldest supported OS still need separate validation. See the [Universal 2 report](docs/UNIVERSAL2_VALIDATION_REPORT.md).

Open `Aura/Aura.xcodeproj`, select the shared **Aura** scheme and build/run. A paid signing identity is not required for a local ad hoc build.

From the repository root:

```sh
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/AURA.app
```

To build and verify the local Universal 2 Release app:

```sh
zsh Scripts/build-universal.sh
open build/Universal2/DerivedData/Build/Products/Release/AURA.app
```

The script verifies both architectures, the macOS 15 minimum, bundled license/notices and the local ad hoc signature. It writes `build/Universal2/verification.json` only after verification succeeds. The tracked project generator is `python3 Scripts/generate-project.py`.

The editor opens on launch and remains accessible from **Open Equalizer** in the menu bar. The app has no permanent Dock icon. For file playback choose **Local file**, use **Open File**, then Play; choose a module and edit its bands or apply a preset. A default −6 dB input pad and −6 dB master gain provide initial headroom. EQ bypass leaves those gain controls in effect.

Settings are stored at `~/Library/Application Support/com.evoluere.aura/configuration.json`. The audio file itself is not copied or restored automatically after relaunch. Version 3 settings retain source/output UID and application bundle hints, never transient HAL IDs; capture never starts automatically after relaunch.

## Tests and validation tools

```sh
swift test
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
swift run -c release AuraValidation --benchmark --play
```

The validation executable generates a clearly identified four-second test-tone WAV under `build/Validation/`. `--play` sends that file through the real graph to the current output; `--benchmark` measures 128 nonflat bands offline. It does not adjust system volume or routing. Its benchmark is not a hardware latency measurement or a whole-app CPU figure.

`Validation/EQCapabilityProbe.swift` separately investigates Apple's EQ implementation through actual offline rendering. The production engine uses AURA's own biquads to implement direct Q controls and a coefficient-exact response graph.

## License and governance

The Product Owner selected **GPL-3.0-or-later**. LICENSE contains the complete, unaltered official GPL v3 text; project source files carry `SPDX-License-Identifier: GPL-3.0-or-later`.

Copyright ownership and authority to release remain **pending determination**. No individual or company is presumed to own the entire project. Repository publication, external uploads and binary distribution require explicit authorization; none has been performed. Local builds are development artifacts, not published releases.

Read [CONTRIBUTING.md](CONTRIBUTING.md), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), and [DISTRIBUTION.md](DISTRIBUTION.md). The current package has no external dependencies. Independent macOS signing/notarization is prepared as a future process and has not been submitted to Apple.

Audio ownership, real-time constraints, DSP decisions and Core Audio capture ownership and recovery are documented in [ARCHITECTURE.md](ARCHITECTURE.md).

## Product roadmap

The Product Owner's [output-first roadmap](AURA_OUTPUT_FIRST_ROADMAP.md) prioritizes P1 system output processing, P2 professional DSP, P3 advanced output routing and P4 Intel/Apple Silicon/Universal 2 optimization and distribution. The product remains free and open source, with no subscriptions, paid features or artificial feature restrictions. Microphone/video/multitrack features are deferred. The Product Owner authorized P1 after P0 acceptance. P1 capture and controls have functional acceptance for the tested envelope; [architecture](docs/P1_ARCHITECTURE.md), [execution package](docs/superpowers/plans/2026-10-17-aura-p1.md), and [report](docs/P1_VALIDATION_REPORT.md) record that boundary. A subsequent explicit instruction brought Universal 2 build preparation forward: the dual-architecture artifact is verified, while physical Intel and broader P4 qualification remain pending. Optional neural modules are a future architectural decision only; no models or heavy dependencies were added.
