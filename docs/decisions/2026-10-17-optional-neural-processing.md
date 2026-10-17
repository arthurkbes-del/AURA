# Optional neural processing — future architecture decision

**Authority:** Product Owner, 2026-10-17. **Status:** approved future direction; documentation only. This decision does not change the P1 system-output priority or authorize neural implementation/model downloads now.

## Core and module boundaries

- AURA Core must remain a Universal 2 product, with conventional audio functionality available on compatible Intel and Apple Silicon Macs. Current P0 evidence is arm64 only; x86_64/Universal 2 qualification remains tracked in P4. Do not describe that qualification as already complete.
- Neural features are optional modules. Core startup, audio routing, conventional EQ/DSP, presets and recovery must work without a neural model or compatible neural hardware.
- Use Core ML for future integration and evaluate Apple Neural Engine acceleration. Detect hardware, OS, model and feature availability at runtime. Do not infer actual Neural Engine execution merely from MLComputeUnits.all.
- Keep model loading/inference lifecycle separate from the real-time audio callback. Measure whether deadlines are achievable before promising real-time operation; preserve a safe conventional path if the optional module cannot keep up.
- All processing remains local/offline. Optional hardware capabilities must not create paid editions, subscriptions or artificial restrictions on conventional audio features.

## Planned optional modules

| Module | Future scope |
|---|---|
| AURA Neural Voice | Neural noise reduction, voice preservation and real-time operation where validated and viable |
| AURA Neural Video | Video super-resolution, neural denoising, restoration and perceptual image improvement |

These modules do not promote microphone/video work ahead of stable output processing. Schedule them in a future package after the output-first priorities; no delivery version or universal hardware/model compatibility is promised here.

## Evidence required before integration

For each model, document its origin, exact version/hash, code and weight licenses, notices and redistribution/modification rights. Confirm compatibility with AURA's free/open-source GPL-3.0-or-later distribution before integration. A free download alone does not establish license compatibility. No model has been selected, downloaded, bundled or approved by this decision.

Measure latency (including buffering/model warmup), memory, energy, sustained throughput and perceptual quality on the stated hardware/OS. Record actual execution/acceleration evidence and fallback behavior. Compare quality and resource costs with conventional processing; do not fabricate ANE usage or real-time performance claims.

## Governance and current effect

Only this record and roadmap links are added. No Core ML dependency, model, capture permission or neural runtime code is added. P1 proceeds with public Core Audio output capture/processing. Existing publication, copyright, artwork, model-license and distribution approval requirements remain in force.
