# Independent macOS distribution preparation

**Preparation only. No publication, external upload, notarization submission, or binary distribution is authorized.** Copyright ownership and authority to release must be settled before publication. The project license is GPL-3.0-or-later; LICENSE is the complete, unchanged GPL v3 text.

## Current local build

- Native Universal 2 `.app`, bundle identifier `com.evoluere.aura`, arm64 and x86_64.
- Minimum deployment target: macOS 15.0; built locally using Swift 6.4 and Xcode 27.1/macOS 27 SDK.
- Xcode project: `Aura/Aura.xcodeproj`, shared scheme `Aura`.
- Current identity `-` is an **ad hoc development signature**. It is not a Developer ID signature and does not establish Gatekeeper acceptance or notarization.
- The app is menu-bar oriented (`LSUIElement`), has no installer/driver, and requests system audio capture permission in Applications mode through NSAudioCaptureUsageDescription. P1 creates only session-owned private tap/aggregate resources; it does not change the global default output or use microphone input.
- LICENSE and THIRD_PARTY_NOTICES.md are included as app resources in Xcode builds.

Build without sending anything externally:

```sh
zsh Scripts/build-universal.sh
```

The bundle is `build/Universal2/DerivedData/Build/Products/Release/AURA.app`. Keep generated binaries under the ignored `build/` directory. The script checks both Mach-O slices, minimum OS, license resources and the ad hoc signature, recording `build/Universal2/verification.json`. It intentionally verifies local development artifacts; a future Developer ID release needs its own signing verification.

The [Universal 2 report](docs/UNIVERSAL2_VALIDATION_REPORT.md) records 64 native arm64 tests, 61 x86_64 tests under Rosetta and an actual x86_64 capture/processing session. Rosetta evidence does not qualify physical Intel hardware. Test the app on a compatible Intel Mac and on the oldest supported macOS before claiming that hardware/OS qualification.

## Before an authorized release

1. Record confirmed rights holders and contribution provenance. Do not infer ownership from authorship of a prompt, a Git identity, a bundle identifier, or the selected license.
2. Obtain explicit Product Owner authorization for the exact source publication and binary distribution/channel. Notarization itself uploads software to Apple and must be authorized.
3. Preserve P0/P1 acceptance and complete release hardware/listening/recovery checks on both processor families and the oldest supported OS, license/dependency review, and any relevant GPL installation-information assessment.
4. Select a release version and immutable Git commit; assemble its complete Corresponding Source, build instructions and notices. Agree how every binary recipient receives GPL-compliant source access before distributing the binary.
5. Use the owner's own Apple Developer membership and Developer ID Application certificate. Configure identity/team explicitly; never commit certificates, private keys, credentials, or a guessed identity.
6. Build Release with Developer ID signing and hardened runtime enabled. Inspect entitlements and signatures of the actual bundle, including nested code. Debug build logs and ad hoc signatures do not establish release readiness; the current local Release signature contains a runtime flag but has no Developer ID or team identity.
7. After upload approval, submit a suitable archive using `xcrun notarytool submit … --keychain-profile … --wait`, inspect the result/log, and staple the approved ticket using `xcrun stapler staple …`. These steps have **not** been run.
8. Validate the resulting bundle using `codesign --verify --deep --strict --verbose=2`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=2`. Test first launch on a separate clean Mac with quarantine/Gatekeeper, not just this development machine.
9. Package the verified bundle and license/notices using a macOS-aware archive tool such as `ditto`; publish only through the explicitly approved channel alongside the required source access.

Do not add a license agreement or distribution restriction that conflicts with recipients' GPL rights. Distribution-channel and Apple signing terms must be reviewed for the actual release arrangement.

Apple's current process is documented in [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). No signing/notarization success is claimed in this preparation.
