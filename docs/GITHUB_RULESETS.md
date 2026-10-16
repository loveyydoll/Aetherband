# GitHub Repository Rulesets — Aetherband

**Status:** Proposed configuration. These are recommendations, not proof that GitHub has enforced them. As of this change, the connected GitHub integration exposes ruleset/branch-protection reads but no mutation operation to create or update repository rulesets. No server-side ruleset was changed by this task.

## Goals
Protect `main` from accidental direct changes and destructive history edits, require reviewable pull requests, and make automated checks a merge gate once the checks are stable. Keep the early-alpha project maintainable without requiring an approval from a second person if the repository is currently maintained by a single owner.

## Ruleset A — Default branch safety
Create a repository ruleset targeting branches, with the default branch included.

Recommended settings:
- **Enforcement:** Active.
- **Target:** Default branch (`main`).
- **Restrict deletions:** On.
- **Block force pushes / non-fast-forward updates:** On.
- **Require a pull request before merging:** On.
- **Required approvals:** 0 initially for a single-maintainer repository; raise to 1 when another trusted reviewer is available.
- **Require conversation resolution:** On, if review comments are used.
- **Require signed commits:** Optional; do not enable until the owner's signing workflow is set up.
- **Restrict who can push:** Do not configure in a way that locks the repository owner out.
- **Bypass list:** Keep empty or limited to a deliberate emergency role. Do not grant broad bypass to bots or all write users.

## Ruleset B — CI merge gate (enable after checks are stable)
Require the relevant checks to pass before merge:
- Rust formatting: `cargo fmt --all -- --check`
- Rust workspace check: `cargo check --workspace --all-targets`
- Rust tests: `cargo test --workspace --all-targets`
- Rust Clippy: `cargo clippy --workspace --all-targets -- -D warnings` once the workflow includes it and is passing.
- .NET restore/build/test only after the workflow targets the actual solution and SDK and its checks pass reliably.

**Important:** Required status-check names must match the exact check-run names shown by GitHub. Inspect a successful run before configuring them. Do not guess names or make a failing/stale check mandatory; this can block every merge. The current main branch's .NET workflow has previously failed, and the Rust workflow added on another branch first failed at formatting. Verify/fix these before enabling CI as a required merge gate.

## Ruleset C — Pull request hygiene
- Use the repository pull-request template.
- Keep PRs focused and small.
- Require a human to review high-risk audio/unsafe/FFI changes where possible.
- Never merge a PR merely because an agent created it.
- Ensure PR body distinguishes implemented, not implemented, verified, not verified and known risks.

## Suggested rollout
1. Inspect current Actions check names and fix existing CI failures.
2. Create and activate Ruleset A in **Settings → Rules → Rulesets → New ruleset → New branch ruleset**.
3. Add Ruleset B's required checks only after each check has completed successfully at least once on a PR.
4. Test protections with a harmless branch/PR. Verify direct pushes and force pushes are blocked without locking out maintainers.
5. Revisit approval requirements when the project gains additional maintainers.

## Current application status
- [x] Version-controlled instructions and PR checklist added on a feature branch.
- [ ] Server-side default-branch ruleset created.
- [ ] Required CI checks enabled after stable successful runs.
- [ ] Protection tested against an ordinary contributor workflow.

The last three items require GitHub repository administration. This task has not applied them because the connected integration provides no ruleset-write operation. The repository was confirmed to report admin permission for the connected identity, but permission alone does not create an available write interface.
