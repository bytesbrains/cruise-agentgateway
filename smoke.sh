#!/usr/bin/env bash
#
# Stand up agentgateway in front of Cruise, prove a completion goes through, and
# prove the thing that makes the pairing worth having: Cruise's per-request lane
# and budget telemetry survives the gateway.
#
#   ./smoke.sh          stand up, assert, tear down
#   ./smoke.sh --keep    leave the gateway running afterwards
#
# Needs: docker, curl. Reads CRUISE_API_KEY from .env at the repo root.
# Defaults to the free Cruise demo, so this costs nothing to run.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose=(docker compose --env-file "$repo_root/.env" -f "$repo_root/compose/docker-compose.yml")
gateway="http://localhost:4000"
readiness="http://localhost:19001/healthz/ready"
keep=false
[[ "${1:-}" == "--keep" ]] && keep=true

pass=0
fail=0

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail + 1)); }

cleanup() {
  if [[ "$keep" == true ]]; then
    printf '\nLeaving the gateway up on %s (--keep). Stop it with:\n  %s down\n' \
      "$gateway" "${compose[*]}"
  else
    say "Tearing down"
    "${compose[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# ---------------------------------------------------------------- preflight --

say "Preflight"

if [[ ! -f "$repo_root/.env" ]]; then
  bad ".env not found. Copy .env.example to .env and put a cru_ key in it."
  exit 1
fi

# Sourced in a subshell check so the key is never echoed.
if ! (set -a; . "$repo_root/.env"; set +a; [[ -n "${CRUISE_API_KEY:-}" ]]); then
  bad "CRUISE_API_KEY is empty in .env"
  exit 1
fi
ok "CRUISE_API_KEY is set"

# ------------------------------------------------------------------- bring up --

say "Starting agentgateway (upstream image, no build)"
"${compose[@]}" up -d --quiet-pull

for _ in $(seq 1 60); do
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "$readiness" || true)" == "200" ]]; then
    ok "gateway ready on $gateway"
    break
  fi
  sleep 1
done

if [[ "$(curl -s -o /dev/null -w '%{http_code}' "$readiness" || true)" != "200" ]]; then
  bad "gateway never became ready"
  "${compose[@]}" logs --tail 40
  exit 1
fi

# ------------------------------------------------------------------ the call --

hdr="$(mktemp)"; body="$(mktemp)"
trap 'rm -f "$hdr" "$body"; cleanup' EXIT

header() { awk -v k="$1" 'BEGIN{IGNORECASE=1} tolower($1)==tolower(k)":" {sub(/\r$/,""); $1=""; sub(/^ /,""); print}' "$hdr"; }

say "One completion through the gateway to Cruise"

code="$(curl -s -D "$hdr" -o "$body" -w '%{http_code}' \
  -X POST "$gateway/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d '{"model":"bb/summarization","messages":[{"role":"user","content":"Reply with the single word: OK"}],"max_tokens":16}')"

if [[ "$code" == "200" ]]; then
  ok "HTTP 200 from Cruise through agentgateway"
else
  bad "expected HTTP 200, got $code"
  head -c 400 "$body"; echo
  exit 1
fi

# --------------------------------------------------- what only Cruise gives --
#
# A model answering through a gateway demonstrates agentgateway. These headers
# are the part only Cruise does, and the point of asserting them is that a proxy
# is free to strip unknown x- headers on the way back. This one does not.

say "Cruise telemetry survived the proxy"

for h in x-cruise-lane x-cruise-model x-cruise-budget-state x-cruise-budget-limit; do
  v="$(header "$h")"
  if [[ -n "$v" ]]; then ok "$h: $v"; else bad "$h missing — the gateway stripped it"; fi
done

[[ "$(header x-cruise-lane)" == "bb/summarization" ]] \
  && ok "the lane that was asked for is the lane that was billed" \
  || bad "lane mismatch"

# ------------------------------------------------------------ lane routing --
#
# Cruise picks a member model per lane. Same gateway, same catch-all config, and
# the routing decision still belongs to Cruise — nothing about these lanes is
# named in the gateway's configuration.

say "Lane routing, one call each"
printf '  %-22s %-14s %s\n' "LANE REQUESTED" "BUDGET" "MODEL CRUISE CHOSE"

for lane in bb/summarization bb/extraction bb/code-review; do
  lane_code="$(curl -s -D "$hdr" -o /dev/null -w '%{http_code}' \
    -X POST "$gateway/v1/chat/completions" \
    -H 'content-type: application/json' \
    -d "{\"model\":\"$lane\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":8}")"

  if [[ "$lane_code" == "200" && -n "$(header x-cruise-model)" ]]; then
    printf '  %-22s %-14s %s\n' "$lane" "$(header x-cruise-budget-state)" "$(header x-cruise-model)"
    pass=$((pass + 1))
  else
    bad "$lane returned $lane_code"
  fi
done

# ------------------------------------------------------------------- result --

say "Result"
printf '  %d passed, %d failed\n\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
