# P1 local acceptance reproduction

Run from the project root on the development Mac. No publication, model download, third-party driver or microphone capture is involved. Do not reset system privacy databases. Preserve evidence from failed/interrupted runs.

## Build the controlled fixture and tools

```sh
zsh Validation/run-process-tap-probe.sh --compile-only
swift build -c release --product AuraSystemValidation
swift test
```

The compile-only script generates the local source fixture at build/P1/AURATestSource. It supports the explicitly verified PRBS marker protocol; an old tone-only fixture must not qualify as a timing marker. Tests cover known positive/negative shifts, amplitude changes, silence, unrelated signals and ambiguous periodic tones. No captured PCM is saved.

## Native lifecycle and rates

```sh
.build/release/AuraSystemValidation --acceptance --rate-change
```

This starts a quiet controlled source, checks20 native128-band start/stop cycles and caller-visible resource baselines, actual selected-source exit/restart, production sleep-listener delivery and a capturing worker SIGKILL/restart. The opt-in rate test operates only on an advertised/settable built-in output, verifies44.1/48kHz changes and restores the exact prior rate. It does not switch the global default output or change volume. Physical sleep/reconnect and auditory dry restoration are separate observations.

## Stability and relative digital timing

```sh
caffeinate -i .build/release/AuraSystemValidation --seconds 300 --selected-only
.build/release/AuraSystemValidation --digital-latency
```

The selected-source soak avoids treating unrelated personal audio as part of a quiet global fixture. It checks session progress/levels/format every100ms with128 active nonflat filters. For both selected/global controlled scopes, omit --selected-only and pause unrelated audio first; otherwise the level guard may stop the experiment. An interrupted or contaminated run is INCOMPLETE, not PASS. The idle-sleep assertion lasts only while the soak child runs; manual sleep still terminates processing safely.

The digital experiment uses two private process taps and a capture-only observer. It checks native-endian Float32 formats, a broadband source handshake and a unique correlation peak before reporting relative marker displacement. Observer Stop/IO/aggregate/tap releases are checked before completion. This includes observer alignment/conversion effects and excludes DAC/acoustics/Bluetooth transmission; it is not an observer-independent physical AURA latency.

## macOS permission test — reproduction checklist

Use the existing AURA permission in System Settings → Privacy & Security → Screen & System Audio Recording → System Audio Recording Only. Touch only AURA; leave Codex/ChatGPT/other apps' permissions unchanged. Authentication, if requested, is performed by the user in macOS.

1. With Spotify playing and AURA processing, turn off AURA's system-audio permission. Record whether macOS quits/restarts AURA and whether ordinary audio continues without echo.
2. While AURA remains denied, reopen it and try Start Processing. It must not silence ordinary playback or falsely report useful processed signal; record the visible status/error. Silence alone is not proof of permission denial.
3. Restore the same AURA permission, comply with any required app restart, then explicitly Start Processing. Confirm EQ/bypass difference and normal Stop restoration.
4. Record the exact OS/build, output, source, status, audible result and whether grant/revocation took effect immediately or required relaunch. Do not mark the clean-host first-grant prompt tested on this already-authorized host.

On2026-10-17 the user initially could not disable permission, then confirmed the remaining tests as OK. Treat that later result as human acceptance; the agent did not observe the toggles or change permissions. Keep this checklist for reproducible future qualification.

## Physical timing and release qualification

A physical end-to-end delay requires a specified independent reference and loopback/measurement setup. No microphone/line feature is authorized by this runbook. USB/Intel/oldest OS, broad output-mode qualification, energy/accessibility and Developer ID/notarization remain separate qualification work. GPL-3.0-or-later and ownership/artwork/publication gates remain in force.
