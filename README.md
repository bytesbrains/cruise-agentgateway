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
  <img src="https://img.shields.io/badge/status-draft%20%C2%B7%20unverified-b45309" alt="Status: draft" />
</p>

---

> **Status: draft. Nothing here has been run yet.**
> This repository was opened to hold the work described in [issue #1](https://github.com/bytesbrains/cruise-agentgateway/issues/1).
> The configuration below follows agentgateway's documented OpenAI-compatible provider shape but has
> **not** been executed against a live gateway. Do not treat it as a working recipe until issue #1 is closed.

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

This repository holds the configuration, a runnable demo and a smoke test that proves the path works.

| | |
| --- | --- |
| **Product** | [bytesbrains.com/cruise](https://bytesbrains.com/cruise) |
| **Cruise API** | `https://cruise.bytesbrains.net/v1` |
| **agentgateway** | [agentgateway.dev](https://agentgateway.dev) · [GitHub](https://github.com/agentgateway/agentgateway) |
| **Source** | [bytesbrains/cruise-agentgateway](https://github.com/bytesbrains/cruise-agentgateway) |

## Planned contents

| Path | What it is |
| --- | --- |
| `config/standalone/` | agentgateway standalone config pointing at Cruise |
| `config/kubernetes/` | `AgentgatewayBackend`, `Secret` and the `BackendTLSPolicy` a custom HTTPS host requires |
| `compose/` | `docker compose up` → agentgateway (upstream image) + Cruise, one working call |
| `smoke.sh` | Stand it up, send one cheap completion through Cruise, assert a 200 |

Samples are held to one rule: **each must demonstrate something only Cruise does** — a spend cap tripping
mid-run, or spend grouped by lane across calls. A sample that merely shows a model answering through a
gateway demonstrates agentgateway, not Cruise, and does not belong here.

## The gotcha this repo exists to document

agentgateway enables TLS automatically for well-known provider hosts, but a **custom `host` override
requires an explicit `BackendTLSPolicy`** for HTTPS endpoints. Pointing a backend at
`cruise.bytesbrains.net` without it is the first thing that will break. See agentgateway's
[OpenAI-compatible providers](https://agentgateway.dev/docs/kubernetes/latest/llm/providers/openai-compatible/) docs.

## Draft configuration — unverified

```yaml
# Shape only. Not yet run against a live gateway — see issue #1.
# Cruise speaks the OpenAI API, so it is configured as an `openai` provider with host overrides.
provider:
  openai:
    host: cruise.bytesbrains.net
    port: 443
    path: /v1
    # Auth: a Cruise key (cru_...) supplied as a Bearer token from a Secret, never inline.
```

## Licence

© 2026 BYTESBRAINS PTE. LTD. All rights reserved. See [LICENSE.txt](LICENSE.txt).
