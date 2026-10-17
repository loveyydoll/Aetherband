# Development and Release Tracking

This document defines how Aetherband changes are tracked from idea to public release.

## The lifecycle

1. **Planned** — recorded in an issue or milestone; not implemented.
2. **In progress** — work is happening on a named branch.
3. **In review** — a pull request is open; CI and review are pending.
4. **Merged** — the change is in the target branch. This is not a release.
5. **Verified** — required automated checks and any specified manual checks have passed. Record the evidence in the PR.
6. **Released** — a version tag and GitHub Release have been published. Only now should a public release date be recorded in the changelog.

A change can be merged without being released. Never label a planned, draft, or unverified feature as shipped.

## Dates we track separately

| Date | Meaning | Source of truth |
|---|---|---|
| First commit | When implementation began | Git commit history |
| PR opened | When review began | Pull request timeline |
| PR merged | When the change entered the target branch | GitHub merge metadata |
| Verification completed | When required checks passed | CI run links and recorded manual test notes |
| Release published | When users could obtain a versioned release | GitHub Release publication date |
| Release tag target | Exact source revision shipped | Git tag / release metadata |

Use ISO dates (`YYYY-MM-DD`) in project-maintained documents. GitHub's timestamps remain authoritative for PR and release events.

## Versioning policy

- Use pre-release labels while the product is in alpha, for example `0.1.0-alpha.1`; do not imply stability.
- Increment the pre-release identifier for another public build of the same milestone.
- Use a stable `1.0.0` only after documented release gates pass.
- A release must point to a reviewed commit on the intended branch.
- Publish notes describing user-visible changes, compatibility/migration notes, known limitations, and verification status.
- Do not create a tag or claim a release simply to mark a milestone as complete.

## Required PR record

Every implementation PR should include:
- **Why:** user or engineering problem being addressed.
- **Scope:** what changes and what explicitly does not.
- **Tests:** commands run and their actual results; never list unrun commands as passing.
- **Risk/regressions:** especially transport, real-time callback, C ABI, and project compatibility.
- **Tracking:** related issue and target milestone/version where known.
- **Release note:** a concise entry suitable for `CHANGELOG.md`, or an explicit statement that the change is internal-only.

## Release checklist

- [ ] Required Rust formatting, workspace checks, and tests pass.
- [ ] Required Flutter analysis, widget tests, and desktop builds pass on supported platforms.
- [ ] Stop/rewind and existing stereo playback regressions pass.
- [ ] User-visible workflows claimed in the notes are tested.
- [ ] Known limitations and platform support are documented.
- [ ] Changelog entry is finalized with the actual publication date.
- [ ] Version tag points to the reviewed release commit.
- [ ] GitHub Release is published with notes and artifacts.
- [ ] Release URL and tag are recorded in the release register.

## Release register

Keep one row per published release. Leave fields blank until the event actually occurs.

| Version | Release date (UTC) | Tag / commit | GitHub Release | Verification summary |
|---|---|---|---|---|
| No published releases recorded yet | — | — | — | — |

## Current work (as of 2026-10-17)

| Item | Status | Reference |
|---|---|---|
| Flutter + Dart FFI migration | PR merged; initial engine lifecycle, transport and telemetry adapter exists. Real Windows/macOS playback and shutdown still require host verification. | [PR #12](https://github.com/loveyydoll/Aetherband/pull/12) |
| Creative-platform README repositioning | Merged; product vision and README updated, not a release. | [PR #13](https://github.com/loveyydoll/Aetherband/pull/13) |
| Creative engine and spatial-audio foundations | Merged foundational metadata/utilities and direction docs; not a spatial renderer or immersive export implementation. | [PR #14](https://github.com/loveyydoll/Aetherband/pull/14) |
| Native-engine widget test stability | Merged; test no longer assumes the native library is absent on every test host. | [PR #18](https://github.com/loveyydoll/Aetherband/pull/18) |
| ABI sample-rate correctness, FFI lifecycle and truthful recording UI | Open PR; Rust formatting was fixed in the branch, CI is running. Not yet merged. | [PR #19](https://github.com/loveyydoll/Aetherband/pull/19) |

This table is a snapshot, not a substitute for GitHub's live state. Update it when PR status changes, and record releases only when published.
