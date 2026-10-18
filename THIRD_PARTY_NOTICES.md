# Third-party notices and dependency review

Review date: 2026-10-18. AURA project license: **GPL-3.0-or-later**.

## Dependency inventory

`swift package show-dependencies --format json` reports **zero external package dependencies**; the recorded result is `evidence/dependencies.json`. The Xcode project references only the local AuraCore package. No downloaded Audio Unit, DSP library, application runtime, or embedded third-party asset is included.

| Component | Use and licensing treatment |
|---|---|
| AURA source and local AuraCore package | GPL-3.0-or-later; Arthur Bes, by explicit declaration dated 2026-10-18; see COPYRIGHT.md |
| SwiftUI, AppKit, Foundation, Observation, AVFoundation/AVFAudio, AudioToolbox, Core Audio, Synchronization and Darwin | Apple/Swift platform frameworks or libraries supplied by the development environment and target macOS. Linked as platform libraries; their framework binaries are not vendored into the repository. Their own vendor terms continue to apply. |
| XCTest | Development/test framework supplied with Xcode; not part of the application bundle |
| Swift compiler, Swift Package Manager, Xcode and Instruments | Development tools, not vendored application dependencies; respective vendor/toolchain licenses apply |
| Python 3 standard library | Development-only project generation and bundle verification; no Python interpreter or package is bundled with AURA |
| SF Symbols | System-rendered symbol names through native APIs; no exported symbol asset or external font is bundled |
| Product Owner icon concept | Supplied as a visual reference. AURA's wave path and PNG sizes are generated from project Swift/Core Graphics source. The original reference image is not bundled. Arthur Bes explicitly confirmed authority to publish the icon under GPL-3.0-or-later on 2026-10-18; see COPYRIGHT.md and the publication decision. |

GPLv3 section 1 defines System Libraries and excludes them from Corresponding Source. This is the basis for the platform-library treatment above, not a claim to relicense Apple's frameworks. Verify the actual linked and bundled libraries for every release, particularly if a future toolchain embeds Swift runtime components. See the [official GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.html).

**Compatibility finding:** no incompatible external package dependency was identified in the current inventory. This finding is limited to the dependency-free implementation and does not preapprove future libraries, assets, plug-ins, capture drivers, or binary redistribution terms.

## DSP reference acknowledgement

The biquad implementation uses mathematical filter equations described in the [W3C Audio EQ Cookbook](https://www.w3.org/TR/audio-eq-cookbook/), adapted there from Robert Bristow-Johnson's work. The W3C publication identifies its [permissive document license](https://www.w3.org/copyright/document-license/). AURA's Swift implementation is project source, not a vendored W3C software library. The publication is linked as a technical reference; its text is not included as application source. Preserve this acknowledgement.

## License text provenance

LICENSE was retrieved directly from `https://www.gnu.org/licenses/gpl-3.0.txt` without editing or adding a header. Its SHA-256 is:

```text
3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986
```

The project selects **GPL-3.0-or-later** through SPDX notices and README. The GPL v3 text itself remains unchanged.

## Release obligations and pending decisions

- Arthur Bes's explicit rights and publication-authority declaration is recorded in COPYRIGHT.md. Preserve rights/provenance records for subsequent contributions; no third-party rights are assigned by this declaration.
- Review contribution provenance and any future dependencies/assets before release.
- For an authorized binary release, provide the applicable license/notices and GPL-compliant access to the Corresponding Source and build instructions for that exact release. Do not substitute a source URL that does not exist or an unreviewed promise of future access.
- Review any applicable installation-information obligations, signing/distribution terms, and recipient restrictions for the intended channel. The preparation currently targets independent macOS distribution, not the Mac App Store.
- Source publication to arthurkbes-del/AURA is authorized by the 2026-10-18 decision. Binary releases, other distribution channels and notarization submissions still require separate authorization.
