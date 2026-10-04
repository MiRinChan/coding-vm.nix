#!/usr/bin/env python3
"""Check that management and control commands select the same instance."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

project = Path(__file__).parents[1]
spec = importlib.util.spec_from_file_location("manager", project / "scripts/manage-vm.py")
manager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(manager)


class StateDirectory(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.checkout = self.root / "checkout"
        scripts = self.checkout / "scripts"
        scripts.mkdir(parents=True)
        control = (project / "scripts/control.sh").read_text().split('if [ -x "$state/runtime-python" ]', 1)[0]
        (scripts / "control.sh").write_text(control + '\nprintf "%s" "$state"\n')
        self.tools = self.root / "tools"
        self.tools.mkdir()
        fuse = self.tools / "fusermount3"
        fuse.write_text('#!/bin/sh\nexit 0\n')
        fuse.chmod(0o755)
        self.runners = self.root / "runners"
        self.runners.mkdir()
        (self.runners / "run-test-vm").touch()
        self.environment = dict(os.environ)
        self.environment.pop("VM_STATE_DIR", None)
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, self.environment, clear=True).start()

    def check_commands(self, expected, override=None):
        environment = dict(self.environment)
        if override is not None:
            environment["VM_STATE_DIR"] = str(override)
        with patch.dict(os.environ, environment, clear=True):
            self.assertEqual(manager.state_directory(self.checkout).resolve(), expected.resolve())
        environment["PATH"] = str(self.tools) + ":" + environment["PATH"]
        for command in ("status", "stop", "console"):
            selected = subprocess.check_output(["bash", str(self.checkout / "scripts/control.sh"), command], env=environment, text=True)
            self.assertEqual(Path(selected).resolve(), expected.resolve())
        # Inspect launcher selection before disk preparation or any host changes.
        prefix = (project / "scripts/run-vm.sh").read_text().split("# First boot", 1)[0]
        environment.update(CODING_VM_PROJECT_ROOT=str(self.checkout), VM_RUNNER_DIR=str(self.runners), VM_REQUIRE_TAILSCALE_EXIT="0")
        selected = subprocess.check_output(["bash", "-c", prefix + '\nprintf "%s" "$VM_STATE_DIR"\n'], env=environment, text=True)
        self.assertEqual(Path(selected), expected.resolve())

    def test_new_instance_uses_home_state_directory(self):
        self.check_commands(Path.home() / ".local/state/coding-vm")
        self.assertFalse((self.checkout / ".vm-state").exists())

    def test_existing_project_state_keeps_its_disk(self):
        state = self.checkout / ".vm-state"
        state.mkdir()
        self.check_commands(state)

    def test_relative_pointer_selects_instance(self):
        (self.checkout / ".instance-state").write_text("../saved-state\n")
        self.check_commands(self.root / "saved-state")

    def test_absolute_pointer_selects_instance(self):
        state = self.root / "saved-state"
        (self.checkout / ".instance-state").write_text(str(state) + "\n")
        self.check_commands(state)

    def test_environment_overrides_pointer_and_legacy_state(self):
        (self.checkout / ".vm-state").mkdir()
        (self.checkout / ".instance-state").write_text("../saved-state\n")
        self.check_commands(self.root / "override", self.root / "override")

    def test_cli_directory_overrides_environment(self):
        with patch.dict(os.environ, {"VM_STATE_DIR": str(self.root / "environment")}):
            state = self.root / "explicit"
            self.assertEqual(manager.state_directory(self.checkout, state), state)


if __name__ == "__main__":
    unittest.main()
