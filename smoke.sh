#!/usr/bin/env bash
#
# Stand up agentgateway in front of Cruise, prove a completion goes through, and
# prove the thing that makes the pairing worth having: Cruise's per-request lane
# and budget telemetry survives the gateway.
#
#   ./smoke.sh          stand up, assert, tear down
#   ./smoke.sh --keep    leave the gateway running afterwards
#   ./smoke.sh --budget-cap   prove the free demo cap and recovery (needs python3)
#
# Needs: docker, curl. Reads CRUISE_API_KEY from .env at the repo root.
# Defaults to the free Cruise demo, so this costs nothing to run.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
compose=(docker compose --env-file "$repo_root/.env" -f "$repo_root/compose/docker-compose.yml")
gateway="http://localhost:4000"
readiness="http://localhost:19001/healthz/ready"
keep=false
budget_cap=false
for arg in "$@"; do
  case "$arg" in
    --keep) keep=true ;;
    --budget-cap) budget_cap=true ;;
    *) printf 'Usage: %s [--keep] [--budget-cap]\n' "$0" >&2; exit 2 ;;
  esac
done
started=false

pass=0
fail=0

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; pass=$((pass + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=$((fail + 1)); }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }

# Temp files and the single cleanup trap are installed before anything that can
# abort, so there is one cleanup contract rather than two.
hdr="$(mktemp)"
body="$(mktemp)"

cleanup() {
  rm -f "$hdr" "$body"
  if [[ "$started" != true ]]; then
    return
  elif [[ "$keep" == true ]]; then
    printf '\nLeaving the gateway up on %s (--keep). Stop it with:\n  %s down\n' \
      "$gateway" "${compose[*]}"
  else
    say "Tearing down"
    "${compose[@]}" down --remove-orphans >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# Reads one header value out of the last response curl dumped into $hdr. curl
# truncates that file on every -D, including when the connection fails outright,
# so a value here is always from the most recent attempt.
header() {
  awk -v k="$1" 'BEGIN{IGNORECASE=1} tolower($1)==tolower(k)":" {sub(/\r$/,""); $1=""; sub(/^ /,""); print}' "$hdr"
}

# ---------------------------------------------------------------- preflight --

say "Preflight"

# Checked explicitly so a missing tool reports itself, rather than surfacing
# later as "the gateway never became ready".
for tool in curl docker; do
  command -v "$tool" >/dev/null 2>&1 || { bad "$tool is not installed"; exit 1; }
done
docker compose version >/dev/null 2>&1 || { bad "docker compose (v2) is not available"; exit 1; }
ok "docker and curl present"

if [[ ! -f "$repo_root/.env" ]]; then
  bad ".env not found. Copy .env.example to .env and put a cru_ key in it."
  exit 1
fi

# Each value is read in a subshell, so .env cannot overwrite this script's own
# variables, and returned by command substitution, so no key is printed.
# Compose reads normal credentials from .env; the cap override selects its
# separate key only for this run.
env_value() { (. "$repo_root/.env"; printf '%s' "${!1:-}"); }
base_url="$(env_value CRUISE_BASE_URL)"
if [[ "$budget_cap" == true ]]; then
  command -v python3 >/dev/null 2>&1 || { bad "--budget-cap needs python3"; exit 1; }
  if [[ "${base_url:-https://cruise-demo.bytesbrains.net/v1}" != "https://cruise-demo.bytesbrains.net/v1" ]]; then
    bad "--budget-cap only runs against https://cruise-demo.bytesbrains.net/v1"
    exit 1
  fi
  cap_key="$(env_value CRUISE_DEMO_CAP_API_KEY)"
  if [[ "$cap_key" != cru_demo_* || "$cap_key" == cru_demo_replace_me ]]; then
    bad "Set CRUISE_DEMO_CAP_API_KEY in .env to your dashboard's hard-cap demo key"
    exit 1
  fi
  compose+=(-f "$repo_root/compose/docker-compose.cap.yml")
fi
if [[ "$budget_cap" != true && -z "$(env_value CRUISE_API_KEY)" ]]; then
  bad "CRUISE_API_KEY is empty in .env"
  exit 1
fi
ok "gateway key is set"

# ------------------------------------------------------------------ bring up --

say "Starting agentgateway (upstream image, no build)"
started=true
"${compose[@]}" up -d --quiet-pull

# curl's exit status is tracked separately from the HTTP status, so "could not
# connect at all" and "connected, not ready yet" fail with different messages.
ready=false
probe_rc=0
probe_code=""
for _ in $(seq 1 60); do
  if probe_code="$(curl -s -o /dev/null -w '%{http_code}' "$readiness" 2>/dev/null)"; then
    probe_rc=0
    [[ "$probe_code" == "200" ]] && { ready=true; break; }
  else
    probe_rc=$?
  fi
  sleep 1
done

if [[ "$ready" == true ]]; then
  ok "gateway ready on $gateway"
else
  if [[ "$probe_rc" -ne 0 ]]; then
    bad "could not reach $readiness at all (curl exit $probe_rc) — is the container up?"
  else
    bad "gateway never became ready (last status: ${probe_code:-none})"
  fi
  "${compose[@]}" logs --tail 40
  exit 1
fi

if [[ "$budget_cap" == true ]]; then
  say "Hard cap through the gateway (emulated charges, no real spend)"
  python3 "$repo_root/budget_cap.py"
  exit "$?"
fi

# ------------------------------------------------------------------ the call --

say "One completion through the gateway to Cruise"

code="$(curl -s -D "$hdr" -o "$body" -w '%{http_code}' \
  -X POST "$gateway/v1/chat/completions" \
  -H 'content-type: application/json' \
  -d '{"model":"bb/summarization","messages":[{"role":"user","content":"Reply with the single word: OK"}],"max_tokens":16}')" \
  || { bad "curl could not reach $gateway"; exit 1; }

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

# Presence is not enough: a budget header that arrives saying the project is out
# of credit should fail a smoke test, not be printed as a pass. `ok` is the only
# healthy value observed; widen this list if Cruise defines more.
bstate="$(header x-cruise-budget-state)"
case "$bstate" in
  ok) ok "budget state is healthy: ok" ;;
  "") bad "x-cruise-budget-state missing" ;;
  *)  bad "budget state is '$bstate', not 'ok' — the project may be capped or out of credit" ;;
esac

# ------------------------------------------------------------ lane routing --
#
# Cruise picks a member model per lane. Same gateway, same catch-all config, and
# the routing decision still belongs to Cruise — nothing about these lanes is
# named in the gateway's configuration.

say "Lane routing, one call each"
printf '  %-22s %-14s %s\n' "LANE REQUESTED" "BUDGET" "MODEL CRUISE CHOSE"

lane_models=()
for lane in bb/summarization bb/extraction bb/code-review; do
  lane_code="$(curl -s -D "$hdr" -o /dev/null -w '%{http_code}' \
    -X POST "$gateway/v1/chat/completions" \
    -H 'content-type: application/json' \
    -d "{\"model\":\"$lane\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":8}")" \
    || { bad "$lane — curl could not reach the gateway"; continue; }

  lane_model="$(header x-cruise-model)"
  lane_echo="$(header x-cruise-lane)"

  # Each failure reports what actually went wrong. "returned 200" on its own
  # reads as a pass, and a 200 with the telemetry stripped is precisely the
  # upstream regression this script exists to catch.
  if [[ "$lane_code" != "200" ]]; then
    bad "$lane — HTTP $lane_code"
    continue
  fi
  if [[ -z "$lane_model" ]]; then
    bad "$lane — HTTP 200 but no x-cruise-model header: the gateway stripped Cruise's telemetry"
    continue
  fi
  if [[ "$lane_echo" != "$lane" ]]; then
    bad "$lane — Cruise booked this against '${lane_echo:-nothing}': the lane did not survive the gateway"
    continue
  fi

  printf '  %-22s %-14s %s\n' "$lane" "$(header x-cruise-budget-state)" "$lane_model"
  lane_models+=("$lane_model")
  pass=$((pass + 1))
done

# The README's lane-routing claim rests on Cruise choosing per lane. That is a
# property of Cruise's catalogue, not of this integration, so a collapse is
# reported rather than failed — the assertions that can fail are above.
if [[ "${#lane_models[@]}" -ge 2 ]]; then
  distinct="$(printf '%s\n' "${lane_models[@]}" | sort -u | wc -l | tr -d ' ')"
  if [[ "$distinct" -gt 1 ]]; then
    ok "Cruise chose $distinct different models across ${#lane_models[@]} lanes"
  else
    warn "all ${#lane_models[@]} lanes resolved to $distinct model — legitimate if the catalogue narrowed, but the lane-routing claim rests on this"
  fi
fi

# ------------------------------------------------------------------- result --

say "Result"
printf '  %d passed, %d failed\n\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
