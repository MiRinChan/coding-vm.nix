#!/usr/bin/env python3
"""Boot a disposable KVM guest, log in over serial, and shut down through QMP."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import socket
import subprocess
import tempfile
import time

project = Path(__file__).parents[1].resolve()
spec = importlib.util.spec_from_file_location("runtime", project / "scripts/vm-runtime.py")
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)
expression = '''let
  flake = builtins.getFlake PROJECT;
  original = flake.lib.defaultSettings;
  settings = original // {
    hostName = "coding-vm-console-test";
    resources = original.resources // { cores = 1; memoryMiB = 2048; diskMiB = 1024; };
    spoofSettings = original.spoofSettings // { enable = false; };
  };
  guest = (flake.lib.mkVM settings).nixosConfiguration.extendModules {
    modules = [ { services.openssh.enable = flake.inputs.nixpkgs.lib.mkForce false; } ];
  };
in guest.config.system.build.vm'''.replace("PROJECT", json.dumps(str(project)))
build = json.loads(subprocess.check_output(["nix", "build", "--accept-flake-config", "--impure", "--no-link", "--json", "--expr", expression], text=True))
runner = next((Path(build[0]["outputs"]["out"]) / "bin").glob("run-*-vm"))
with tempfile.TemporaryDirectory(prefix="coding-vm-console-") as directory:
    state = Path(directory)
    (state / "shared").mkdir()
    with contextlib.redirect_stdout(io.StringIO()):
        runtime.prepare(state)
    paths = runtime.runtime_paths(state)
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        port = reservation.getsockname()[1]
    env = os.environ.copy()
    env.update(NIX_DISK_IMAGE=str(state / "nixos.qcow2"), SHARED_DIR=str(state / "shared"), VM_STATE_DIR=str(state), VM_SSH_PORT=str(port), VM_CONSOLE_SOCKET=paths["console"], VM_CONSOLE_LOG=paths["consoleLog"], VM_QMP_SOCKET=paths["qmp"], VM_PID_FILE=paths["pid"])
    log = (state / "qemu.log").open("w+")
    process = subprocess.Popen([str(runner)], env=env, cwd=state, stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    terminal = None
    master = slave = None
    try:
        deadline = time.monotonic() + 90
        while not Path(paths["console"]).is_socket():
            if process.poll() is not None or time.monotonic() > deadline:
                log.seek(0)
                raise AssertionError("QEMU did not open the console:\n" + log.read())
            time.sleep(0.2)
        master, slave = pty.openpty()
        terminal = subprocess.Popen([str(project / "console.sh")], env=env, stdin=slave, stdout=slave, stderr=slave)
        transcript = bytearray()
        def expect(text):
            start = len(transcript)
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], 0.2)
                if readable:
                    transcript.extend(os.read(master, 65536))
                    if text in transcript[start:]:
                        return
                if process.poll() is not None:
                    break
            log.seek(0)
            raise AssertionError(f"Missing {text!r}:\n" + transcript.decode(errors="replace") + "\n" + log.read())
        expect(b"Serial console.")
        os.write(master, b"\r")
        expect(b"login:")
        os.write(master, b"alice\r")
        expect(b"Password:")
        os.write(master, b"change-me\r")
        expect(b"alice@")
        os.write(master, b"printf 'CONSOLE_%s\\n' VERIFIED\r")
        expect(b"CONSOLE_VERIFIED")
        os.write(master, b"\x1d")
        assert terminal.wait(timeout=5) == 0
        assert process.poll() is None, "Disconnecting the terminal stopped QEMU"
        result = json.loads(subprocess.check_output([str(project / "status.sh"), "--json"], env=env, text=True))
        assert result["state"] == "running" and result["qmp"] and result["console"], result
        # A failing SSH executable makes accidental SSH use fail this test.
        tools = state / "tools"
        tools.mkdir()
        (tools / "ssh").write_text("#!/bin/sh\nexit 99\n")
        (tools / "ssh").chmod(0o755)
        env["PATH"] = str(tools) + ":" + env["PATH"]
        subprocess.run([str(project / "stop.sh"), "--timeout", "60"], env=env, check=True)
        assert process.wait(timeout=5) == 0
        result = json.loads(subprocess.check_output([str(project / "status.sh"), "--json"], env=env, text=True))
        assert result["state"] == "stopped", result
        print("OK: serial login, Ctrl-] disconnect, running/stopped status, and normal shutdown with SSH disabled")
    finally:
        if terminal and terminal.poll() is None:
            terminal.terminate()
            terminal.wait(timeout=5)
        for fd in (master, slave):
            if fd is not None:
                os.close(fd)
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        process.wait(timeout=10)
        log.close()
        for key in ("qmp", "console", "pid"):
            Path(paths[key]).unlink(missing_ok=True)
        Path(paths["qmp"]).parent.rmdir()
