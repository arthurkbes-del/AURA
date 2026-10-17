# Contributing to AURA

AURA uses **GPL-3.0-or-later**. Read the complete, unmodified license in [LICENSE](LICENSE) before contributing.

Submit only work you have the right to contribute under GPL-3.0-or-later. Identify any copied or adapted third-party code, its original source, copyright notices, license, and modifications. Record approved dependencies in THIRD_PARTY_NOTICES.md. Do not introduce dependencies with unverified or incompatible terms.

Contributors retain their rights unless a separate, explicit written agreement says otherwise. Contribution does not imply copyright assignment. The project's copyright ownership has not yet been determined; do not invent an owner or add a blanket ownership claim. Confirmation of ownership and authority to release is required before publication.

## Development

- Use Swift 6 and official Apple frameworks. Current deployment target: macOS 15, Apple Silicon.
- Preserve four independent EQ modules and the 32-band-per-module contract.
- Keep audio callbacks free of file I/O, blocking locks, UI work, and dynamic allocation.
- Add regression tests for changes to DSP, state, playback, or persistence. Keep deterministic tests separate from hardware/listening checks.
- Never present generated test tones as measurements or claim listening results from automated tests.
- Preserve the P0 file path while developing P1 capture. Use only session-owned taps/aggregates; reject unsupported formats, exclude AURA feedback and keep dry playback available until useful PCM is verified.
- Follow AURA_OUTPUT_FIRST_ROADMAP.md for later packages. The Product Owner has released P1’s entry gate; current acceptance limits are in docs/P1_VALIDATION_REPORT.md. Preserve the path to Intel and Apple Silicon compatibility; P0's current validation is arm64 only.

From the repository root:

```sh
swift test
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
xcodebuild -project Aura/Aura.xcodeproj -scheme Aura \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData test
```

Use `// SPDX-License-Identifier: GPL-3.0-or-later` in Swift files. In Package.swift, keep the `swift-tools-version` directive first and place SPDX immediately below it. Do not modify the GPL license text itself.

Keep commits focused and document evidence, remaining limitations, and performance measurement methods. Do not commit personal audio, credentials, signing certificates, provisioning profiles, private keys, or notarization credentials.

## Publication and distribution

The Product Owner has **not authorized repository publication or binary distribution**. Local builds and tests are authorized. Opening a public repository, pushing to an external remote, uploading releases, submitting for notarization, or distributing builds requires explicit authorization. Follow [DISTRIBUTION.md](DISTRIBUTION.md) when a release is authorized.
