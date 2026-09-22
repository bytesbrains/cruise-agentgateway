"""Verify the demo-cap contract through the gateway started by smoke.sh."""

import json
import re
import time
import urllib.error
import urllib.request
from decimal import Decimal


class DemoFailure(Exception):
    pass


def completion():
    request = urllib.request.Request(
        "http://localhost:4000/v1/chat/completions",
        data=json.dumps({
            "model": "bb/summarization",
            "messages": [{"role": "user", "content": "Reply with OK"}],
            "max_tokens": 8,
        }).encode(),
        # The gateway forwards the client's User-Agent, and the demo's edge
        # rejects urllib's default one with a 403 (Cloudflare error 1010).
        headers={"Content-Type": "application/json", "User-Agent": "cruise-agentgateway-smoke"},
    )
    try:
        response = urllib.request.urlopen(request, timeout=15)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read()


def require(condition, message):
    if not condition:
        raise DemoFailure(message)


def money(headers, name):
    value = headers.get(name, "")
    require(bool(re.fullmatch(r"[0-9]+(?:\.[0-9]+)?", value)), f"Missing or invalid {name}")
    return Decimal(value)


def observe():
    status, headers, body = completion()
    require(status in (200, 429), f"Expected HTTP 200 or 429, got {status}")
    require(headers.get("x-cruise-budget-period") == "minute",
            "Expected a minute budget; use the dashboard's hard-cap key")
    require(money(headers, "x-cruise-budget-limit") == Decimal("0.01"),
            "Expected the demo-cap $0.01 limit")
    spend = money(headers, "x-cruise-budget-spend")
    require(Decimal(0) <= spend <= Decimal("0.01"), "Spend exceeded the cap")
    try:
        payload = json.loads(body)
    except (ValueError, UnicodeError):
        raise DemoFailure("Response body is not JSON") from None
    require(isinstance(payload, dict), "Expected a JSON object")
    if status == 200:
        require(headers.get("x-cruise-budget-state") == "ok", "Served request has unhealthy budget state")
        require(headers.get("x-cruise-lane") == "bb/summarization", "Lane header did not survive")
        require(bool(headers.get("x-cruise-model")), "Model header did not survive")
        require(bool(payload.get("choices")), "HTTP 200 did not contain a completion")
        print(f"  HTTP 200: pre-request spend ${spend:.4f}, budget ok", flush=True)
        return spend, None
    error = payload.get("error")
    require(isinstance(error, dict) and error.get("code") == "budget_exhausted",
            "HTTP 429 was not budget_exhausted")
    require(headers.get("x-cruise-budget-state") == "hard", "Refusal lost the hard budget state")
    retry = headers.get("retry-after", "")
    require(bool(re.fullmatch(r"[0-9]+", retry)) and 1 <= int(retry) <= 60,
            "Expected retry-after between 1 and 60 seconds")
    require(spend == Decimal("0.01"), "Budget refused before the expected $0.01 spend")
    print(f"  HTTP 429: budget_exhausted, spend ${spend:.4f}, retry-after {retry}s", flush=True)
    return spend, int(retry)


def run():
    # A previously used key may already be capped; a run may also cross a minute.
    # Bound both requests and time so a wrong or broken demo never loops forever.
    deadline = time.monotonic() + 180
    previous = None
    rose = False
    for _ in range(20):
        require(time.monotonic() < deadline, "Timed out waiting for a complete cap cycle")
        spend, retry = observe()
        if retry is None:
            if previous is not None and spend > previous:
                require(spend - previous == Decimal("0.002"),
                        "Unexpected charge; stop other calls to this demo-cap project")
                rose = True
            previous = spend
            continue
        # retry-after is seconds until the next window. A one-second margin
        # avoids racing the reset; each individual sleep stays at most 60s.
        print(f"  Waiting {retry + 1}s for the minute budget to reset…", flush=True)
        time.sleep(retry)
        time.sleep(1)
        recovered, refusal = observe()
        require(refusal is None, "Still refused after retry-after")
        require(recovered < spend, "Spend did not reset after retry-after")
        if rose:
            print("  PASS: spend rose, the cap refused a call, and service recovered through agentgateway.", flush=True)
            return
        print("  Key was already near its cap; checking the new window.", flush=True)
        previous = recovered
    raise DemoFailure("No complete cap cycle within 20 calls; check the demo-cap project")


if __name__ == "__main__":
    try:
        run()
    except (DemoFailure, OSError, urllib.error.URLError) as error:
        print(f"  FAIL: {error}", flush=True)
        raise SystemExit(1)
