# Contributing

Pull requests are welcome from anyone. Fork the repository and open your PR against **`dev`**, the
default branch.

- **Features and fixes merge into `dev`.** Neither `dev` nor `main` accepts direct pushes.
- **`main` takes only release PRs from `dev`**, titled `Release vX.Y.Z`. A required check rejects any
  other PR into `main`. Merging a release PR tags `vX.Y.Z` and publishes a GitHub release. Release PRs
  merge with a merge commit, so `dev` and `main` keep a shared history.

## Repository settings the flow relies on

These live in GitHub's settings, not in a file, so they are recorded here. Nothing in the repository
enforces them. `release gate` is only a check name. These settings are what make its result
trustworthy: they decide which workflow runs it and which runs count.

- **`dev`** is the repository's default branch, and must stay the default. `pull_request_target`
  loads the workflow from the default branch, so if the default ever moved to `main`, the gate would
  load from the branch it protects, and a PR into `main` could edit the check that judges it. Branch
  protection requires a pull request, applies to admins, and blocks force pushes and deletion.
- **`main`** has the same protection plus a required status check, `release gate`, from
  `.github/workflows/release-flow.yml`, pinned to the GitHub Actions app (`app_id` 15368) so a status
  posted through the API cannot satisfy it. Without that required check, nothing stops a non-release
  PR from merging into `main`. The check runs on `pull_request_target`, which takes the workflow from
  the default branch, `dev`, so a PR cannot rewrite the gate that judges it. That makes `dev`'s
  protection part of the gate: a change to it lands on `dev` first, through a pull request.
- **A ruleset on `main`** allows only the merge-commit method, and requires every review thread to be
  resolved before merge.
- **Fork PR workflows** need a maintainer's approval for every outside contributor
  (`all_external_contributors`), not only first-time ones. A fork PR's own workflow, including a job
  named `release gate`, therefore never runs without review. The tests below show such a job would
  not pass the gate, so this is a second layer.

Tested on 2026-09-22 in throwaway PRs into `main` (#17, #19), pushed to branches in this repository
with write access, so no fork approval applied. Each of these left the PR blocked:

- Editing the gate to `exit 0`. The gate ran from `dev`'s copy and failed.
- Also giving the PR's own copy of the workflow a `pull_request` gate, which passed. Every
  `release gate` run on the head commit counts toward the required check, so `dev`'s failing run
  still blocked the merge, even when the passing run was the newest.
- Cancelling `dev`'s run before it finished. A cancelled required run also blocks.
- A `[skip ci]` head commit, with the PR's own `release gate` job on `pull_request_review`. `[skip ci]`
  did not suppress `dev`'s `pull_request_target` run, which ran and failed.

So a collaborator's own `release gate` job can add a passing run, but cannot remove `dev`'s failing
one. Not tested: a PR from a fork, and deleting `dev`'s run rather than cancelling it.

Read back over the API on 2026-09-22, so this is what was checked rather than what was intended:

- `dev` is the default branch.
- `dev` and `main` both require a pull request, apply it to admins, and block force pushes and
  deletion.
- `main`'s required check is `release gate`, from app `15368`.
- The `main` ruleset allows only the merge method, and requires threads resolved.
- The fork approval policy is `all_external_contributors`.

Re-read these after any settings change. `release gate` is only as strong as the settings behind it,
so until they are confirmed, treat it as advisory.

## Checking your change

Before claiming something works, run `./smoke.sh` against the free demo (see the README). Every claim
in the README was run; a change that adds one belongs in its "What was verified" section.

Never commit a key. `.env` is gitignored and holds your own `cru_demo_` key.
