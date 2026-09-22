# Contributing

Pull requests are welcome from anyone. Fork the repository and open your PR against **`dev`**, the
default branch.

- **Features and fixes merge into `dev`.** Neither `dev` nor `main` accepts direct pushes.
- **`main` takes only release PRs from `dev`**, titled `Release vX.Y.Z`. A required check rejects any
  other PR into `main`. Merging a release PR tags `vX.Y.Z` and publishes a GitHub release. Release PRs
  merge with a merge commit, so `dev` and `main` keep a shared history.

## Repository settings the flow relies on

These live in GitHub's settings, not in a file, so they are recorded here:

- **`dev`** is the default branch. Branch protection requires a pull request, applies to admins,
  and blocks force pushes and deletion.
- **`main`** has the same protection plus a required status check, `release gate`, from
  `.github/workflows/release-flow.yml`. Without that required check, nothing stops a non-release PR
  from merging into `main`.
- **A ruleset on `main`** allows only the merge-commit method.

## Checking your change

Before claiming something works, run `./smoke.sh` against the free demo (see the README). Every claim
in the README was run; a change that adds one belongs in its "What was verified" section.

Never commit a key. `.env` is gitignored and holds your own `cru_demo_` key.
