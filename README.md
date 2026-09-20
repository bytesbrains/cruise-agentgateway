<p align="center">
  <img src="https://bytesbrains.com/brand/cruise-logo-480.png" alt="BytesBrains Cruise" width="280" />
</p>

<h1 align="center">BytesBrains Cruise for agentgateway</h1>

<p align="center">
  Run Cruise as an OpenAI-compatible backend behind <a href="https://agentgateway.dev">agentgateway</a> —<br />
  so budgets, per-project keys and one cost ledger stay on the gateway, per job.
</p>

<p align="center">
  <a href="https://bytesbrains.com/cruise"><img src="https://img.shields.io/badge/Product-bytesbrains.com%2Fcruise-111111" alt="Product" /></a>
  <a href="https://agentgateway.dev/docs/kubernetes/latest/llm/providers/openai-compatible/"><img src="https://img.shields.io/badge/agentgateway-OpenAI--compatible-4b5fc7" alt="agentgateway" /></a>
  <img src="https://img.shields.io/badge/status-verified-2f855a" alt="Status: verified" />
</p>

---

## What this is

[BytesBrains Cruise](https://bytesbrains.com/cruise) is one OpenAI-compatible endpoint in front of every
model provider, with lanes (named jobs), hard per-project spend caps, and a ledger that records cost per
request without storing prompts or completions.

[agentgateway](https://agentgateway.dev) is an AI-native proxy for agent-to-LLM, agent-to-tool and
agent-to-agent traffic. It was donated to the Linux Foundation in 2025 and is an Agentic AI Foundation
project.

The two compose cleanly: agentgateway handles identity, policy and routing at the mesh edge; Cruise is
the backend that meters and caps what those calls cost, grouped by the job they did. **No plugin or
package is required** — Cruise plugs in through agentgateway's generic OpenAI-compatible provider.

Everything here has been run. See [What was verified](#what-was-verified) for the exact versions and the
one experiment worth reading.

| | |
| --- | --- |
| **Product** | [bytesbrains.com/cruise](https://bytesbrains.com/cruise) |
| **Cruise API** | `https://cruise.bytesbrains.net/v1` · free demo: `https://cruise-demo.bytesbrains.net/v1` |
| **agentgateway** | [agentgateway.dev](https://agentgateway.dev) · [GitHub](https://github.com/agentgateway/agentgateway) |
| **Source** | [bytesbrains/cruise-agentgateway](https://github.com/bytesbrains/cruise-agentgateway) |

## Quick start

You need Docker, `curl`, and a Cruise key. The free demo takes a `cru_demo_` key and costs nothing to
run, so this is safe to try end to end.

```sh
cp .env.example .env     # then put your cru_ key in it — .env is gitignored
./smoke.sh
```

`smoke.sh` brings the gateway up, sends one completion, asserts it came back `200` with Cruise's
telemetry intact, shows lane routing across three lanes, and tears everything down. It exits non-zero
if any of that fails.

To leave the gateway running and talk to it yourself:

```sh
./smoke.sh --keep
# or: cd compose && docker compose up
```

Then point any OpenAI client at `http://localhost:4000/v1` and ask for a Cruise lane:

```sh
curl -s http://localhost:4000/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"bb/code-review","messages":[{"role":"user","content":"hi"}]}' -D -
```

The model id is a Cruise lane, not a model. Cruise picks which model serves it — the gateway is not
configured with any of them.

## What Cruise adds that the gateway does not

The gateway proxies. Cruise prices. Every response carries what the call cost and what it was for:

```
x-cruise-lane: bb/code-review              the job this call was booked against
x-cruise-model: anthropic/claude-fable-5-1  who actually answered
x-cruise-selection: cheap                   why that one
x-cruise-budget-state: ok                   ok, or the reason the next call gets refused
x-cruise-budget-spend: 0.0000               spent this period
x-cruise-budget-limit: 5.00                 the hard cap
x-cruise-budget-period: day
```

**These survive the proxy.** That is not a given — a gateway is free to strip response headers it does
not recognise, and one that did would cost every caller behind it their budget state and their cost
attribution. `smoke.sh` asserts on them for exactly that reason: it is the assertion that would catch an
upstream change turning this integration into a plain proxy hop.

Aggregate spend — what a month cost, grouped by lane — is not an HTTP endpoint. `/v1/budget`, `/v1/spend`
and `/v1/usage` all `404`. It lives on the Cruise MCP server (`get_budget`, `get_spend`).

## The TLS gotcha

This repository was opened to document a trap: *a custom host override needs TLS stated explicitly,
where well-known provider hosts get it automatically.* Running it gave a more useful answer — **it
depends on which agentgateway you are configuring, and the two behave differently.**

### Standalone: no longer a trap

The current standalone config takes a `baseUrl`, which the schema documents as expanding "to
hostOverride, pathPrefix, and **tls** for https URLs". An `https://` scheme turns TLS on by itself:

```yaml
params:
  baseUrl: https://cruise.bytesbrains.net/v1   # TLS enabled by the scheme
```

No TLS block, no `sni`, nothing. The older `hostOverride` / `pathOverride` / `pathPrefix` fields the
original warning was written around are all marked `deprecated` in the published schema. If you are
reading advice about explicit TLS for standalone custom hosts, it predates `baseUrl`.

### Kubernetes: still a trap, and a well-disguised one

On Kubernetes the trap is real. `AgentgatewayBackend` does **not** infer TLS from `port: 443`. Omit the
TLS policy and the gateway speaks plaintext to an HTTPS port. Verified by removing exactly that block
and putting it back:

| `policies.tls` | Result |
| --- | --- |
| omitted | `400` — `The plain HTTP request was sent to HTTPS port` |
| `sni: cruise-demo.bytesbrains.net` | `200`, with Cruise headers intact |

```yaml
policies:
  auth:
    secretRef:
      name: cruise-api-key
  tls:
    sni: cruise-demo.bytesbrains.net   # must match `host`
```

Two things make this cost more time than it should:

1. **It is not a `BackendTLSPolicy`.** Despite what the Gateway API habit suggests, TLS to an
   `AgentgatewayBackend` is `spec.ai.groups.providers[].policies.tls` on the backend itself. Writing a
   separate `BackendTLSPolicy` resource will not fix it.
2. **The error never mentions TLS.** A `400 Bad Request` arrives from the *upstream's* edge — Cloudflare,
   in Cruise's case — so it reads like a malformed request and sends you to inspect your JSON body. The
   body is fine. The connection was plaintext.

If a custom-host backend returns a `400` you cannot explain, check `policies.tls` before anything else.

## Contents

| Path | What it is |
| --- | --- |
| [`config/standalone/config.yaml`](config/standalone/config.yaml) | agentgateway standalone, pointed at Cruise |
| [`config/kubernetes/`](config/kubernetes/) | `AgentgatewayBackend` with the TLS policy, `Gateway`, `HTTPRoute`, and a `Secret` template |
| [`compose/docker-compose.yml`](compose/docker-compose.yml) | `docker compose up` → gateway on `:4000`, upstream image, digest-pinned |
| [`smoke.sh`](smoke.sh) | Stand up, one completion, assert `200` and the Cruise headers, tear down |

Samples are held to one rule: **each must demonstrate something only Cruise does.** A sample that merely
shows a model answering through a gateway demonstrates agentgateway, not Cruise, and does not belong
here. `smoke.sh` asserts on lane routing and budget headers on those grounds.

One consequence worth stating plainly: the demo returns emulated completions and never accumulates
spend, so **a hard cap tripping mid-run cannot be shown against it.** That sample needs a production key
and real spend, and is not in v0 rather than being faked.

### Kubernetes

```sh
kubectl create namespace cruise
kubectl create secret generic cruise-api-key -n cruise \
  --from-literal=Authorization="Bearer $CRUISE_API_KEY"
kubectl apply -f config/kubernetes/01-backend.yaml -f config/kubernetes/02-gateway.yaml

kubectl port-forward -n cruise svc/cruise 8080:8080
curl -s http://localhost:8080/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{"model":"bb/summarization","messages":[{"role":"user","content":"hi"}]}' -D -
```

The Secret's key must be `Authorization` and its value the whole header, `Bearer ` included.

## Versions

This matters more than usual, because the standalone recipe **does not run on the newest published
release**.

| | Verified against | Note |
| --- | --- | --- |
| Standalone | `ghcr.io/agentgateway/agentgateway:latest`, reporting `1.6.0-alpha.1` | Digest-pinned in the compose file |
| Kubernetes | `agentgateway` Helm chart `v1.5.0`, Gateway API `v1.6.0` | |

The newest published image *release* tag is `0.8.2`, and it rejects this config outright — the
standalone `llm:` block does not exist there:

```
Error: llm: unknown field `llm`, expected one of `config`, `binds`, `policies`, `workloads`, `services`
```

So the compose file pins the `latest` digest that was verified rather than a release tag. Swap it for
`:latest` to track upstream, and expect the config to need revisiting when the 1.x line is released.

**A related trap, if you use an older build:** `0.8.2` expands `$UPPERCASE` tokens across the raw file
before parsing it as YAML — including inside comments. A comment mentioning an environment variable
kills startup with `error looking key 'VAR' up`. Newer builds parse first and expand only values. The
config here keeps `$` out of its comments regardless.

## Failure modes worth recognising

| What you see | What it is |
| --- | --- |
| `400 The plain HTTP request was sent to HTTPS port` | Missing `policies.tls` on a Kubernetes backend |
| `401 Incorrect API key provided.` | Cruise rejecting the key, relayed intact. Often a `cru_demo_` key against production or the reverse — check `CRUISE_BASE_URL` against the key prefix |
| `401 Missing bearer token.` | No key reached Cruise. Check the Secret's key name is `Authorization` |
| `llm: unknown field` | agentgateway too old — see [Versions](#versions) |

A `cf-ray` header on a response means the request reached Cruise rather than dying in the gateway.
Useful for splitting "the gateway is misconfigured" from "Cruise said no".

## What was verified

On a clean kind cluster and a local Docker daemon, 2026-09-20:

- One chat completion through standalone agentgateway to Cruise — `200`, real completion body.
- The same through agentgateway on Kubernetes — `200`.
- Cruise's `x-cruise-*` headers arrive intact through both.
- Four lanes routed to different models, with nothing about those lanes in the gateway config.
- `policies.tls` removed → `400`; restored → `200`. The controlled experiment behind the TLS section.
- `0.8.2` rejects the standalone config; `latest` accepts it.
- `smoke.sh` exits `0` on success and non-zero on failure.

Not verified: production Cruise (`cruise.bytesbrains.net`) end to end — the calls above ran against the
demo. Auth, TLS and routing are identical; only the key prefix and the base URL differ.

## Security

The key is read from the environment and never written to a file in this repository. `.env` is
gitignored, `config/kubernetes/00-secret.example.yaml` carries a placeholder, and `smoke.sh` checks the
key is set without printing it. Rotate anything you paste anywhere.

## Licence

© 2026 BYTESBRAINS PTE. LTD. All rights reserved. See [LICENSE.txt](LICENSE.txt).
