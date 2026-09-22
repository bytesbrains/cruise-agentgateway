# Contributing

Pull requests are welcome from anyone. Fork the repository and open your PR against **`dev`**, the
default branch.

- **Features and fixes merge into `dev`.** Neither `dev` nor `main` accepts direct pushes.
- **`main` takes only release PRs from `dev`**, titled `Release vX.Y.Z`. A required check rejects any
  other PR into `main`. Merging a release PR tags `vX.Y.Z` and publishes a GitHub release. Release PRs
  merge with a merge commit, so `dev` and `main` keep a shared history.

## Repository settings the flow relies on

These live in GitHub's settings, not in a file, so they are recorded here. Nothing in the repository
enforces them: `release gate` is a check name, and only the settings below stop a PR from posting a
same-named check of its own.

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
  (`all_external_contributors`), not only first-time ones. A PR could otherwise add its own workflow
  with a job named `release gate`.

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
