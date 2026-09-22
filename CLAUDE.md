# Working in this repository

A published, verified recipe for running [BytesBrains Cruise](https://bytesbrains.com/cruise) as an
OpenAI-compatible backend behind [agentgateway](https://agentgateway.dev). It is configuration, a
demo and a smoke test — there is no application here, nothing to build, and no package to publish.

**The repository's entire value is that its claims survive checking.** Everything in the README was
run. If you cannot run a thing, do not write it down as though you did.

## Running it

```sh
cp .env.example .env     # a cru_demo_ key; .env is gitignored
./smoke.sh               # up, one completion, assert, tear down. Exits non-zero on failure.
./smoke.sh --keep        # leave the gateway on :4000
```

`smoke.sh` needs Docker and `curl`, and it is the check to run before claiming the integration works.
`./smoke.sh --budget-cap` also needs Python 3 and `CRUISE_DEMO_CAP_API_KEY` in `.env`, issued from the
dashboard's Demo tab. It checks emulated spend, refusal, and recovery on the separate cap project.
Run `python3 -m unittest -v test_budget_cap` for local contract edge cases; those tests do not replace
a live smoke run.

Kubernetes is verified separately and needs a cluster:

```sh
kubectl create secret generic cruise-api-key -n cruise \
  --from-literal=Authorization="Bearer $CRUISE_API_KEY"
kubectl apply -f config/kubernetes/01-backend.yaml -f config/kubernetes/02-gateway.yaml
```

## Rules that are not obvious from the files

**Test against the demo, never production.** `cruise-demo.bytesbrains.net` takes a `cru_demo_` key,
costs nothing, and returns the real response shape and the full `x-cruise-*` header set. It is what
makes a public smoke test something a stranger can run. The normal demo project never accumulates
spend. Each tenant's separate `demo-cap` project charges emulated $0.002 per call against $0.01 per
minute, allowing a free cap demo with its own key. Never publish a demo key; readers issue their own
from the dashboard. Avoid concurrent calls to the cap project when testing its spend sequence.

**No key ever enters a file here.** Keys live in `.env` (gitignored) or a Kubernetes Secret created
from the environment. Never print, echo or commit a `cru_` value. The example Secret ships with an
empty value on purpose — a key-shaped placeholder authenticates and fails with a 401 pointing
nowhere.

**Every sample must demonstrate something only Cruise does** — a spend cap tripping, or spend
grouped by lane. A sample showing a model answering through a gateway demonstrates agentgateway, not
Cruise, and does not belong here. This is why `smoke.sh` asserts on `x-cruise-*` headers rather than
just a `200`.

**The standalone recipe runs only on agentgateway's unreleased 1.x.** The newest published release,
`0.8.2`, rejects the config outright — the `llm:` block does not exist on that line. `compose/` pins
the verified digest for that reason. Kubernetes is on released artifacts (Helm `v1.5.0`, Gateway API
`v1.6.0`). See issue #6.

**Public repository.** No client names, no engagement or pipeline references, no internal repo paths,
no pricing strategy — in files *and* commit messages.

## Conventions

- **Changes go through a pull request into `dev`** (the default branch); neither `dev` nor `main`
  takes direct pushes. `main` takes only release PRs from `dev`, titled `Release vX.Y.Z` and merged
  with a merge commit; the `release gate` check enforces this and merging tags the version. See
  `CONTRIBUTING.md`. The wrokin bot reviews PRs; add the `skip-bot-review` label before pushing a
  correction so a fix does not buy a re-review.
- **Never edit a sibling repository** to finish work that belongs there. File an issue on it instead,
  carrying the facts so that repo's agent needs nothing re-derived.
- **Say what was verified and what was not.** The README has a "What was verified" section; changes
  that add a claim belong in it, and claims that were not run do not belong in the README at all.

## Layout

| Path | What it is |
| --- | --- |
| `config/standalone/config.yaml` | agentgateway standalone, pointed at Cruise |
| `config/kubernetes/` | `AgentgatewayBackend` with its TLS policy, `Gateway`, `HTTPRoute`, Secret template |
| `compose/docker-compose.yml` | `docker compose up` → gateway on `:4000`, upstream image, digest-pinned |
| `smoke.sh` | The only test |
