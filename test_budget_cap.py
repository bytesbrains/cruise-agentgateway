"""Contract edge cases without Docker, credentials, or real waits."""

import contextlib
import io
import json
import unittest
from unittest.mock import patch

import budget_cap


def response(spend="0.0000", status=200, **overrides):
    headers = {
        "x-cruise-budget-period": "minute",
        "x-cruise-budget-limit": "0.01",
        "x-cruise-budget-spend": spend,
        "x-cruise-budget-state": "ok" if status == 200 else "hard",
        "x-cruise-lane": "bb/summarization",
        "x-cruise-model": "demo-model",
        "retry-after": "1",
    }
    headers.update(overrides)
    body = {"choices": [{"message": {"content": "OK"}}]} if status == 200 else {
        "error": {"code": "budget_exhausted"}}
    return status, headers, json.dumps(body).encode()


class CapTest(unittest.TestCase):
    def run_demo(self, responses):
        with patch.object(budget_cap, "completion", side_effect=responses), \
                patch.object(budget_cap.time, "sleep"), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            budget_cap.run()
        self.assertIn("PASS:", output.getvalue())

    def test_cap_and_recovery(self):
        self.run_demo([response(f"0.00{i}0") for i in (0, 2, 4, 6, 8)] + [
            response("0.0100", 429), response()])

    def test_already_capped_key_gets_fresh_window(self):
        self.run_demo([response("0.0100", 429), response()] + [
            response(f"0.00{i}0") for i in (2, 4, 6, 8)] + [
            response("0.0100", 429), response()])

    def test_minute_boundary_during_calls(self):
        self.run_demo([response("0.0080"), response(), response("0.0020"),
                       response("0.0040"), response("0.0060"), response("0.0080"),
                       response("0.0100", 429), response()])

    def test_missing_or_wrong_telemetry_fails(self):
        cases = [
            {"x-cruise-budget-period": "day"},
            {"x-cruise-budget-limit": "5.00"},
            {"x-cruise-budget-spend": "NaN"},
            {"x-cruise-budget-spend": "0.0120"},
            {"x-cruise-lane": ""},
            {"x-cruise-model": ""},
        ]
        for headers in cases:
            with self.subTest(headers=headers), patch.object(
                    budget_cap, "completion", return_value=response(**headers)):
                with self.assertRaises(budget_cap.DemoFailure):
                    budget_cap.observe()

    def test_other_429_is_not_a_budget_pass(self):
        status, headers, _ = response("0.0100", 429)
        with patch.object(budget_cap, "completion", return_value=(
                status, headers, b'{"error":{"code":"rate_limit_exceeded"}}')):
            with self.assertRaisesRegex(budget_cap.DemoFailure, "not budget_exhausted"):
                budget_cap.observe()

    def test_invalid_retry_after_fails(self):
        for retry in ("", "0", "61", "NaN", "1.5"):
            with self.subTest(retry=retry), patch.object(
                    budget_cap, "completion", return_value=response(
                        "0.0100", 429, **{"retry-after": retry})):
                with self.assertRaisesRegex(budget_cap.DemoFailure, "retry-after"):
                    budget_cap.observe()

    def test_no_cap_has_bounded_attempts(self):
        with self.assertRaisesRegex(budget_cap.DemoFailure, "within 20 calls"):
            self.run_demo([response()] * 20)

    def test_no_recovery_fails(self):
        with self.assertRaisesRegex(budget_cap.DemoFailure, "Still refused"):
            self.run_demo([response("0.0100", 429)] * 2)


if __name__ == "__main__":
    unittest.main()
