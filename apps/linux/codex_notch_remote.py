#!/usr/bin/env python3
"""Durable Codex completion publisher for a remote Ubuntu host."""

import argparse
from contextlib import contextmanager
import datetime
import fcntl
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
import time
import uuid


PROTOCOL_VERSION = 1
MARKER = "--codex-notch-remote-hook-v1"
MAX_FRAME_SIZE = 4096
MAX_TITLE_LENGTH = 180
DEFAULT_PORT = 47391
OUTBOX_RETENTION_DAYS = 7
OUTBOX_MAX_EVENTS = 500
OUTBOX_LOCK_TIMEOUT = 2
FLUSH_LOCK_TIMEOUT = 0.1
LOCAL_QUEUE_ORDER_KEY = "_codex_notch_queued_at_ns"
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


def outbox_lock_file():
    return state_root() / "outbox.lock"


def flush_lock_file():
    return state_root() / "flush.lock"


def hooks_file():
    return codex_home() / "hooks.json"


def codex_config_file():
    return codex_home() / "config.toml"


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


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def ensure_private_directory(path):
    missing = []
    current = path
    while not current.exists():
        missing.append(current)
        current = current.parent
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    for created in reversed(missing):
        fsync_directory(created.parent)


def atomic_json_write(path, value, mode=0o600):
    ensure_private_directory(path.parent)
    os.chmod(path.parent, 0o700)
    descriptor, temporary_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            os.fchmod(handle.fileno(), mode)
            json.dump(value, handle, separators=(",", ":"), sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_name, path)
        fsync_directory(path.parent)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


@contextmanager
def private_file_lock(path, timeout):
    ensure_private_directory(path.parent)
    os.chmod(path.parent, 0o700)
    descriptor = os.open(
        path,
        os.O_RDWR | os.O_CREAT | getattr(os, "O_CLOEXEC", 0),
        0o600,
    )
    try:
        os.fchmod(descriptor, 0o600)
        deadline = time.monotonic() + max(0, timeout)
        while True:
            try:
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("timed out waiting for the private queue lock")
                time.sleep(min(0.01, remaining))
        yield descriptor
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def outbox_lock(timeout=OUTBOX_LOCK_TIMEOUT):
    return private_file_lock(outbox_lock_file(), timeout)


def flush_lock(timeout=FLUSH_LOCK_TIMEOUT):
    return private_file_lock(flush_lock_file(), timeout)


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


def outbox_creation_key(path):
    try:
        with path.open(encoding="utf-8") as handle:
            queued_at = json.load(handle).get(LOCAL_QUEUE_ORDER_KEY)
        if isinstance(queued_at, int) and queued_at >= 0:
            return (queued_at, path.name)
    except (OSError, ValueError, json.JSONDecodeError, AttributeError):
        pass
    try:
        return (path.stat().st_mtime_ns, path.name)
    except FileNotFoundError:
        return (2**63 - 1, path.name)


def next_outbox_order_unlocked():
    latest = max(
        (outbox_creation_key(path)[0] for path in outbox_directory().glob("*.json")),
        default=-1,
    )
    return max(time.time_ns(), latest + 1)


def unlink_unlocked_outbox_path(path):
    try:
        descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
    except FileNotFoundError:
        return False
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        try:
            path.unlink()
            return True
        except FileNotFoundError:
            return False
    finally:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
        finally:
            os.close(descriptor)


def prune_outbox_unlocked(now=None, protected=None):
    directory = outbox_directory()
    if not directory.exists():
        return
    now = now or datetime.datetime.now(datetime.timezone.utc).timestamp()
    paths = sorted(directory.glob("*.json"), key=outbox_creation_key)
    cutoff = now - OUTBOX_RETENTION_DAYS * 24 * 60 * 60
    changed = False
    for path in paths:
        if path == protected:
            continue
        try:
            if path.stat().st_mtime < cutoff:
                changed = unlink_unlocked_outbox_path(path) or changed
        except FileNotFoundError:
            pass
    remaining = sorted(directory.glob("*.json"), key=outbox_creation_key)
    excess = max(0, len(remaining) - OUTBOX_MAX_EVENTS)
    for path in remaining:
        if excess == 0:
            break
        if path == protected:
            continue
        if not unlink_unlocked_outbox_path(path):
            continue
        changed = True
        excess -= 1
    if changed:
        fsync_directory(directory)


def prune_outbox(now=None, protected=None):
    with outbox_lock():
        prune_outbox_unlocked(now=now, protected=protected)


def enqueue(event):
    with outbox_lock():
        destination = outbox_directory() / (event["event_id"] + ".json")
        if destination.exists():
            return destination
        queued = dict(event)
        # The persisted order is monotonic relative to every existing event,
        # even when the wall clock rolls backward or older files are future-dated.
        queued[LOCAL_QUEUE_ORDER_KEY] = next_outbox_order_unlocked()
        atomic_json_write(destination, queued)
        # Include the newly durable event when enforcing the bound. The lock
        # makes concurrent enqueue/prune cycles one atomic queue operation.
        prune_outbox_unlocked(protected=destination)
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


def ping_receiver(configuration, attempts=1, timeout=2, retry_delay=0.25):
    attempts = max(1, min(10, int(attempts)))
    last_error = None
    for attempt in range(attempts):
        try:
            acknowledgement = send_envelope(configuration, "ping", timeout=timeout)
            if not isinstance(acknowledgement, dict):
                raise ValueError("ping acknowledgement must be a JSON object")
            if acknowledgement.get("status") != "pong":
                raise ConnectionError("the Mac receiver rejected the pairing ping")
            return acknowledgement
        except (OSError, ValueError, ConnectionError) as error:
            last_error = error
            if attempt + 1 < attempts:
                time.sleep(retry_delay)
    endpoint = "%s:%s" % (configuration["endpoint_host"], configuration["endpoint_port"])
    raise ConnectionError(
        "Could not reach Codex Notch on this Mac at %s. "
        "Make sure Codex Notch and Tailscale are running on the Mac. (%s)"
        % (endpoint, last_error)
    ) from last_error


def claim_outbox_path(path):
    with outbox_lock():
        try:
            descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_CLOEXEC", 0))
        except FileNotFoundError:
            return None
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            os.close(descriptor)
            return None
        try:
            return os.fdopen(descriptor, "r", encoding="utf-8")
        except Exception:
            os.close(descriptor)
            raise


def quarantine_claimed_path(path):
    with outbox_lock():
        invalid = outbox_directory() / "invalid"
        ensure_private_directory(invalid)
        try:
            os.replace(path, invalid / path.name)
        except FileNotFoundError:
            return
        fsync_directory(outbox_directory())
        fsync_directory(invalid)


def unlink_acknowledged_path(path):
    with outbox_lock():
        try:
            path.unlink()
        except FileNotFoundError:
            return
        fsync_directory(outbox_directory())


def flush_outbox_locked(timeout=2):
    configuration = load_configuration()
    prune_outbox()
    directory = outbox_directory()
    if not directory.exists():
        return 0
    delivered = 0
    paths = sorted(directory.glob("*.json"), key=outbox_creation_key)
    for path in paths:
        handle = claim_outbox_path(path)
        if handle is None:
            continue
        try:
            try:
                event = json.load(handle)
                if not isinstance(event, dict):
                    raise ValueError("queued completion must be a JSON object")
                event.pop(LOCAL_QUEUE_ORDER_KEY, None)
                if (
                    type(event.get("schema_version")) is not int
                    or event["schema_version"] != PROTOCOL_VERSION
                ):
                    raise ValueError("queued completion has an unsupported schema version")
                identifier = event.get("event_id")
                if not isinstance(identifier, str) or not TOKEN_PATTERN.fullmatch(identifier):
                    raise ValueError("queued completion has an invalid event_id")
            except (OSError, ValueError, json.JSONDecodeError):
                quarantine_claimed_path(path)
                continue
            try:
                acknowledgement = send_envelope(
                    configuration, "completion", event, timeout=timeout
                )
                if not isinstance(acknowledgement, dict):
                    raise ValueError("completion acknowledgement must be a JSON object")
                if acknowledgement.get("event_id") != event.get("event_id"):
                    raise ValueError("acknowledgement event_id does not match")
                if acknowledgement.get("status") not in ("accepted", "duplicate"):
                    raise ValueError("completion was not accepted")
                unlink_acknowledged_path(path)
                delivered += 1
            except (OSError, ValueError, ConnectionError):
                break
        finally:
            handle.close()
    return delivered


def flush_outbox(timeout=2):
    try:
        with flush_lock():
            return flush_outbox_locked(timeout=timeout)
    except TimeoutError:
        return 0


def run_hook(stream=None):
    try:
        payload = json.load(stream or sys.stdin)
        if payload.get("hook_event_name") not in (None, "Stop"):
            return 0
        configuration = load_configuration()
        enqueue(completion_event(payload, configuration))
        # Codex waits for Stop hooks to return. Keep network delivery outside
        # that critical path: the durable outbox owns the event before the
        # no-block service is asked to replay it in creation order.
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


def contains_our_handlers(root):
    hooks = root.get("hooks")
    if not isinstance(hooks, dict):
        return False
    groups = hooks.get("Stop")
    if not isinstance(groups, list):
        return False
    return any(
        is_our_handler(handler)
        for group in groups
        if isinstance(group, dict) and isinstance(group.get("hooks"), list)
        for handler in group["hooks"]
    )


def hook_state_keys(root, source_path):
    hooks = root.get("hooks")
    if not isinstance(hooks, dict):
        return set()
    groups = hooks.get("Stop")
    if not isinstance(groups, list):
        return set()
    keys = set()
    for group_index, group in enumerate(groups):
        if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
            continue
        for handler_index, handler in enumerate(group["hooks"]):
            if is_our_handler(handler):
                keys.add("%s:stop:%d:%d" % (source_path, group_index, handler_index))
    return keys


def trusted_hook_state_keys(keys):
    path = codex_config_file()
    if not keys or not path.exists():
        return set()
    header = re.compile(r'^\[hooks\.state\.("(?:\\.|[^"\\])*")\]\s*$')
    trusted_hash = re.compile(r'^trusted_hash\s*=\s*"[^"]+"\s*$')
    current_key = None
    trusted = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            match = header.fullmatch(stripped)
            current_key = json.loads(match.group(1)) if match else None
        elif current_key in keys and trusted_hash.fullmatch(stripped):
            trusted.add(current_key)
    return trusted


def check_health(attempts=1):
    configuration = load_configuration()
    root = read_hooks(hooks_file())
    if not contains_our_handlers(root):
        raise ValueError("Codex completion hook is not installed")
    keys = hook_state_keys(root, hooks_file())
    if trusted_hook_state_keys(keys) != keys:
        raise ValueError("Codex completion hook still needs trust")
    live_script = Path(__file__).resolve().with_name("codex_notch_live-v1.py")
    if not live_script.exists():
        live_script = Path(__file__).resolve().with_name("codex_notch_live.py")
    if not live_script.is_file() or not os.access(live_script, os.X_OK):
        raise ValueError("Codex active-task observer is not installed")
    ping_receiver(configuration, attempts=attempts)


def remove_hook_state(keys):
    path = codex_config_file()
    if not keys or not path.exists():
        return
    header = re.compile(r'^\[hooks\.state\.("(?:\\.|[^"\\])*")\]\s*$')
    original = path.read_text(encoding="utf-8")
    filtered = []
    skipping = False
    for line in original.splitlines(keepends=True):
        stripped = line.strip()
        if stripped.startswith("["):
            match = header.fullmatch(stripped)
            skipping = bool(match and json.loads(match.group(1)) in keys)
        if not skipping:
            filtered.append(line)
    updated = "".join(filtered)
    if updated == original:
        return
    descriptor, temporary_name = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(updated)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o600)
        os.replace(temporary_name, path)
    except Exception:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise


def write_hooks(path, root, create_backup=True):
    if create_backup and path.exists():
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
    live_script = script_path.with_name("codex_notch_live-v1.py")
    live_service = """[Unit]
Description=Publish active Codex tasks to Codex Notch
After=network-online.target

[Service]
Type=simple
ExecStart=%s
Restart=always
RestartSec=2s

[Install]
WantedBy=default.target
""" % shlex.quote(str(live_script))
    (directory / "codex-notch-flush.service").write_text(service)
    (directory / "codex-notch-flush.timer").write_text(timer)
    (directory / "codex-notch-live.service").write_text(live_service)
    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, timeout=5)
        subprocess.run(
            ["systemctl", "--user", "enable", "--now", "codex-notch-flush.timer"],
            check=False,
            timeout=5,
        )
        if live_script.is_file():
            subprocess.run(
                ["systemctl", "--user", "enable", "--now", "codex-notch-live.service"],
                check=False,
                timeout=5,
            )
            subprocess.run(
                ["systemctl", "--user", "restart", "codex-notch-live.service"],
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
    hook_paths = (hooks_file(), hooks_file().with_name(hooks_file().name + ".bak"))
    state_keys = set()
    for path in hook_paths:
        if path.exists():
            if "--codex-notch-remote-hook" not in path.read_text(encoding="utf-8", errors="ignore"):
                continue
            root = read_hooks(path)
            if contains_our_handlers(root):
                state_keys.update(hook_state_keys(root, hooks_file()))
                write_hooks(path, remove_our_handlers(root), create_backup=False)
    remove_hook_state(state_keys)
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
    try:
        subprocess.run(
            ["systemctl", "--user", "disable", "--now", "codex-notch-live.service"],
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        pass
    for name in ("codex-notch-flush.service", "codex-notch-flush.timer", "codex-notch-live.service"):
        try:
            (systemd / name).unlink()
        except FileNotFoundError:
            pass
    try:
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, timeout=5)
    except (OSError, subprocess.SubprocessError):
        pass
    shutil.rmtree(config_root(), ignore_errors=True)
    shutil.rmtree(state_root(), ignore_errors=True)
    installed_script = Path.home() / ".local" / "lib" / "codex-notch" / "codex_notch_remote-v1.py"
    try:
        installed_script.unlink()
    except FileNotFoundError:
        pass
    installed_live_script = installed_script.with_name("codex_notch_live-v1.py")
    try:
        installed_live_script.unlink()
    except FileNotFoundError:
        pass
    try:
        installed_script.parent.rmdir()
    except OSError:
        pass


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    actions = parser.add_mutually_exclusive_group(required=True)
    actions.add_argument(MARKER, action="store_true", help=argparse.SUPPRESS)
    actions.add_argument("--install-json", action="store_true")
    actions.add_argument("--flush", action="store_true")
    actions.add_argument("--ping", action="store_true")
    actions.add_argument("--health", action="store_true")
    actions.add_argument("--repair", action="store_true")
    actions.add_argument("--uninstall", action="store_true")
    parser.add_argument("--ping-attempts", type=int, default=1, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)
    if args.ping_attempts < 1 or args.ping_attempts > 10:
        parser.error("--ping-attempts must be between 1 and 10")

    if args.codex_notch_remote_hook_v1:
        return run_hook()
    if args.install_json:
        install(json.load(sys.stdin))
        return 0
    if args.flush:
        flush_outbox()
        return 0
    if args.ping:
        try:
            ping_receiver(load_configuration(), attempts=args.ping_attempts)
            return 0
        except (OSError, ValueError, ConnectionError) as error:
            print(error, file=sys.stderr)
            return 1
    if args.health:
        try:
            check_health(attempts=args.ping_attempts)
            return 0
        except (OSError, ValueError, ConnectionError) as error:
            print(error, file=sys.stderr)
            return 1
    if args.repair:
        install(load_configuration())
        return 0
    uninstall()
    return 0


if __name__ == "__main__":
    sys.exit(main())
