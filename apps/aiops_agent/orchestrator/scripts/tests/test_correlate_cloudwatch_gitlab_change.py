#!/usr/bin/env python3
import importlib.util
import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "correlate_cloudwatch_gitlab_change.py"
SPEC = importlib.util.spec_from_file_location("correlate_cloudwatch_gitlab_change", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class FakeClient:
    def get(self, path, query=None):
        if path.endswith("/repository/commits"):
            self.query = query
            return [
                {
                    "id": "bad-commit-id",
                    "short_id": "bad-comm",
                    "title": "set Sulu down",
                    "author_name": "OQ",
                    "committed_date": "2026-07-16T06:00:00Z",
                }
            ]
        return [
            {
                "old_path": "demo/sulu-runtime.yml",
                "new_path": "demo/sulu-runtime.yml",
                "diff": "-desired_state: up\n+desired_state: down\n",
            }
        ]


class CorrelationTest(unittest.TestCase):
    def test_desired_state_change(self):
        self.assertEqual(MODULE.desired_state_change("- desired_state: up\n+ desired_state: down\n"), ("up", "down"))
        self.assertEqual(MODULE.desired_state_change("+desired_state: down\n"), (None, "down"))

    def test_selects_probable_cause(self):
        client = FakeClient()
        result = MODULE.correlate(
            client,
            project="aiops/service-management",
            config_path="demo/sulu-runtime.yml",
            alarm_time=datetime(2026, 7, 16, 6, 2, tzinfo=timezone.utc),
            alarm_name="Sulu Service Error",
            lookback_minutes=30,
        )
        self.assertTrue(result["probable_cause_found"])
        self.assertEqual(result["selected"]["commit_id"], "bad-commit-id")
        self.assertEqual(result["selected"]["desired_state"], {"from": "up", "to": "down"})
        self.assertEqual(client.query["all"], "true")

    def test_new_down_config_is_probable_cause(self):
        class NewFileClient(FakeClient):
            def get(self, path, query=None):
                value = super().get(path, query)
                if not path.endswith("/repository/commits"):
                    value[0]["diff"] = "+service: sulu\n+desired_state: down\n"
                return value

        result = MODULE.correlate(
            NewFileClient(),
            project="aiops/service-management",
            config_path="demo/sulu-runtime.yml",
            alarm_time=datetime(2026, 7, 16, 6, 2, tzinfo=timezone.utc),
            alarm_name="Sulu Service Error",
            lookback_minutes=30,
        )
        self.assertTrue(result["probable_cause_found"])
        self.assertEqual(result["selected"]["desired_state"], {"from": None, "to": "down"})


if __name__ == "__main__":
    unittest.main()
