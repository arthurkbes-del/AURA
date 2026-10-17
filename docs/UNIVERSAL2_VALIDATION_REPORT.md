# AURA — Universal 2 preparation

2026-10-17. Product Owner instruction: “quero que ele rode nos Macs Intel também, vamos preparar a versão Universal 2”. Branch: `codex/aura-universal2`, based on P1 acceptance `9248673`. Build implementation: `8dab812`. This pulls the architecture-build portion of P4 forward; P0/P1 functionality, P2 priorities and publication restrictions remain in place.

**Result: a local Universal 2 Release .app is built and verified, with arm64 and x86_64 code.** Native Intel hardware qualification remains pending. No claim of support for every Intel Mac or macOS version follows from this build.

## Artifact and build contract

- Local app: `build/Universal2/DerivedData/Build/Products/Release/AURA.app`.
- `ARCHS = $(ARCHS_STANDARD)`, resolving here to arm64/x86_64. Debug builds the active architecture; Release builds both. No exclusion or runtime feature restriction is applied to Intel.
- Deployment minimum remains **macOS 15.0** in Info.plist and both Mach-O slices.
- One executable contains the shared conventional audio implementation, four independent EQ modules and up to128 bands. No neural model, heavy package, new DSP or permission change was added.
- Local **ad hoc** signing; not Developer ID, not notarized, not a released distribution.
- LICENSE and THIRD_PARTY_NOTICES.md are bundled byte-for-byte from project source. GPL-3.0-or-later remains selected; copyright ownership/artwork provenance remain pending before publication.

Apple recommends Standard Architectures and documents Rosetta execution for the Intel slice on Apple Silicon: [Building a universal macOS binary](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary). The actual local bundle, rather than build settings alone, is inspected for both architectures.

## Reproduce locally

```sh
zsh Scripts/build-universal.sh
```

The script builds Release for generic macOS, removes its own stale verification marker before starting, then verifies the actual bundle. Results are written to `build/Universal2/verification.json`. Nothing is uploaded or distributed. The running P1 app and its settings are not replaced by this separate output path.

`Scripts/verify-universal.py` checks the executable and bundled Mach-O files, both architecture slices and deployment minima, bundled notices and the ad hoc signature. It fails on the previous arm64-only bundle and on the x86_64-only Debug test app; these are real negative artifact checks, not checks of configuration strings. This artifact contains one bundled Mach-O executable; its AuraCore code is linked into it. Platform frameworks are linked from macOS, not vendored.

`Scripts/generate-project.py` is the tracked canonical project generator, replacing the formerly ignored development copy. It derives the root from its own path; generation from `/tmp` produced identical project and scheme files. Regeneration preserves Universal 2 settings.

## Validation evidence

Host: Apple Silicon, macOS27.0.1, Xcode27.1/Swift6.4/macOS27 SDK. Rosetta was already available; no installation or system-setting change was required.

| Check | Actual result | Evidence under `evidence/universal2/` |
|---|---|---|
| Universal Release | Build succeeded, arm64+x86_64, minimum15.0 each | `release-final-build.txt`, `bundle-verification.json` |
| Thin-bundle rejection | Existing arm64-only and x86_64-only .apps rejected | `thin-bundle-red.txt`, `thin-intel-bundle-rejected.txt` |
| Native arm64 regression suite |61 core+3 measurement tests,64 total,zero failures | `arm64-final-package-tests.txt` |
| x86_64 Xcode suite under Rosetta |61 core tests,zero failures; test bundle is x86_64-only | `x86-xcode-tests.txt`, `test-runtime.json` |
| x86_64 HAL integration under Rosetta | Actual controlled source capture,128 nonflat bands,+6dB integration check,live bypass and cleanup pass | `x86-native-session.txt`, `rosetta/native-session-result.json` |
| Generator reproducibility | Project/scheme unchanged when generating outside project cwd | `generator-idempotence.json` |
| Signature/notices | Both slices verified; local ad hoc; license/notices match | `bundle-verification.json` |

The x86_64 integration observed135,168frames over3.14seconds at44.1kHz on MacBook Pro speakers. Invalid buffers0,missing input0,HAL overload events0,timestamp discontinuities1. The timestamp gap is reported, not interpreted as zero audible dropouts. This is a bounded translated-runtime integration check, not an Intel hardware latency/performance or long-stability measurement. The standalone source fixture was controlled; no captured PCM was saved. `--output-dir` keeps architecture evidence separate from historical P1 results.

The build's linked libraries are inventoried in `linked-platform-libraries.txt`. No external package, driver or neural model was added. Swift/Python/Xcode are development tools; Python code is not bundled in AURA.

## Reproduce architecture tests

```sh
swift test
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath build/Universal2/Tests-x86 test

zsh Validation/run-process-tap-probe.sh --compile-only
swift build -c release --arch x86_64 --scratch-path build/Universal2/SPM-x86 \
  --product AuraSystemValidation
TASK_X86_BIN_DIR="$(swift build -c release --arch x86_64 \
  --scratch-path build/Universal2/SPM-x86 --show-bin-path)"
arch -x86_64 "$TASK_X86_BIN_DIR/AuraSystemValidation" \
  --selected-only --seconds 3 --output-dir evidence/universal2/rosetta
```

On this Apple Silicon host, the x86_64 test execution is Rosetta. It does not become physical Intel evidence because the bundle has Intel code. Keep exit status and current run log alongside the result JSON.

## Independent review and remaining qualification

One read-only review of the immutable build change found **no Critical or Important issue**. A Minor inherited validation-tool issue is deferred: reusing a session output directory can retain a previous success JSON after a failed run, or an incomplete JSON after success. This run used a fresh architecture-specific directory and checked the process exit status/current log; the Universal app verifier clears its own marker before every build. Cost if deferred: future users who inspect only an old session JSON could misattribute it to a later failed run. Do not use JSON alone as a run-success signal.

The reviewer did not independently build/run the artifact and declined physical Intel operation, physical latency/listening, distribution readiness and independent regeneration. Those limits are retained; the executor's actual build/test/regeneration evidence is listed above.

Before claiming hardware qualification, test the generated .app on an actual compatible Intel Mac, including macOS15, audio permission flow, application capture, four32-band modules, device/format changes, Bluetooth, sleep/restart and extended stability. Existing arm64 P1 human acceptance is preserved; Rosetta does not establish those Intel-specific outcomes. Universal 2 does not lower the current macOS15 minimum.

P4 still owns broad architecture/hardware/performance/accessibility and distribution qualification. Developer ID/notarization, ownership and source/binary publication require their existing explicit authorization. No public repository, external upload, binary distribution or P2 feature was started by this work.
