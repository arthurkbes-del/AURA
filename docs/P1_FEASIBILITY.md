# P1 feasibility findings

2026-10-17. Development experiment on macOS 27.0.1, Xcode 27.1, Swift 6.4; arm64 runtime, macOS15 deployment. P1 is authorized by the Product Owner's instruction after P0 handoff. Scope clarification: application output; microphone/line input remain deferred.

## Observed topology

`Validation/ProcessTapProbe.swift` launches a separate controlled source process (stereo 1 kHz, amplitude 0.001), creates a private process tap, then one private aggregate containing that tap and the current physical output. Physical input channels are disabled and aggregate input is verified stereo-only before I/O. Callback output is half the captured amplitude. Global macOS output selection and volume are not changed.

The generic stereo-mixdown tap reported 48 kHz while the current MacBook Pro output ran at 44.1 kHz. The aggregate retained different stream rates. The probe rejected this safely and destroyed both resources; drift compensation alone must not be assumed to convert exposed buffer formats.

A device/stream-scoped process tap reported 44.1 kHz, matching the physical-output aggregate. Actual final result: 364 blocks, 186,368 frames, nonzero captured energy 0.18631501998878386, output gain exactly 0.5, no invalid buffers, output peak 0.00049999274779111147. See evidence/p1/probe-nonisolated.txt and probe-result.json. These values establish real signal capture/rendering; they are not end-to-end latency or proof of absence of an audible dry path.

Production should initially capture a selected output stream and return processed audio to that same device, with optional application selection or all applications except AURA. This supports a coherent clock without silently changing device rates. Cross-device routing/resampling requires independent evidence; keep it explicit as unimplemented until verified, rather than claiming arbitrary source/output pairs.

## Lifecycle and callback findings

Installed public SDK declares process tap create/destroy APIs available from macOS14.2; current deployment remains15. The [Apple sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) documents private taps/aggregate input, permission rationale and mute behavior. Use mutedWhenTapped so muting follows active consumption. Scope to selected sources and exclude AURA before any output starts.

An initial IOProc block inherited MainActor isolation from its construction context and crashed on the HAL thread. The extracted stack is preserved in evidence/p1/probe-actor-crash.json. Constructing an explicitly Sendable block in a nonisolated function removed that assertion; the corrected probe passed. This must be preserved at the production callback boundary.

Normal Stop/DestroyIOProc and aggregate/tap destruction succeeded with OSStatus0. Earlier guarded-format failures rolled back successfully. The accidental actor-assertion crash exercised process exit, but restoration of physical dry audio was not measured or human-confirmed; no crash-safety PASS is claimed. Keep forced-exit/device-loss/dry-duplication listening in acceptance QA. Only owned private resources may be destroyed.

Capture returned nonzero PCM in this development host. No fresh permission prompt was observed during the successful run; that does not establish clean-machine permission behavior or distribution signing requirements. Denial/revocation still need isolated tests and hardware acceptance.

## Reproduce and limits

Run `zsh Validation/run-process-tap-probe.sh` from the repository. It builds local arm64 and x86_64 probes, signs the .app ad hoc and runs arm64 against the current output; it does not publish anything. Use `--compile-only` to avoid capture. The controlled source may be faintly audible before/after the tap. No PCM capture recording is saved.

P0's 32 tests still pass (evidence/p1/baseline-tests.txt). Probe compilation succeeded for x86_64, without Intel execution. Not qualified yet: all-app self-exclusion, protected content, device loss, Bluetooth, multichannel/exotic formats, cross-device routing, long-run stability, latency, GUI permission/cleanup and human listening. Production session/bridge tests can proceed using this verified same-output topology while those acceptance checks remain pending.
