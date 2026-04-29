#!/usr/bin/env python3
"""Unit tests for _supabase_client agent-registration auto-upsert."""
import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).parent))


def _fake_env():
    os.environ["SUPABASE_URL"] = "https://test.supabase.co"
    os.environ["SUPABASE_SERVICE_ROLE_KEY"] = "test-key"
    os.environ["PERCH_USER_ID"] = "00000000-0000-0000-0000-000000000001"


class TestAgentAutoRegister(unittest.TestCase):
    def setUp(self):
        _fake_env()
        # Re-import each test so the module re-reads env if needed.
        import _supabase_client
        self.mod = _supabase_client

    def _ok_response(self):
        resp = MagicMock()
        resp.status = 201
        resp.__enter__ = lambda self_: self_
        resp.__exit__ = lambda *a: None
        return resp

    def test_insert_agent_run_registers_agent_first(self):
        with patch.object(self.mod, "urlopen") as mock_urlopen:
            mock_urlopen.return_value = self._ok_response()
            ok = self.mod.insert_agent_run(
                agent_id="brand-new-agent",
                run_type="manual",
                summary={"n": 1},
            )

        self.assertTrue(ok)
        self.assertEqual(mock_urlopen.call_count, 2)

        register_req = mock_urlopen.call_args_list[0].args[0]
        run_req = mock_urlopen.call_args_list[1].args[0]

        self.assertIn("/rest/v1/agents?on_conflict=id", register_req.full_url)
        self.assertEqual(
            register_req.headers["Prefer"],
            "resolution=ignore-duplicates,return=minimal",
        )
        body = json.loads(register_req.data.decode())
        self.assertEqual(body["id"], "brand-new-agent")
        self.assertEqual(body["display_name"], "brand-new-agent")
        self.assertEqual(body["model"], "python:brand-new-agent")
        self.assertTrue(body["is_active"])
        self.assertEqual(body["owner_id"], os.environ["PERCH_USER_ID"])

        self.assertTrue(run_req.full_url.endswith("/rest/v1/agent_runs"))
        run_body = json.loads(run_req.data.decode())
        self.assertEqual(run_body["agent_id"], "brand-new-agent")
        self.assertEqual(run_body["run_type"], "manual")

    def test_ensure_agent_registered_returns_true_on_2xx(self):
        with patch.object(self.mod, "urlopen") as mock_urlopen:
            mock_urlopen.return_value = self._ok_response()
            self.assertTrue(self.mod._ensure_agent_registered("any-agent"))


if __name__ == "__main__":
    unittest.main()
