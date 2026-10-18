# AURA — standing project instructions

## Keep both processor architectures current

Product Owner instruction: after every new functionality, update the local Universal 2 app so Intel x86_64 and Apple Silicon arm64 contain the same current conventional features.

- Preserve the macOS 15 minimum unless the Product Owner approves changing it.
- Run appropriate regression checks, then `zsh Scripts/build-universal.sh` after the final source/resource changes. Check its exit status and current `build/Universal2/verification.json` before reporting the build as updated.
- Keep the resulting app at `build/Universal2/DerivedData/Build/Products/Release/AURA.app`; generated binaries remain ignored by Git.
- Update relevant documentation and validation evidence. Distinguish native hardware validation from Rosetta execution; do not claim physical Intel qualification from a dual-architecture build alone.
- Keep licensing notices current. Local build updates do not authorize publication, binary distribution, external uploads or notarization submissions.

## Source publication authorization

On 2026-10-18, Arthur Bes explicitly declared rights and authority to publish the code and icon under GPL-3.0-or-later and authorized sending this project to the public repository `https://github.com/arthurkbes-del/AURA`. See `COPYRIGHT.md` and `docs/decisions/2026-10-18-source-publication.md`. Preserve the scope of that authorization; binary releases and external notarization submissions require separate authorization.
