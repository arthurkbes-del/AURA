# AURA P0 design brief

Date: 2026-10-17. Authority: the Product Owner's supplied master execution prompt, preserved in `docs/MASTER_EXECUTION_PROMPT.md`.

## Intent and execution authority

Build a maintainable, offline native macOS audio equalizer whose actual local-file processing can be verified. The user explicitly authorizes ordinary implementation decisions and asks for immediate execution; additional design approval is not a prerequisite. No system changes, global routing, driver installation, or system-wide capture are authorized.

## Scope and architecture

Swift 6, SwiftUI, AVFoundation, AudioToolbox, Core Audio, Foundation; no third-party dependencies. Exactly four serial EQ modules, 1–32 bands each. A main-actor observable app state owns configuration and communicates with an independent audio controller. UI rendering and persistence never run inside audio callbacks.

Implemented graph: file player → mono/stereo normalization mixer → one AURA Audio Unit with headroom, four logical 32-band native biquad modules and master gain → main mixer → system-selected output. Idle and stopped states do not render continuously. Output selection means following the output selected in macOS; the app does not mutate the global default device.

Before selecting the implementation, query Apple's maximum band count and validate four 32-band stages by offline rendering. Apple's EQ uses octave bandwidth, not direct Q. Verify the conversion, range coverage, supported filter parameters, response coefficients, and safe transitions. If it cannot meet the target frequency 20–20,000 Hz, gain −24…+24 dB, and Q 0.1…30 contracts, implement native biquads in a dedicated audio processor instead of reducing the requirement. Do not create 128 Audio Unit nodes.

Use sample-rate-aware frequency clamping below Nyquist. For unsupported parameter combinations, disable the control and explain it. A response derived from Apple's coefficients must be compared against offline rendering; otherwise identify the preview as approximate. Never show a response curve as a measured spectrum.

## State, persistence, and playback

Versioned Codable value models enforce exactly four modules, band capacity, finite numeric bounds, stable identifiers, independent enabled/bypassed state, output gains, and preset references. Persistence uses Application Support, atomic writes off the audio thread, debounced changes, schema version handling, and recoverable corrupt-file quarantine. Unknown future versions are preserved rather than overwritten. Seven factory presets hold actual parameters; user presets retain identity and survive app updates.

Playback has empty, ready, playing, paused, stopped, completed, and failed states. Repeated play is idempotent. A generation token rejects stale scheduling completions after stop/reload. Pause/resume retains position; stop resets position. Loading and decode failures preserve a usable controller. Device or sample-rate changes trigger a controlled stop/reconnect outside audio callbacks and a visible status. Security-scoped file access is balanced with resource cleanup.

## Interface

MenuBarExtra uses window presentation and four generated native wave image assets for processing/bypass/stopped/error. A custom shape label was replaced after an invisible-icon report; the Product Owner confirmed the native image appears and opens the panel. LSUIElement avoids a permanent Dock icon; opening the editor explicitly activates its window. The menu includes actual engine status, processing bypass, four module bypasses, preset, master gain, output, settings, and quit. Every playback surface says local-file audio.

The main window has four EQ module sidebar entries plus presets and settings. The selected module shows name, enable/bypass, draggable logarithmic response graph, selected-band inspector, filter choice, band add/remove, preset management, and module gain. Footer shows actual engine/playback state, rate, output, and master gain. Graph drags are coalesced to a controlled update rate. No animated fake analyzer.

## Acceptance

Build and test on the detected Apple Silicon toolchain. Unit tests cover models, preset storage, migration/corruption, filter response and stability. Offline rendering verifies real graph gain, bypass, and all-stage composition independently of hardware. Device-dependent playback and UI checks are recorded separately. A human must listen to a supported file before the audible-processing criterion is satisfied; automated tests do not prove freedom from audible artifacts. CPU, memory, latency, and listening remain unclaimed until measured.

## Final outcome and later packages

The initial license/first-launch toolchain blockers were resolved by the Product Owner. Swift 6.4, Xcode 27.1/macOS 27 SDK builds and 32 deterministic tests pass on arm64; deployment target is macOS 15. Apple EQ probing established tested 32-band capacity, but its octave bandwidth does not cover the requested direct-Q contract, so production uses native coefficients and an exact response graph.

The Product Owner confirmed audible processing ("consegui escutar ele muda o som"). P0 meets its Definition of Done within the scope documented in VALIDATION_REPORT.md; exhaustive artifact, device, codec, oldest-OS and Intel qualification remain further QA. GPL-3.0-or-later governance, undetermined copyright/artwork ownership and no-publication restrictions are documented separately.

AURA_OUTPUT_FIRST_ROADMAP.md sets output processing first. P1 architecture/execution preparation is documentation only; P1 has not started and still requires review of the final P0 report.
