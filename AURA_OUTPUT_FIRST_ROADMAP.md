# AURA — Output-first product roadmap

**Decision:** Product Owner directive, 2026-10-17. **Priority:** Critical.
**Scope:** Every development package after P0. This decision preserves P0's requirements and acceptance criteria.

## Mission and strategy

AURA should give users professional control over the audio they hear from their Mac, without cost, subscriptions or unnecessary complexity. Prioritize comprehensive native macOS output processing before microphone processing, video capture, multitrack production or audiovisual synchronization.

The product is free and open source, under **GPL-3.0-or-later**, local first, with no subscriptions, paid features or artificial feature restrictions. Support for Intel x86_64 and Apple Silicon arm64 is a product requirement. Current P0 validation covers arm64 only; this is a validation boundary, not a paid edition or permanent product restriction.

Reliable audio takes priority over visual complexity. Measurements and compatibility claims require evidence. Device and processing failures must have safe recovery paths.

## Execution order

| Package | Required outcome |
|---|---|
| **P1 — System-wide audio processing** | Real-time capture, processing and playback of supported macOS application audio. Investigate public Core Audio Process Taps and aggregate devices first. Preserve four independent EQ modules, up to 32 bands each. Address permissions, mute behavior, explicit device/process selection, feedback prevention, sample-rate changes, latency, failures and cleanup. Record which applications/output modes were actually tested. |
| **P2 — Professional DSP** | Meaningful, independently tested and documented spectrum/FFT analyzer, compressor, true peak limiter, dynamic EQ, stereo balance/channel controls, crossfeed, loudness measurements and signal headroom management. No decorative analyzer or gain control mislabeled as a limiter. |
| **P3 — Advanced output routing** | Device profiles, automatic preset switching, output-device monitoring, reliable recovery and advanced routing where public APIs and validated hardware support it. P1 still includes the minimum device monitoring/recovery needed for safe operation. |
| **P4 — Optimization and distribution** | Validate Intel x86_64, Apple Silicon arm64 and Universal 2; CPU/memory, audio latency/stability, accessibility/native UI behavior, signing/notarization and GNU GPL v3 licensing compliance. Architecture decisions before P4 must preserve the path to both processor families. |

## Deferred product directions

Microphone processing, virtual microphone, HDMI video capture, multitrack recording, automatic camera/audio synchronization and an audiovisual production workstation remain future directions. They are not cancelled, but must not take priority before output processing is stable.

## Gates and governance

1. Do not interrupt or weaken P0. Its supported local-file source, four modules, 128-band capacity, tests and human audible-processing acceptance remain required.
2. **Do not start P1 before P0 is complete and its validation report has been reviewed.** Current state: P0's audible-processing criterion is now confirmed by the Product Owner ("consegui escutar ele muda o som"). Menu icon visibility/panel opening are also confirmed. Review of the final P0 validation report remains pending.
3. At the P0 handoff, provide a proposed P1 architecture and execution package for review. Preparation is documentation only; it does not authorize starting capture, creating aggregate devices or changing routing now.
4. No system-wide compatibility claim is valid until measured on the stated OS, hardware, application and output mode. Preserve evidence and state limitations.
5. Repository publication, binary distribution and external notarization uploads still require explicit authorization. Confirm copyright ownership and artwork provenance before publication. Preparing a free/open-source release does not itself authorize publishing it.

## Prepared handoff

- P0 acceptance/evidence: [VALIDATION_REPORT.md](VALIDATION_REPORT.md).
- Proposed P1 architecture: [docs/P1_ARCHITECTURE.md](docs/P1_ARCHITECTURE.md).
- Gated execution package: [docs/superpowers/plans/2026-10-17-aura-p1.md](docs/superpowers/plans/2026-10-17-aura-p1.md).
- Current graph and future API assessment: [ARCHITECTURE.md](ARCHITECTURE.md).

**P1 execution status: NOT STARTED.**
