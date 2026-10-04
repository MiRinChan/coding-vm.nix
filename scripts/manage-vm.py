#!/usr/bin/env python3
"""Keep instance settings and built generations separate from the upstream checkout."""
import argparse
import contextlib
import datetime
import difflib
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import uuid


def run(*args, capture=True):
    return subprocess.check_output(args, text=True).strip() if capture else subprocess.check_call(args)


def nix_value(value):
    if isinstance(value, dict):
        return "{\n" + "\n".join(f'{json.dumps(k)} = {nix_value(v)};' for k, v in sorted(value.items())) + "\n}"
    if isinstance(value, list):
        return "[ " + " ".join(nix_value(v) for v in value) + " ]"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False).replace("${", "\\${")
    return str(value)


def diff(old, new):
    a = json.dumps(old, indent=2, sort_keys=True, ensure_ascii=False).splitlines()
    b = json.dumps(new, indent=2, sort_keys=True, ensure_ascii=False).splitlines()
    return "\n".join(difflib.unified_diff(a, b, fromfile="current", tofile="candidate", lineterm=""))


def atomic_text(path, text):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text)
    temporary.replace(path)


def state_directory(project, explicit=None):
    if explicit is not None:
        return explicit
    if os.environ.get("VM_STATE_DIR"):
        return Path(os.environ["VM_STATE_DIR"])
    pointer = project / ".instance-state"
    if pointer.is_file():
        return project / pointer.read_text().strip()
    legacy = project / ".vm-state"
    if legacy.is_dir():
        return legacy
    return Path.home() / ".local/state/coding-vm"


class Manager:
    def __init__(self, project, state):
        self.project = project.resolve()
        if not (self.project / "templates/instance/flake.nix").exists() and (self.project / "modular/.git").exists():
            self.project = self.project / "modular"
        self.state = state.resolve()
        self.root = self.state / "manager"
        self.root.mkdir(parents=True, exist_ok=True)
        self.generations = self.root / "generations"
        self.generations.mkdir(exist_ok=True)
        self.settings = self.root / "settings.nix"

    @contextlib.contextmanager
    def locked(self):
        with (self.root / "update.lock").open("w") as handle:
            fcntl.flock(handle, fcntl.LOCK_EX)
            yield

    def selected(self, name="current"):
        link = self.root / name
        return link.resolve() if link.is_symlink() else None

    def source(self, fetch=False):
        if run("git", "-C", str(self.project), "status", "--porcelain"):
            raise RuntimeError("Commit or move checkout changes before updating. Instance settings belong in the state directory.")
        if fetch:
            run("git", "-C", str(self.project), "fetch", "origin", "main", capture=False)
            run("git", "-C", str(self.project), "merge", "--ff-only", "origin/main", capture=False)
        revision = run("git", "-C", str(self.project), "rev-parse", "HEAD")
        return f"git+file://{self.project}?rev={revision}", revision

    def evaluate(self, generation, attribute):
        return json.loads(run("nix", "eval", "--accept-flake-config", "--json", "--no-write-lock-file", f"path:{generation}#{attribute}"))

    def defaults(self, source):
        expression = f'(builtins.getFlake {json.dumps(source)}).lib.defaultSettings'
        return json.loads(run("nix", "eval", "--accept-flake-config", "--json", "--expr", expression))

    def candidate(self, source, settings_text):
        temporary = Path(tempfile.mkdtemp(prefix=".candidate-", dir=self.generations))
        try:
            template = (self.project / "templates/instance/flake.nix").read_text()
            (temporary / "flake.nix").write_text(template.replace("github:MiRinChan/coding-vm.nix", source))
            (temporary / "settings.nix").write_text(settings_text)
            run("nix", "flake", "lock", "--accept-flake-config", f"path:{temporary}", capture=False)
            settings = self.evaluate(temporary, "lib.effectiveSettings")
            (temporary / "settings.nix").write_text(nix_value(settings) + "\n")
            manifest = self.evaluate(temporary, "lib.behaviorManifest")
            versions = self.evaluate(temporary, "lib.packageVersions")
            (temporary / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
            (temporary / "versions.json").write_text(json.dumps(versions, indent=2) + "\n")
            return temporary, settings, manifest, versions
        except BaseException:
            shutil.rmtree(temporary)
            raise

    def promote(self, candidate, source, revision, settings, write_settings):
        # Build before publishing any selection or changing the user's settings.
        result = json.loads(run("nix", "build", "--accept-flake-config", "--no-link", "--json", f"path:{candidate}#default"))
        output = result[0]["outputs"]["out"]
        final = self.generations / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8])
        (candidate / "metadata.json").write_text(json.dumps({"source": source, "revision": revision}, indent=2) + "\n")
        candidate.rename(final)
        run("nix-store", "--add-root", str(final / "runner"), "--indirect", "--realise", output, capture=False)
        current = self.selected()
        if current:
            self.select("previous", current)
        if write_settings:
            atomic_text(self.settings, nix_value(settings) + "\n")
        self.select("current", final)
        self.prune_roots()
        print(f"Selected {revision[:12]} for the next start. The running VM stays active.")
        return final

    def prune_roots(self):
        retained = {self.selected(), self.selected("previous")}
        for generation in self.generations.iterdir():
            if generation not in retained:
                (generation / "runner").unlink(missing_ok=True)

    def select(self, name, generation):
        temporary = self.root / (name + ".tmp")
        temporary.unlink(missing_ok=True)
        temporary.symlink_to(generation.relative_to(self.root))
        temporary.replace(self.root / name)

    def change(self, command, args):
        current = self.selected()
        if command == "init" and current:
            raise RuntimeError("Instance already exists. Use update or config.")
        source, revision = self.source(fetch=command in ("update", "upgrade-defaults") and not args.no_fetch)
        if command == "init":
            text = Path(args.settings).read_text() if args.settings else nix_value(self.defaults(source))
        elif command == "upgrade-defaults":
            if not current:
                raise RuntimeError("Initialize the instance first: ./vm init")
            old = json.loads((current / "manifest.json").read_text())["settings"]
            settings = self.defaults(source)
            for key in ("system", "user", "hostName", "systemStateVersion"):
                settings[key] = old[key]
            for key in ("sshAlias", "sshPort", "sshKey", "fsMountDir", "fsRemote"):
                if key in old["launcher"]:
                    settings["launcher"][key] = old["launcher"][key]
            text = nix_value(settings)
        else:
            if not current:
                raise RuntimeError("Initialize the instance first: ./vm init")
            text = self.settings.read_text()
        candidate = None
        try:
            candidate, settings, manifest, versions = self.candidate(source, text)
            if current:
                changes = diff(json.loads((current / "manifest.json").read_text()), manifest)
                if changes:
                    print(changes, flush=True)
                    if command == "update" and not args.accept_behavior_changes:
                        raise RuntimeError("Behavior changed. Review the diff, then repeat with --accept-behavior-changes.")
                    if command == "upgrade-defaults" and not args.yes:
                        if not sys.stdin.isatty() or input("Adopt these defaults? [y/N] ").lower() != "y":
                            raise RuntimeError("Defaults were not changed.")
                package_changes = diff(json.loads((current / "versions.json").read_text()), versions)
                if package_changes:
                    print("Package changes:\n" + package_changes, flush=True)
            self.promote(candidate, source, revision, settings, write_settings=True)
            candidate = None
        finally:
            if candidate and candidate.exists():
                shutil.rmtree(candidate)

    def rollback(self, args):
        current, previous = self.selected(), self.selected("previous")
        if not current or not previous:
            raise RuntimeError("No previous generation is available.")
        if self.settings.read_text() != (current / "settings.nix").read_text() and not args.yes:
            raise RuntimeError("Instance settings have pending edits. Save them first, or use rollback --yes.")
        print(diff(json.loads((current / "manifest.json").read_text()), json.loads((previous / "manifest.json").read_text())))
        atomic_text(self.settings, (previous / "settings.nix").read_text())
        self.select("previous", current)
        self.select("current", previous)
        print("Previous configuration selected for the next start. Disk contents stay unchanged.")

    def start(self, args):
        if not self.selected():
            self.change("init", args)
        current = self.selected()
        if self.settings.read_text() != (current / "settings.nix").read_text():
            raise RuntimeError("Instance settings have pending edits. Run ./vm update --no-fetch --accept-behavior-changes first.")
        os.environ["VM_MANAGED_RUNNER_ROOT"] = str((current / "runner").resolve())
        os.environ["VM_STATE_DIR"] = str(self.state)
        os.environ["CODING_VM_PROJECT_ROOT"] = str(self.project)
        return current / "runner/bin/run-vm"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    parser.add_argument("--state-dir", type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("init", "update", "upgrade-defaults", "rollback", "start", "status", "config"):
        sub = commands.add_parser(command)
        sub.add_argument("--no-fetch", action="store_true", help="Use the current checkout revision")
        sub.add_argument("--yes", action="store_true", help="Adopt the displayed defaults or restore saved settings")
        sub.add_argument("--accept-behavior-changes", action="store_true", help="Accept the displayed configuration diff")
        sub.add_argument("--settings", help="Initial settings file (init only)")
    args = parser.parse_args()
    project = args.project.resolve()
    if not (project / "templates/instance/flake.nix").exists() and (project / "modular/.git").exists():
        project = project / "modular"
    state = state_directory(project, args.state_dir)
    manager = Manager(project, state)
    launcher = None
    with manager.locked():
        if args.command in ("init", "update", "upgrade-defaults"):
            manager.change(args.command, args)
        elif args.command == "rollback":
            manager.rollback(args)
        elif args.command == "start":
            launcher = manager.start(args)
        elif args.command == "config":
            print(manager.settings)
        else:
            current = manager.selected()
            if current:
                metadata = json.loads((current / "metadata.json").read_text())
                settings = json.loads((current / "manifest.json").read_text())["settings"]
                print(json.dumps({"nextStart": metadata, "defaultsVersion": settings["defaultsVersion"], "timeZone": settings["spoofSettings"]["region"]["timeZone"], "preallocateDisk": settings["resources"]["preallocateDisk"], "settings": str(manager.settings), "previous": str(manager.selected("previous")) if manager.selected("previous") else None}, indent=2))
            else:
                print("Instance is not initialized. Run ./vm init or ./vm start.")
    if launcher:
        os.execv(str(launcher), [str(launcher)])


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.CalledProcessError, OSError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
