import importlib.util
import pathlib
import types
import unittest
from unittest import mock


MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "host-proxy.py"
SPEC = importlib.util.spec_from_file_location("host_proxy", MODULE_PATH)
host_proxy = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(host_proxy)


class HostProxyNotificationTests(unittest.TestCase):
    @mock.patch.object(host_proxy.subprocess, "run")
    def test_run_cmux_notify_executes_cmux_notify_with_socket(self, run_mock):
        run_mock.return_value = types.SimpleNamespace(returncode=0, stdout="", stderr="")

        host_proxy.run_cmux_notify(
            {
                "title": "Claude Code",
                "subtitle": "Permission",
                "body": "Needs approval",
                "cmux_socket_path": "/tmp/cmux.sock",
                "cmux_workspace_id": "workspace:1",
                "cmux_surface_id": "surface:2",
            }
        )

        run_mock.assert_called_once_with(
            [
                "cmux",
                "notify",
                "--workspace",
                "workspace:1",
                "--surface",
                "surface:2",
                "--title",
                "Claude Code",
                "--subtitle",
                "Permission",
                "--body",
                "Needs approval",
            ],
            capture_output=True,
            text=True,
            timeout=5,
            env=mock.ANY,
        )
        env = run_mock.call_args.kwargs["env"]
        self.assertEqual(env["CMUX_SOCKET_PATH"], "/tmp/cmux.sock")
        self.assertNotIn("CMUX_WORKSPACE_ID", env)
        self.assertNotIn("CMUX_SURFACE_ID", env)

    def test_run_cmux_notify_requires_socket_path(self):
        with self.assertRaisesRegex(ValueError, "cmux_socket_path"):
            host_proxy.run_cmux_notify(
                {
                    "title": "Claude Code",
                    "subtitle": "Permission",
                    "body": "Needs approval",
                }
            )


if __name__ == "__main__":
    unittest.main()
