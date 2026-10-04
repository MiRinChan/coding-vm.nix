#!/usr/bin/env python3
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import socket
import tempfile
import threading
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("runtime", Path(__file__).parents[1] / "scripts/vm-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)


class LocalControl(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def qmp_server(self, callback):
        path = self.state / "qmp.sock"
        listener = socket.socket(socket.AF_UNIX)
        listener.bind(str(path))
        listener.listen(1)
        errors = []

        def serve():
            try:
                connection, _ = listener.accept()
                with connection, connection.makefile("rb") as stream:
                    connection.sendall(b'{"QMP":{"version":{}}}\n')
                    for line in stream:
                        request = json.loads(line)
                        response = callback(request)
                        connection.sendall(json.dumps({"event": "IGNORED"}).encode() + b"\n")
                        connection.sendall(json.dumps({"return": response, "id": request["id"]}).encode() + b"\n")
            except BaseException as error:
                errors.append(error)
            finally:
                listener.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        self.addCleanup(thread.join, 3)
        return path, errors

    def test_qmp_negotiation_and_events(self):
        commands = []
        def respond(request):
            commands.append(request["execute"])
            return {"status": "running"} if request["execute"] == "query-status" else {}
        path, errors = self.qmp_server(respond)
        with runtime.QMP(path) as qmp:
            self.assertEqual(qmp.command("query-status")["status"], "running")
            qmp.command("system_powerdown")
        self.assertEqual(commands, ["qmp_capabilities", "query-status", "system_powerdown"])
        self.assertFalse(errors)

    def test_stop_waits_for_exit_and_never_sends_quit(self):
        commands = []
        path, _ = self.qmp_server(lambda request: commands.append(request["execute"]) or {})
        with patch.object(runtime, "runtime_paths", return_value={"qmp": path}), patch.object(runtime, "processes", return_value=[123]), patch.object(runtime, "alive", side_effect=[True, False]), patch.object(runtime.time, "sleep"):
            runtime.stop(self.state, 10)
        self.assertEqual(commands, ["qmp_capabilities", "system_powerdown"])

    def test_shutdown_timeout_preserves_process(self):
        path, _ = self.qmp_server(lambda request: {})
        with patch.object(runtime, "runtime_paths", return_value={"qmp": path}), patch.object(runtime, "processes", return_value=[123]), patch.object(runtime, "alive", return_value=True), patch.object(runtime.time, "monotonic", side_effect=[0, 2]):
            with self.assertRaisesRegex(RuntimeError, "No process was killed"):
                runtime.stop(self.state, 1)

    def test_stopped_instance_does_not_connect_or_send_shutdown(self):
        with patch.object(runtime, "processes", return_value=[]), patch.object(runtime, "QMP") as qmp:
            self.assertEqual(runtime.status(self.state)["state"], "stopped")
            runtime.stop(self.state, 1)
            qmp.assert_not_called()

    def test_status_detects_legacy_vm_without_qmp(self):
        with patch.object(runtime, "processes", return_value=[123]):
            result = runtime.status(self.state)
        self.assertEqual(result["state"], "running")
        self.assertFalse(result["qmp"])
        self.assertFalse(result["console"])

    def test_console_status_does_not_depend_on_qmp(self):
        path = self.state / "console.sock"
        with socket.socket(socket.AF_UNIX) as connection:
            connection.bind(str(path))
            with patch.object(runtime, "processes", return_value=[123]), patch.object(runtime, "runtime_paths", return_value={"console": str(path), "qmp": str(self.state / "missing.sock")}):
                result = runtime.status(self.state)
        self.assertTrue(result["console"])
        self.assertFalse(result["qmp"])


if __name__ == "__main__":
    unittest.main()
