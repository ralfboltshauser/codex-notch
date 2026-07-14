#!/usr/bin/env python3
"""Durable Codex completion publisher for a remote Ubuntu host."""

import argparse
import datetime
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import uuid


PROTOCOL_VERSION = 1
MARKER = "--codex-notch-remote-hook-v1"
MAX_FRAME_SIZE = 4096
MAX_TITLE_LENGTH = 180
DEFAULT_PORT = 47391
OUTBOX_RETENTION_DAYS = 7
OUTBOX_MAX_EVENTS = 500
TOKEN_PATTERN = re.compile(r"^[0-9a-f]{64}$")
HOST_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$")


def codex_home():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))


def config_root():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "codex-notch"


def state_root():
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "codex-notch"


def config_file():
    return config_root() / "remote.json"


def outbox_directory():
    return state_root() / "outbox"


def hooks_file():
    return codex_home() / "hooks.json"


def clean_text(value, fallback, maximum):
    cleaned = " ".join(str(value or "").split())
    return (cleaned or fallback)[:maximum]


def event_id(thread_id, turn_id):
    value = "v1\0%s\0%s" % (thread_id.lower(), turn_id)
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def validate_host(value):
    value = value.strip()
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        if not HOST_PATTERN.fullmatch(value):
            raise ValueError("endpoint_host must be an IP address or DNS name")
        return value.lower()


def validate_configuration(value):
    token = str(value.get("token", "")).lower()
    if not TOKEN_PATTERN.fullmatch(token):
        raise ValueError("token must contain 64 lowercase hexadecimal characters")
    port = int(value.get("endpoint_port", DEFAULT_PORT))
    if port < 1024 or port > 65535:
        raise ValueError("endpoint_port must be between 1024 and 65535")
    host_id = clean_text(value.get("host_id"), "", 128)
    if not host_id:
        raise ValueError("host_id is required")
    return {
        "endpoint_host": validate_host(str(value.get("endpoint_host", ""))),
        "endpoint_port": port,
        "token": token,
        "host_id": host_id,
        "source_name": clean_text(value.get("source_name"), socket.gethostname().split(".")[0], 80),
    }


def atomic_json_write(path, value, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(path.parent, 0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump(value, handle, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, mode)
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def load_configuration():
    with config_file().open(encoding="utf-8") as handle:
        return validate_configuration(json.load(handle))


def lookup_title(session_id):
    path = codex_home() / "session_index.jsonl"
    try:
        lines = path.read_bytes()[-4 * 1024 * 1024:].splitlines()
    except OSError:
        return None
    for line in reversed(lines):
        try:
            item = json.loads(line)
        except (TypeError, ValueError):
            continue
        if str(item.get("id", "")).lower() == session_id:
            return clean_text(item.get("thread_name"), "Codex task finished", MAX_TITLE_LENGTH)
    return None


def completion_event(payload, configuration):
    session_id = str(uuid.UUID(payload["session_id"]))
    turn_id = clean_text(payload.get("turn_id"), "", 256)
    if not turn_id:
        raise ValueError("turn_id is required")
    return {
        "schema_version": PROTOCOL_VERSION,
        "event_id": event_id(session_id, turn_id),
        "thread_id": session_id,
        "turn_id": turn_id,
        "title": lookup_title(session_id) or "Codex task finished",
        "source_id": configuration["host_id"],
        "source_label": configuration["source_name"],
        "completed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"
        ).replace("+00:00", "Z"),
    }


def prune_outbox(now=None):
    directory = outbox_directory()
    if not directory.exists():
        return
    now = now or datetime.datetime.now(datetime.timezone.utc).timestamp()
    paths = sorted(directory.glob("*.json"), key=lambda path: path.stat().st_mtime)
    cutoff = now - OUTBOX_RETENTION_DAYS * 24 * 60 * 60
    for path in paths:
        try:
            if path.stat().st_mtime < cutoff:
                path.unlink()
        except FileNotFoundError:
            pass
    remaining = sorted(directory.glob("*.json"), key=lambda path: path.stat().st_mtime)
    for path in remaining[:-OUTBOX_MAX_EVENTS]:
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def enqueue(event):
    prune_outbox()
    destination = outbox_directory() / (event["event_id"] + ".json")
    atomic_json_write(destination, event)
    return destination


def receive_exact(connection, length):
    chunks = []
    remaining = length
    while remaining:
        chunk = connection.recv(remaining)
        if not chunk:
            raise ConnectionError("connection closed before acknowledgement")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def send_envelope(configuration, kind, event=None, timeout=2):
    envelope = {
        "protocol_version": PROTOCOL_VERSION,
        "kind": kind,
        "token": configuration["token"],
    }
    if event is not None:
        envelope["event"] = event
    payload = json.dumps(envelope, separators=(",", ":"), sort_keys=True).encode("utf-8")
    if len(payload) > MAX_FRAME_SIZE:
        raise ValueError("completion frame exceeds %d bytes" % MAX_FRAME_SIZE)

    with socket.create_connection(
        (configuration["endpoint_host"], configuration["endpoint_port"]),
        timeout=timeout,
    ) as connection:
        connection.settimeout(timeout)
        connection.sendall(struct.pack("!I", len(payload)) + payload)
        response_length = struct.unpack("!I", receive_exact(connection, 4))[0]
        if response_length > MAX_FRAME_SIZE:
            raise ValueError("acknowledgement frame is too large")
        return json.loads(receive_exact(connection, response_length))


def flush_outbox(timeout=2):
    configuration = load_configuration()
    prune_outbox()
    directory = outbox_directory()
    if not directory.exists():
        return 0
    delivered = 0
    paths = sorted(directory.glob("*.json"), key=lambda path: (path.stat().st_mtime, path.name))
    for path in paths:
        try:
            with path.open(encoding="utf-8") as handle:
                event = json.load(handle)
        except (OSError, ValueError, json.JSONDecodeError):
            invalid = directory / "invalid"
            invalid.mkdir(parents=True, exist_ok=True, mode=0o700)
            try:
                os.replace(path, invalid / path.name)
            except OSError:
                pass
            continue
        try:
            acknowledgement = send_envelope(configuration, "completion", event, timeout=timeout)
            if acknowledgement.get("event_id") != event.get("event_id"):
                raise ValueError("acknowledgement event_id does not match")
            if acknowledgement.get("status") not in ("accepted", "duplicate"):
                raise ValueError("completion was not accepted")
            path.unlink()
            delivered += 1
        except (OSError, ValueError, ConnectionError):
            break
    return delivered


def run_hook(stream=None):
    try:
        payload = json.load(stream or sys.stdin)
        if payload.get("hook_event_name") not in (None, "Stop"):
            return 0
        configuration = load_configuration()
        enqueue(completion_event(payload, configuration))
        flush_outbox(timeout=0.75)
        if any(outbox_directory().glob("*.json")):
            trigger_background_flush()
    except Exception:
        pass
    return 0


def trigger_background_flush():
    try:
        subprocess.run(
            ["systemctl", "--user", "start", "--no-block", "codex-notch-flush.service"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=0.5,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def read_hooks(path):
    if not path.exists():
        return {}
    with path.open(encoding="utf-8") as handle:
        root = json.load(handle)
    if not isinstance(root, dict):
        raise ValueError("hooks.json must contain a JSON object")
    return root


def is_our_handler(handler):
    return isinstance(handler, dict) and "--codex-notch-remote-hook" in str(handler.get("command", ""))


def remove_our_handlers(root):
    hooks = root.get("hooks")
    if hooks is None:
        return root
    if not isinstance(hooks, dict):
        raise ValueError("hooks.json 'hooks' value must be an object")
    groups = hooks.get("Stop")
    if groups is None:
        return root
    if not isinstance(groups, list):
        raise ValueError("hooks.json Stop value must be an array")

    cleaned = []
    for group in groups:
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            cleaned.append(group)
            continue
        remaining = [handler for handler in group["hooks"] if not is_our_handler(handler)]
        if remaining:
            updated = dict(group)
            updated["hooks"] = remaining
            cleaned.append(updated)
    if cleaned:
        hooks["Stop"] = cleaned
    else:
        hooks.pop("Stop", None)
    return root


def write_hooks(path, root):
    if path.exists():
        backup = path.with_name(path.name + ".bak")
        backup.write_bytes(path.read_bytes())
        os.chmod(backup, 0o600)
    atomic_json_write(path, root)


def install_systemd_units(script_path):
    directory = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "systemd" / "user"
    directory.mkdir(parents=True, exist_ok=True)
    service = """[Unit]
Description=Flush queued Codex Notch completions
After=network-online.target

[Service]
Type=oneshot
ExecStart=%s --flush
""" % shlex.quote(str(script_path))
    timer = """[Unit]
Description=Retry queued Codex Notch completions

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
Persistent=true
RandomizedDelaySec=5s
Unit=codex-notch-flush.service

[Install]
WantedBy=timers.target
"""
    (directory / "codex-notch-flush.service").write_text(service)
    (directory / "codex-notch-flush.timer").write_text(timer)
    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, timeout=5)
        subprocess.run(
            ["systemctl", "--user", "enable", "--now", "codex-notch-flush.timer"],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def install(configuration, script_path=None):
    configuration = validate_configuration(configuration)
    script_path = Path(script_path or __file__).resolve()
    root = remove_our_handlers(read_hooks(hooks_file()))
    hooks = root.setdefault("hooks", {})
    groups = hooks.setdefault("Stop", [])
    groups.append({"hooks": [{
        "type": "command",
        "command": "%s %s" % (shlex.quote(str(script_path)), MARKER),
        "timeout": 5,
        "statusMessage": "Queueing completion for Codex Notch",
    }]})
    atomic_json_write(config_file(), configuration)
    write_hooks(hooks_file(), root)
    install_systemd_units(script_path)


def uninstall():
    if hooks_file().exists():
        write_hooks(hooks_file(), remove_our_handlers(read_hooks(hooks_file())))
    systemd = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "systemd" / "user"
    try:
        subprocess.run(
            ["systemctl", "--user", "disable", "--now", "codex-notch-flush.timer"],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        subprocess.run(
            ["systemctl", "--user", "stop", "codex-notch-flush.service"],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    for name in ("codex-notch-flush.service", "codex-notch-flush.timer"):
        try:
            (systemd / name).unlink()
        except FileNotFoundError:
            pass
    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        config_file().unlink()
    except FileNotFoundError:
        pass
    shutil.rmtree(state_root(), ignore_errors=True)
    try:
        config_root().rmdir()
    except OSError:
        pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument(MARKER, action="store_true", help=argparse.SUPPRESS)
    actions.add_argument("--install-json", action="store_true")
    actions.add_argument("--flush", action="store_true")
    actions.add_argument("--ping", action="store_true")
    actions.add_argument("--uninstall", action="store_true")
    args = parser.parse_args(argv)

    if args.codex_notch_remote_hook_v1:
        return run_hook()
    if args.install_json:
        install(json.load(sys.stdin))
        return 0
    if args.flush:
        flush_outbox()
        return 0
    if args.ping:
        acknowledgement = send_envelope(load_configuration(), "ping")
        return 0 if acknowledgement.get("status") == "pong" else 1
    uninstall()
    return 0


if __name__ == "__main__":
    sys.exit(main())
