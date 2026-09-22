# Contributing

Pull requests are welcome from anyone. Fork the repository and open your PR against **`dev`**, the
default branch.

- **Features and fixes merge into `dev`.** Neither `dev` nor `main` accepts direct pushes.
- **`main` takes only release PRs from `dev`**, titled `Release vX.Y.Z`. A required check rejects any
  other PR into `main`. Merging a release PR tags `vX.Y.Z` and publishes a GitHub release. Release PRs
  merge with a merge commit, so `dev` and `main` keep a shared history.

Before claiming something works, run `./smoke.sh` against the free demo (see the README). Every claim
in the README was run; a change that adds one belongs in its "What was verified" section.

Never commit a key. `.env` is gitignored and holds your own `cru_demo_` key.
