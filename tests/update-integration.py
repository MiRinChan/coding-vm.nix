#!/usr/bin/env python3
"""Build disposable instances and test updates across two default profiles."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

project = Path(__file__).parents[1]


def command(*args):
    subprocess.run(args, check=True, stdout=subprocess.DEVNULL)


with tempfile.TemporaryDirectory(prefix="coding-vm-update-") as temporary:
    root = Path(temporary)
    checkout, state = root / "checkout", root / "state"
    files = subprocess.check_output(["git", "-C", str(project), "ls-files"], text=True).splitlines()
    for name in files:
        target = checkout / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(project / name, target)
    command("git", "init", "-q", str(checkout))

    def commit():
        command("git", "-C", str(checkout), "add", ".")
        command("git", "-C", str(checkout), "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false", "commit", "-qm", "Test configuration")

    def vm(*args, success=True):
        result = subprocess.run(["python3", str(project / "scripts/manage-vm.py"), "--project", str(checkout), "--state-dir", str(state), *args], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if (result.returncode == 0) != success:
            raise AssertionError(result.stdout + result.stderr)
        return result

    def manifest():
        return json.loads((state / "manager/current/manifest.json").read_text())

    commit()
    vm("init")
    original = manifest()
    assert original["settings"]["defaultsVersion"] == 1
    profile = (checkout / "profiles/v1.nix").read_text()
    (checkout / "profiles/v2.nix").write_text(profile.replace("defaultsVersion = 1;", "defaultsVersion = 2;").replace("America/Los_Angeles", "America/New_York").replace("preallocateDisk = false;", "preallocateDisk = true;"))
    (checkout / "settings.nix").write_text("import ./profiles/v2.nix\n")
    normalizer = checkout / "lib/normalize-settings.nix"
    normalizer.write_text(normalizer.read_text().replace("else throw", "else if version == 2 then import ../profiles/v2.nix else throw"))
    commit()
    vm("update", "--no-fetch")
    assert manifest() == original, "Ordinary update changed the instance defaults"
    vm("upgrade-defaults", "--no-fetch", "--yes")
    upgraded = manifest()["settings"]
    assert upgraded["defaultsVersion"] == 2
    assert upgraded["resources"]["preallocateDisk"] is True
    assert upgraded["spoofSettings"]["region"]["timeZone"] == "America/New_York"
    vm("rollback")
    assert manifest() == original, "Rollback did not restore the configuration"
    base = checkout / "modules/system/base.nix"
    base.write_text(base.read_text().replace("system.stateVersion =", "networking.firewall.allowedTCPPorts = [9999];\n  system.stateVersion ="))
    commit()
    selected = (state / "manager/current").resolve()
    result = vm("update", "--no-fetch", success=False)
    assert "Behavior changed" in result.stderr
    assert (state / "manager/current").resolve() == selected
    assert manifest() == original
    assert not list((state / "manager/generations").glob(".candidate-*"))
    vm("update", "--no-fetch", "--accept-behavior-changes")
    assert 9999 in manifest()["effective"]["firewall"]["allowedTCPPorts"]
    assert len(list((state / "manager/generations").glob("*/runner"))) == 2
    vm("rollback")
    assert manifest() == original
    print("OK: real builds preserve defaults, adopt explicit changes, block unexpected behavior, and roll back")
