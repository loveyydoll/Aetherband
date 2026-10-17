# Aetherband — Messaging Guide

This guide keeps public descriptions of Aetherband consistent with its product direction, current early-alpha status, and distinction between development milestones and stable releases.

## Positioning

**Aetherband is an open creative platform for making music.**

It is an experimental, free and open-source DAW being built for musicians first, with developers close behind. Its long-term purpose is to make a flexible, inspectable audio workspace where creative workflows and the underlying tools can evolve in the open.

## Core tagline

**Make sound your own. Keep the tools open.**

## Short descriptions

### GitHub repository description
An experimental, open-source DAW built around a native Rust audio engine and a customizable Flutter desktop UI. Early alpha; actively evolving.

### One sentence
Aetherband is an open creative platform for musicians and developers exploring a more flexible, community-shaped approach to digital audio workstations.

### Short project introduction
Aetherband is an early-alpha, free and open-source DAW with a Rust audio engine and a Flutter desktop frontend. We are building in the open toward a flexible workspace for recording, arranging, sound design, and mixing. The project is experimental today; the roadmap describes where we want to go, not features we claim are already finished.

### Social profile
An open creative platform for making music. Rust audio engine, Flutter desktop UI, GPL-3.0, built in the open. Early alpha.

### Release announcement template
**Aetherband [version] — [milestone name]**

This release moves Aetherband toward [specific user-facing outcome].

**What changed**
- [Implemented change, verified on named platform]
- [Implemented change, with test or manual verification noted where relevant]

**Known limitations**
- [Important missing workflow]
- [Platform or hardware limitation]

**What's next**
The next milestone is [goal]. It is a development target, not a guaranteed release date.

## Audience priorities

1. **Musicians and producers:** explain the creative outcome and what they can actually try today.
2. **Open-source contributors:** explain where help is useful, how the code is structured, and how to verify a change.
3. **Audio developers:** document engine boundaries, real-time safety, ABI contracts, testing, and trade-offs.

Do not assume that musicians care about framework choices before they understand the product. Technical details should support the vision rather than replace it.

## Voice

- Independent, curious, experimental, and grounded.
- Ambitious about the long-term vision; precise about the current state.
- Speak plainly. Prefer specific outcomes over grand claims.
- Invite people to shape the project without implying that a community or contributor base is already large.
- Treat uncertainty as part of open development, not as something to hide.

## Release-stage terminology

- **Alpha 1.0** completes the initial alpha roadmap and establishes a baseline for broader testing. It is not a stable release and does not imply production readiness.
- **Beta releases** continue testing implemented workflows, usability, compatibility, performance, and reliability.
- **Release candidates (RCs)** are candidate builds checked against explicit release criteria.
- **Stable 1.0** is a separate milestone and should be announced only when the supported workflows meet documented quality and reliability requirements.

There may be multiple beta, RC, and other testing builds. Do not imply a fixed number of releases or a schedule before evidence supports it.

## Claims policy

### Safe to say
- Free and open source under GPL-3.0.
- Rust audio engine, versioned C ABI, Dart FFI, and Flutter desktop frontend.
- Early alpha and actively evolving.
- The project aims to support recording, arranging, sound design, and mixing over time.
- The Stop/rewind transport fix has regression coverage.

### Say only after verification
- A feature works end to end.
- A platform build is stable or release-ready before it has passed the relevant release criteria.
- Alpha 1.0 is the stable release or means the project is production-ready.
- Audio performance is better than another DAW or UI framework.
- The app is suitable for professional or production-critical sessions.
- Plugin compatibility, project interchange, recording, MIDI, export, or save/load is complete.

### Avoid
- “Revolutionary”, “the future of music production”, or other empty superlatives.
- Claiming to replace established DAWs before feature and reliability parity exists.
- Presenting mock/demo clips as real sessions.
- Treating a successful compile as proof that hardware audio workflows work.
- Promising delivery dates based only on AI coding speed.

## Visual direction

Use a recognizable, restrained identity that feels independent and exploratory. Prefer real application screenshots, annotated prototypes clearly labelled as concepts, and short recordings of verified workflows. Do not use mockups that could be mistaken for implemented UI. The visual identity should make Aetherband recognizable without pretending the product is more mature than it is.

## Release communication checklist

Before publishing a release, confirm:

- [ ] The named features are implemented in the release branch.
- [ ] Automated tests and CI status are reported accurately.
- [ ] Manual platform and audio-hardware checks are identified separately from automated tests.
- [ ] Known limitations and data-loss risks are stated clearly.
- [ ] Screenshots and videos show the actual release build.
- [ ] The next milestone is described as a goal, not a promise.
