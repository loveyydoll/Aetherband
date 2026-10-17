# Changelog

All notable changes to Aetherband are recorded here. This project follows a lightweight Keep a Changelog structure, with release dates recorded only when a version is actually published.

## [Unreleased]

### Added
- Foundational spatial-audio metadata: channel layouts and Cartesian source positions. These types are not yet connected to playback or project persistence.
- An allocation-free equal-power stereo gain utility with deterministic tests for hard-left, centre, hard-right, and invalid inputs. It is not yet wired into the mixer.
- Architecture plan for the shared creative engine, visual programming, extensible synthesis, and staged spatial-audio work.
- A release-recording policy that distinguishes commits, merged pull requests, and published releases.

### Not yet released
- Multichannel rendering/routing, spatial panning in the audio callback, binaural/HRTF monitoring, Dolby Atmos authoring/export, modular synthesis, and user-authored DSP are not delivered by this work.

## Release history

No tagged or published Aetherband release has been recorded in this changelog yet. Development milestones and merged pull requests are not releases by themselves.

## Entry format

For each published version, add a dated section such as:

`## [0.1.0-alpha.1] - YYYY-MM-DD`

Include **Added**, **Changed**, **Fixed**, **Removed**, and **Known limitations** as appropriate. Link the version to its Git tag and GitHub Release when those exist. Never backdate a release to the date of a commit or PR merge.
