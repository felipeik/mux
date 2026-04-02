import importlib.util
import pathlib
import unittest


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "claude_cmux.py"
SPEC = importlib.util.spec_from_file_location("claude_cmux", MODULE_PATH)
claude_cmux = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(claude_cmux)


class ClaudeCmuxTests(unittest.TestCase):
    def test_build_request_classifies_permission_notification(self):
        payload = {"message": "Claude needs your approval to run swift build"}

        request = claude_cmux.build_request(
            "notification",
            payload,
            "/tmp/cmux.sock",
            "workspace:6",
            "surface:22",
        )

        self.assertEqual(request["action"], "cmux_notify")
        self.assertEqual(request["title"], "Claude Code")
        self.assertEqual(request["subtitle"], "Permission")
        self.assertEqual(request["body"], "Claude needs your approval to run swift build")
        self.assertEqual(request["cmux_socket_path"], "/tmp/cmux.sock")
        self.assertEqual(request["cmux_workspace_id"], "workspace:6")
        self.assertEqual(request["cmux_surface_id"], "surface:22")

    def test_build_request_defaults_stop_to_completed(self):
        request = claude_cmux.build_request("stop", {}, "/tmp/cmux.sock")

        self.assertEqual(request["title"], "Claude Code")
        self.assertEqual(request["subtitle"], "Completed")
        self.assertEqual(request["body"], "Claude session completed")


if __name__ == "__main__":
    unittest.main()
