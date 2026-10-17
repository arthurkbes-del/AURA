# AURA

Native macOS parametric equalizer foundation. Bundle identifier: `com.evoluere.aura`.

**P0 status: incomplete — development toolchain blocked by Xcode license acceptance. No application has been built or delivered.**

The requested product is a Swift 6 / SwiftUI menu bar application that plays a local file through four independent EQ modules, each supporting up to 32 bands. System-wide capture and routing are outside P0.

## Unblock development

In your own Terminal, run:

```sh
sudo xcodebuild -license
```

Review Apple's agreement and accept it if you agree. The developer must do this; this repository does not accept licenses, request credentials, or change system configuration.

Then verify:

```sh
sw_vers
uname -m
xcodebuild -version
swift --version
xcode-select -p
xcodebuild -showsdks
```

If Xcode subsequently requests first-launch components, open Xcode and finish its setup. No additional dependency is currently needed.

Run the prepared native audio capability probe after setup:

```sh
swift Validation/EQCapabilityProbe.swift
```

This runs offline; it does not play audio, capture system sound, install drivers, or change global routing. It checks four 32-band Apple EQ instances and measures actual rendered sine-wave gain. It is a framework feasibility probe, not the application or a substitute for its test suite.

Read [ARCHITECTURE.md](ARCHITECTURE.md), [the implementation plan](docs/superpowers/plans/2026-10-17-aura-p0.md), and [VALIDATION_REPORT.md](VALIDATION_REPORT.md) for the intended design, remaining work, and evidence.
