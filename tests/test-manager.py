#!/usr/bin/env python3
"""Exercise generation transactions without starting a VM."""
import argparse
import contextlib
import io
import importlib.util
import json
import re
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("manager", Path(__file__).parents[1] / "scripts/manage-vm.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Transactions(unittest.TestCase):
    def setUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.project = Path(__file__).parents[1]
        self.manager = module.Manager(self.project, Path(self.temp.name))
        self.args = argparse.Namespace(no_fetch=True, accept_behavior_changes=False, yes=True, settings=None)
        self.defaults = {"defaultsVersion": 1, "user": "alice", "system": "x86_64-linux", "hostName": "coding-vm", "launcher": {"sshPort": 2222}, "systemStateVersion": "25.11", "region": "SF"}
        self.settings = dict(self.defaults, region="NYC")
        self.behavior = "old"
        self.version = "1"
        self.fail_build = False
        self.addCleanup(patch.stopall)
        patch.object(self.manager, "source", return_value=("source", "abc123")).start()
        patch.object(self.manager, "defaults", side_effect=lambda _: self.defaults.copy()).start()
        patch.object(self.manager, "candidate", side_effect=self.candidate).start()
        patch.object(module, "run", side_effect=self.fake_run).start()

    def candidate(self, source, text):
        directory = Path(tempfile.mkdtemp(prefix=".candidate-", dir=self.manager.generations))
        settings = dict(self.settings)
        settings["launcher"] = {"sshPort": int(re.search(r'"sshPort" = (\d+);', text)[1])}
        settings["defaultsVersion"] = int(re.search(r'"defaultsVersion" = (\d+);', text)[1])
        settings["region"] = re.search(r'"region" = "([^"]+)";', text)[1]
        (directory / "settings.nix").write_text(module.nix_value(settings) + "\n")
        manifest = {"settings": settings, "effective": self.behavior}
        versions = [{"name": "tool", "version": self.version}]
        (directory / "manifest.json").write_text(json.dumps(manifest))
        (directory / "versions.json").write_text(json.dumps(versions))
        return directory, settings, manifest, versions

    def fake_run(self, *args, **kwargs):
        if args[:2] == ("nix", "build"):
            if self.fail_build:
                raise RuntimeError("Build failed")
            return '[{"outputs":{"out":"/mock/store/runner"}}]'
        if args[0] == "nix-store":
            Path(args[2]).symlink_to("/mock/store/runner")
            return 0
        raise AssertionError(args)

    def initialize(self):
        self.manager.promote(*self.candidate("source", module.nix_value(self.settings) + "\n")[:1], "source", "initial", self.settings, True)

    def test_package_update_preserves_instance_and_rollback(self):
        self.initialize()
        first = self.manager.selected()
        self.version = "2"
        self.manager.change("update", self.args)
        self.assertEqual(self.manager.settings.read_text(), module.nix_value(self.settings) + "\n")
        self.assertEqual(self.manager.selected("previous"), first)
        self.manager.rollback(self.args)
        self.assertEqual(self.manager.selected(), first)

    def test_effective_behavior_change_requires_acceptance(self):
        self.initialize()
        first = self.manager.selected()
        self.behavior = "new"
        with self.assertRaisesRegex(RuntimeError, "Behavior changed"):
            self.manager.change("update", self.args)
        self.assertEqual(self.manager.selected(), first)
        self.assertFalse(list(self.manager.generations.glob(".candidate-*")))
        self.args.accept_behavior_changes = True
        self.manager.change("update", self.args)
        self.assertNotEqual(self.manager.selected(), first)

    def test_failed_build_keeps_selection_settings_and_previous(self):
        self.initialize()
        before = self.manager.selected()
        self.fail_build = True
        with self.assertRaisesRegex(RuntimeError, "Build failed"):
            self.manager.change("upgrade-defaults", self.args)
        self.assertEqual(self.manager.selected(), before)
        self.assertIsNone(self.manager.selected("previous"))
        self.assertEqual(self.manager.settings.read_text(), module.nix_value(self.settings) + "\n")

    def test_explicit_defaults_upgrade_and_rollback(self):
        self.initialize()
        self.defaults["launcher"] = {"sshPort": 9999}
        self.defaults["defaultsVersion"] = 2
        self.manager.change("upgrade-defaults", self.args)
        settings = json.loads((self.manager.selected() / "manifest.json").read_text())["settings"]
        self.assertEqual(settings["region"], "SF")
        self.assertEqual(settings["defaultsVersion"], 2)
        self.assertEqual(settings["launcher"]["sshPort"], 2222)
        self.manager.rollback(self.args)
        self.assertEqual(self.manager.settings.read_text(), module.nix_value(self.settings) + "\n")

    def test_start_refuses_unapplied_edits(self):
        self.initialize()
        self.manager.settings.write_text("{ user = \"bob\"; }")
        with self.assertRaisesRegex(RuntimeError, "pending edits"):
            self.manager.start(self.args)

    def test_serializer_escapes_nix_interpolation(self):
        self.assertEqual(module.nix_value("${secret}"), '"\\${secret}"')


if __name__ == "__main__":
    unittest.main()
