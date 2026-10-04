#!/usr/bin/env python3
"""Control an instance through local QEMU sockets, without SSH or Nix evaluation."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shlex
import socket
import subprocess
import sys
import termios
import time
import tty


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        try:
            self.socket.settimeout(3)
            self.socket.connect(str(path))
            self.file = self.socket.makefile("rb")
            greeting = self.read()
            if "QMP" not in greeting:
                raise RuntimeError("The QEMU control socket sent an invalid greeting.")
            self.command("qmp_capabilities")
        except BaseException:
            self.close()
            raise

    def read(self):
        line = self.file.readline()
        if not line:
            raise RuntimeError("The QEMU control connection closed.")
        return json.loads(line)

    def command(self, name):
        self.socket.sendall(json.dumps({"execute": name, "id": name}).encode() + b"\n")
        while True:
            result = self.read()
            if result.get("id") != name:
                continue
            if "error" in result:
                raise RuntimeError(result["error"].get("desc", "QEMU rejected the command."))
            return result["return"]

    def close(self):
        if hasattr(self, "file"):
            self.file.close()
        self.socket.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def processes(state):
    disk = str(state / "nixos.qcow2")
    found = []
    for process in Path("/proc").glob("[0-9]*"):
        try:
            args = (process / "cmdline").read_bytes().decode().split("\0")
            if "qemu-system-" not in Path(args[0]).name:
                continue
            if any(f"file={disk}," in arg or arg.endswith(f"file={disk}") for arg in args):
                found.append(int(process.name))
        except (OSError, UnicodeError, IndexError):
            pass
    return found


def alive(pid):
    try:
        # A zombie no longer holds the disk or serves a console.
        return Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[0] != "Z"
    except OSError:
        return False


def runtime_paths(state):
    record = state / "runtime.json"
    if record.exists():
        return json.loads(record.read_text())
    base = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/coding-vm-{os.getuid()}")) / "coding-vm"
    directory = base / hashlib.sha256(str(state).encode()).hexdigest()[:16]
    return {"qmp": str(directory / "qmp.sock"), "console": str(directory / "console.sock"), "pid": str(directory / "qemu.pid"), "consoleLog": str(state / "logs/console.log")}


def prepare(state):
    if processes(state):
        raise RuntimeError("This instance already has a running QEMU process.")
    # Compute fresh paths in this login session, rather than reusing an old runtime directory.
    record = state / "runtime.json"
    record.unlink(missing_ok=True)
    paths = runtime_paths(state)
    directory = Path(paths["qmp"]).parent
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if directory.stat().st_uid != os.getuid():
        raise RuntimeError("The QEMU socket directory belongs to another user.")
    directory.chmod(0o700)
    for name in ("qmp", "console"):
        if len(os.fsencode(paths[name])) >= 108 or "," in paths[name]:
            raise RuntimeError("The QEMU socket path is too long or contains a comma. Set a shorter XDG_RUNTIME_DIR.")
    if "," in paths["consoleLog"]:
        raise RuntimeError("The instance path contains a comma. Select another VM_STATE_DIR.")
    for name in ("qmp", "console", "pid"):
        Path(paths[name]).unlink(missing_ok=True)
    (state / "logs").mkdir(parents=True, exist_ok=True)
    temporary = record.with_suffix(".tmp")
    temporary.write_text(json.dumps(paths) + "\n")
    temporary.replace(record)
    for variable, key in (("VM_QMP_SOCKET", "qmp"), ("VM_CONSOLE_SOCKET", "console"), ("VM_PID_FILE", "pid"), ("VM_CONSOLE_LOG", "consoleLog")):
        print(f"export {variable}={shlex.quote(paths[key])}")


def status(state):
    pids = processes(state)
    result = {"state": "running" if pids else "stopped", "pids": pids, "qmp": False, "console": False}
    if pids:
        paths = runtime_paths(state)
        result["console"] = Path(paths["console"]).is_socket()
        try:
            with QMP(paths["qmp"]) as qmp:
                result["qemuStatus"] = qmp.command("query-status")["status"]
            result["qmp"] = True
        except (OSError, RuntimeError, ValueError):
            result["qemuStatus"] = "control-unavailable"
    return result


def legacy_shutdown(state, pid):
    # Older launchers have no QMP socket. Use their existing SSH connection once.
    manifest = state / "manager/current/manifest.json"
    if not manifest.exists():
        raise RuntimeError("This launcher has no QMP socket. Shut down the guest through its existing SSH connection.")
    settings = json.loads(manifest.read_text())["settings"]
    launcher = settings["launcher"]
    port = launcher["sshPort"]
    args = Path(f"/proc/{pid}/cmdline").read_bytes().decode().split("\0")
    import re
    for argument in args:
        match = re.search(r"(?:tcp-ports=127\.0\.0\.1/|hostfwd=tcp:127\.0\.0\.1:)(\d+)(?::22|-:22)", argument)
        if match:
            port = int(match[1])
    key = os.environ.get("VM_SSH_KEY", launcher["sshKey"] or str(Path.home() / ".ssh/coding-vm_ed25519"))
    print("The running launcher has no QMP socket. Requesting shutdown through SSH.", flush=True)
    subprocess.run(["ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-o", "IdentitiesOnly=yes", "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={state / 'known_hosts'}", "-p", str(port), "-i", key, f"{settings['user']}@127.0.0.1", "sudo -n systemctl poweroff"], check=True)


def stop(state, timeout):
    pids = processes(state)
    if not pids:
        print("VM is stopped.")
        return
    try:
        qmp = QMP(runtime_paths(state)["qmp"])
    except (OSError, RuntimeError):
        legacy_shutdown(state, pids[0])
    else:
        with qmp:
            qmp.command("system_powerdown")
        print("Shutdown requested. Waiting for QEMU to exit...", flush=True)
    deadline = time.monotonic() + timeout
    while any(alive(pid) for pid in pids):
        if time.monotonic() >= deadline:
            raise RuntimeError("The guest did not shut down before the timeout. No process was killed. Use console.sh to inspect the guest.")
        time.sleep(0.25)
    print("VM is stopped.")


def console(state):
    if not processes(state):
        raise RuntimeError("VM is stopped. Start it before opening the console.")
    paths = runtime_paths(state)
    connection = socket.socket(socket.AF_UNIX)
    try:
        connection.connect(paths["console"])
    except OSError as error:
        connection.close()
        raise RuntimeError("The serial console is unavailable. Older launchers need a restart to add this interface.") from error
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        connection.close()
        raise RuntimeError("Open console.sh in an interactive terminal.")
    print("Serial console. Press Enter for the login prompt. Press Ctrl-] to disconnect.", flush=True)
    previous = termios.tcgetattr(sys.stdin.fileno())
    try:
        tty.setraw(sys.stdin.fileno())
        with selectors.DefaultSelector() as events:
            events.register(connection, selectors.EVENT_READ)
            events.register(sys.stdin.fileno(), selectors.EVENT_READ)
            while True:
                for key, _ in events.select():
                    if key.fileobj == connection:
                        data = connection.recv(65536)
                        if not data:
                            return
                        os.write(sys.stdout.fileno(), data)
                    else:
                        data = os.read(sys.stdin.fileno(), 4096)
                        if not data:
                            return
                        if b"\x1d" in data:
                            prefix = data.split(b"\x1d", 1)[0]
                            if prefix:
                                connection.sendall(prefix)
                            return
                        connection.sendall(data)
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSADRAIN, previous)
        connection.close()
        print("\r\nConsole disconnected.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", required=True, type=Path)
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("prepare")
    show = commands.add_parser("status")
    show.add_argument("--json", action="store_true")
    shutdown = commands.add_parser("stop")
    shutdown.add_argument("--timeout", type=float, default=120)
    commands.add_parser("console")
    args = parser.parse_args()
    state = args.state_dir.resolve()
    if args.command == "prepare":
        prepare(state)
    elif args.command == "status":
        result = status(state)
        if args.json:
            print(json.dumps(result))
        elif result["state"] == "stopped":
            print("VM is stopped.")
        else:
            print(f"VM is running. QEMU status: {result['qemuStatus']}. PID: {', '.join(map(str, result['pids']))}.")
            print(f"Serial console: {'available' if result['console'] else 'unavailable until the next start'}.")
    elif args.command == "stop":
        if args.timeout <= 0:
            raise RuntimeError("The shutdown timeout must be greater than zero.")
        stop(state, args.timeout)
    else:
        console(state)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Error: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        sys.exit(130)
