# AURA — NATIVE macOS AUDIO ENGINE
## MASTER EXECUTION PROMPT — P0 FOUNDATION & AUDIO ENGINE

**Product:** AURA  
**Platform:** macOS / Apple Silicon  
**Language:** Swift 6  
**UI:** SwiftUI  
**Audio:** Core Audio / AVFoundation / Accelerate  
**Architecture:** Native, modular, offline-first  
**Bundle Identifier:** `com.evoluere.aura`

---

# 1. ROLE & RESPONSIBILITY

Act as a multidisciplinary engineering team consisting of:

- Principal macOS Engineer
- Core Audio / DSP Engineer
- SwiftUI Interface Architect
- Software Quality Engineer
- Performance Engineer
- Apple Platform Specialist

Your mission is to design and implement AURA, a professional native macOS audio equalizer.

You have authorization to create and modify the project, organize its architecture, implement source code, execute builds and tests, and correct implementation errors.

Do not ask for confirmation for ordinary implementation decisions.

Do not install system-level audio drivers, modify global audio routing, or make changes outside the project without explicit authorization.

**The application must actually process audio. It must not be a visual-only prototype.**

---

# 2. PRODUCT VISION

AURA is a professional-grade audio equalization application designed specifically for macOS.

Its objectives are:

1. Provide precise audio equalization.
2. Integrate naturally with macOS.
3. Operate from the system menu bar.
4. Support four independent equalizer modules.
5. Support up to 32 parametric bands per module.
6. Provide a visual frequency-response editor.
7. Maintain low CPU and memory consumption.
8. Deliver reliable audio processing with minimal latency.
9. Preserve user settings locally.
10. Prepare the architecture for future system-wide audio processing.

Design principle:

**Professional audio engineering. Effortless native experience.**

---

# 3. NON-NEGOTIABLE REQUIREMENTS

The application must:

- Be developed entirely in Swift.
- Use SwiftUI for its interface.
- Run natively on Apple Silicon.
- Use official Apple frameworks wherever practical.
- Not use Electron, Chromium, WebView or JavaScript runtimes.
- Not require Docker, Node.js or a backend.
- Not require an internet connection during normal operation.
- Not introduce unnecessary third-party dependencies.
- Keep audio processing independent from UI rendering.
- Use predictable and documented state management.
- Implement proper error handling.
- Avoid blocking operations on real-time audio threads.
- Never show simulated audio measurements as if they were real.
- Avoid unnecessary energy consumption while idle.
- Respect macOS audio permissions and security mechanisms.

Use the macOS version and available Xcode SDK detected on the development machine. Do not assume SDK compatibility.

---

# 4. DEVELOPMENT ENVIRONMENT DISCOVERY

Before creating the project, execute:

```bash
sw_vers
uname -m
xcodebuild -version
swift --version
xcode-select -p
```

Determine:

- Installed macOS version.
- Processor architecture.
- Xcode version.
- Available SDKs.
- Swift toolchain.
- Required deployment target.
- Build and code-signing configuration.

If Xcode is not installed or correctly configured, explain the blocker and provide the minimal required installation instructions.

Do not silently install large dependencies.

---

# 5. PROJECT STRUCTURE

Create the project with a structure similar to:

```text
Aura/
├── Aura.xcodeproj
├── Aura/
│   ├── App/
│   │   ├── AuraApp.swift
│   │   ├── AppState.swift
│   │   └── AppCommands.swift
│   ├── Models/
│   │   ├── EqualizerModule.swift
│   │   ├── EqualizerBand.swift
│   │   ├── EqualizerPreset.swift
│   │   └── AudioConfiguration.swift
│   ├── Audio/
│   │   ├── AudioEngineManager.swift
│   │   ├── EqualizerProcessor.swift
│   │   ├── AudioGraphManager.swift
│   │   ├── FrequencyResponseCalculator.swift
│   │   └── AudioDeviceManager.swift
│   ├── Views/
│   │   ├── MenuBarView.swift
│   │   ├── EqualizerWindow.swift
│   │   ├── EqualizerGraphView.swift
│   │   ├── EqualizerModuleView.swift
│   │   ├── BandInspectorView.swift
│   │   ├── PresetView.swift
│   │   └── SettingsView.swift
│   ├── Persistence/
│   │   └── PresetStore.swift
│   └── Resources/
├── AuraTests/
├── README.md
├── ARCHITECTURE.md
└── VALIDATION_REPORT.md
```

Adjust the structure if necessary for a clean and maintainable architecture.

Avoid unnecessary abstraction and placeholder files.

---

# 6. FOUR-INDEPENDENT-EQ ARCHITECTURE

AURA must provide exactly four available EQ modules.

Each module must support:

- Independent enable/disable.
- Independent bypass.
- Editable name.
- Between 1 and 32 active bands.
- Frequency controls.
- Gain controls.
- Q factor controls.
- Filter type selection.
- Individual output gain.
- Individual presets.
- Reset functionality.
- Persistent configuration.

Audio signal chain:

```text
Audio Input
    |
    v
EQ MODULE 1 — Up to 32 bands
    |
    v
EQ MODULE 2 — Up to 32 bands
    |
    v
EQ MODULE 3 — Up to 32 bands
    |
    v
EQ MODULE 4 — Up to 32 bands
    |
    v
Master Gain
    |
    v
Audio Output
```

Maximum theoretical configuration:

**4 EQ modules × 32 bands = 128 configurable bands.**

Do not assume that AVAudioUnitEQ supports all required configurations.

Investigate its actual capabilities using the installed SDK and executable tests.

If AVAudioUnitEQ cannot meet the requirements reliably, design an alternative using native DSP filters.

Do not implement 128 independent Audio Unit nodes when a more efficient architecture is possible.

---

# 7. PARAMETRIC EQUALIZATION

Each band must support, where implemented:

- Peak / Bell
- Low Shelf
- High Shelf
- High-Pass
- Low-Pass
- Notch

Target parameter ranges:

| Parameter | Target |
|---|---|
| Frequency | 20 Hz to 20 kHz |
| Gain | -24 dB to +24 dB |
| Q Factor | 0.1 to 30 |
| Bands per module | 32 |
| EQ modules | 4 |

Validate the actual supported ranges of the selected DSP implementation.

Clamp parameters safely, including frequencies relative to the current sample rate and Nyquist limit.

Do not expose unsupported parameters as functional controls.

Audio parameter changes should avoid audible clicks and discontinuities.

Implement parameter smoothing where necessary.

---

# 8. REAL AUDIO ENGINE

Use AVAudioEngine as the initial audio graph coordinator.

The P0 engine must support:

1. Selecting a local audio file.
2. Loading the file safely.
3. Playing audio.
4. Pausing audio.
5. Stopping audio.
6. Processing audio through all four EQ modules.
7. Editing EQ parameters during playback.
8. Bypassing individual EQ modules.
9. Applying master gain.
10. Outputting processed audio to the selected system output.

Choose supported audio formats through the native macOS file picker.

Handle:

- Unsupported formats.
- Missing files.
- Sample-rate changes.
- Audio engine startup failures.
- Output device changes.
- Playback completion.
- Repeated playback requests.
- Resource cleanup.

Do not perform disk I/O, blocking locks, UI calls or dynamic memory allocation inside a real-time audio callback.

Use the audio engine's supported scheduling and parameter APIs.

Avoid audio graph reconstruction during ordinary parameter changes.

---

# 9. SYSTEM AUDIO — FUTURE ARCHITECTURE

The long-term objective is processing audio from macOS applications, including:

- Apple Music
- Spotify
- Safari
- Chrome
- Other supported applications

Research Apple Core Audio Process Taps and relevant routing mechanisms.

Document:

- Required APIs.
- macOS compatibility.
- Audio capture permissions.
- Process and device selection.
- Audio duplication prevention.
- Output routing.
- Feedback prevention.
- Latency implications.
- Potential limitations with protected audio.
- Differences between physical and Bluetooth outputs.

**Do not implement system-wide capture or routing in P0.**

Provide a technical feasibility assessment in `ARCHITECTURE.md`.

Do not promise universal application compatibility without validation.

---

# 10. MENU BAR APPLICATION

AURA must operate as a menu bar application.

Use SwiftUI `MenuBarExtra` with `.window` presentation where appropriate.

The menu bar interface must include:

- AURA identity/icon.
- Global processing enable/disable.
- Actual audio engine status.
- Four EQ modules with individual bypass.
- Active preset.
- Master gain.
- Current audio output information.
- Open Equalizer button.
- Settings access.
- Quit application.

The icon must visibly communicate:

- Processing enabled.
- Processing bypassed.
- Audio engine stopped.
- Processing error.

Do not claim that the system audio is being processed when only the internal file-player engine is active.

The menu bar must remain responsive while processing audio.

Prefer a menu-bar-only experience, without a permanent Dock icon, while ensuring the main window is accessible and focusable.

---

# 11. MAIN WINDOW — NATIVE AUDIO WORKSTATION

Implement an elegant, professional SwiftUI interface.

Visual direction:

- Native macOS design.
- Dark graphite and restrained neutral surfaces.
- Subtle translucent panels where appropriate.
- High-quality typography.
- SF Symbols.
- Minimal decorative elements.
- Excellent information hierarchy.
- Smooth, lightweight animations.
- Clear focus and selection states.

Do not imitate a web dashboard.

Use native macOS controls and patterns.

Main interface:

**Left sidebar**

- EQ 1
- EQ 2
- EQ 3
- EQ 4
- Presets
- Settings

**Main workspace**

- Selected EQ name.
- Enable/bypass control.
- Parametric frequency-response graph.
- Active band markers.
- Frequency-response grid.
- Individual band controls.
- Filter selection.
- Gain and Q controls.
- Preset selection.
- Module output gain.

**Footer**

- Audio engine state.
- Playback state.
- Sample rate.
- Output device.
- Master gain.

Present measured data only when actual audio measurements are available.

---

# 12. INTERACTIVE FREQUENCY RESPONSE

Implement a native frequency-response visualization using SwiftUI Canvas or an appropriate native rendering API.

Requirements:

- Logarithmic frequency axis.
- Frequency range from 20 Hz to 20 kHz.
- Gain axis in decibels.
- Visible zero-dB line.
- Movable EQ control points.
- Selected-band highlighting.
- Individual filter response.
- Combined module response.
- Optional response across all four EQ modules.

Use a mathematically appropriate frequency-response calculation for the actual filters.

Do not create arbitrary decorative curves.

If AVAudioUnitEQ does not expose coefficients needed for an exact match, document the limitation and distinguish any approximate preview from verified DSP response.

Dragging a control point should update the corresponding audio parameter.

Use controlled UI update rates to avoid overwhelming the audio engine.

---

# 13. PRESETS & PERSISTENCE

Implement local persistence using Codable and an appropriate application support directory.

Requirements:

- Save EQ settings.
- Restore EQ settings after relaunch.
- Save custom presets.
- Rename presets.
- Delete custom presets.
- Reset individual EQs.
- Reset the entire configuration.
- Handle corrupted configuration files.
- Version serialized configuration data.

Initial presets:

- Flat
- Bass Boost
- Vocal Clarity
- Warm
- Bright
- Music
- Cinema

Presets must contain actual filter parameters rather than placeholder labels.

Avoid overwriting user-created presets during updates.

---

# 14. AUDIO SAFETY & PERFORMANCE

Implement:

- Input/headroom control.
- Master gain.
- Gain clamping.
- Protection against invalid parameters.
- Safe bypass transitions.
- Proper cleanup on stop.
- Recovery from audio engine failure.

Document the difference between a gain control and a true peak limiter.

Do not label simple gain reduction as limiting.

A real limiter may be implemented in a later package if the required DSP and testing are not ready.

Performance objectives:

- Responsive UI during playback.
- Stable processing with all four modules active.
- No avoidable audio-thread blocking.
- No audible artifacts during ordinary adjustments.
- Minimal CPU usage when idle.
- No persistent audio processing while no source is playing.

Measure actual CPU, memory and audio behavior instead of inventing benchmark results.

---

# 15. QUALITY ASSURANCE

Implement automated tests where practical.

Required test categories:

**Model Tests**
- Exactly four modules.
- Maximum 32 bands per module.
- Band parameter bounds.
- Independent module state.
- Bypass persistence.

**Preset Tests**
- Save and restore.
- Data migration/version handling.
- Invalid/corrupted file recovery.

**DSP Tests**
- Flat response.
- Peak-filter response.
- Shelf-filter response.
- Combined filter response.
- Numeric stability at supported frequencies.

**Audio Engine Tests**
- Initialization.
- Audio graph configuration.
- Parameter application.
- Playback state management.
- Failure handling.

Separate deterministic unit tests from hardware-dependent integration tests.

Do not claim automated tests prove the absence of audible artifacts.

---

# 16. BUILD & VALIDATION

Complete the following:

1. Generate a valid Xcode project.
2. Compile for Apple Silicon.
3. Resolve compiler errors.
4. Run available automated tests.
5. Launch the application.
6. Verify menu bar behavior.
7. Verify the main window opens.
8. Verify the four EQ modules exist.
9. Verify settings persist.
10. Verify real audio processing with a supported test file.

Use Instruments for profiling where feasible.

If manual speaker/headphone listening is required, document that it remains unverified until the Product Owner performs the test.

Do not mark a feature PASS without adequate evidence.

---

# 17. EXECUTION ORDER

Proceed in this order:

**P0-A — Environment & Project**
- Inspect environment.
- Create Xcode project.
- Configure app lifecycle.
- Establish architecture.

**P0-B — Models & Persistence**
- Implement four EQ modules.
- Implement 32-band capacity.
- Implement presets.
- Implement configuration storage.

**P0-C — Audio Engine**
- Build real audio graph.
- Connect four EQ stages.
- Implement playback.
- Implement live parameters and bypass.

**P0-D — Native Interface**
- Implement menu bar.
- Implement main window.
- Implement EQ editor.
- Implement response graph.

**P0-E — Validation**
- Execute build.
- Execute tests.
- Profile where possible.
- Correct identified defects.
- Document remaining limitations.

Do not advance to system-wide audio capture in this execution package.

---

# 18. GOVERNANCE & DELIVERY

The project must remain maintainable and auditable.

Use Git with meaningful commits.

Do not overwrite an existing unrelated project.

Before modifying an existing repository, inspect its current status and preserve unrelated work.

Do not fabricate tests, measurements, screenshots or evidence.

Do not silently downgrade product requirements.

If a technical limitation prevents implementation, document:

- The limitation.
- Evidence supporting it.
- Alternatives.
- Recommended solution.
- Impact on the roadmap.

Final report must contain:

1. Summary of implemented features.
2. Files created or modified.
3. Audio architecture.
4. DSP architecture.
5. Build results.
6. Test results.
7. Performance observations.
8. Known issues.
9. Manual validation instructions.
10. Recommended next execution package.
11. Git commit hash.

**Definition of Done:**

P0 is complete only when the app compiles successfully, its menu bar and main interface work, the four independent EQ stages are configured, local settings persist, and at least one supported audio file is audibly processed through the EQ chain.

If any condition is not met, report P0 as incomplete with precise blockers.

---

# 19. START EXECUTION

Begin immediately.

First inspect the development environment, then create the AURA project and implement the execution package.

Make reasonable engineering decisions independently, but preserve all non-negotiable product requirements.

Prioritize correct DSP behavior, native integration, maintainability and reliability over visual polish.

**AURA — Precision in every frequency.**
