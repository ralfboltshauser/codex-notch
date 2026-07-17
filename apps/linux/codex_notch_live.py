#!/usr/bin/env python3
"""Ephemeral active-task observer for Codex Notch remote hosts."""

import base64
import datetime
import hashlib
import json
import os
from pathlib import Path
import secrets
import select
import socket
import struct
import sys
import tempfile
import time
import uuid


PROTOCOL_VERSION = 1
MAX_FRAME_SIZE = 65536
MAX_TASKS = 50
generation = str(uuid.uuid4())
sequence = 0


def codex_home():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))


def configuration_file():
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "codex-notch/remote.json"


def load_configuration():
    with configuration_file().open(encoding="utf-8") as handle:
        return json.load(handle)


def receive_exact(connection, length):
    result = bytearray()
    while len(result) < length:
        chunk = connection.recv(length - len(result))
        if not chunk:
            raise ConnectionError("connection closed")
        result.extend(chunk)
    return bytes(result)


def send_remote_snapshot(configuration, snapshot):
    envelope = {
        "protocol_version": PROTOCOL_VERSION,
        "kind": "active_snapshot",
        "token": configuration["token"],
        "snapshot": snapshot,
    }
    payload = json.dumps(envelope, separators=(",", ":"), sort_keys=True).encode()
    if len(payload) > MAX_FRAME_SIZE:
        raise ValueError("active snapshot is too large")
    with socket.create_connection(
        (configuration["endpoint_host"], int(configuration.get("endpoint_port", 47391))),
        timeout=3,
    ) as connection:
        connection.sendall(struct.pack("!I", len(payload)) + payload)
        length = struct.unpack("!I", receive_exact(connection, 4))[0]
        if length > MAX_FRAME_SIZE:
            raise ValueError("acknowledgement is too large")
        acknowledgement = json.loads(receive_exact(connection, length))
        if acknowledgement.get("status") not in ("accepted", "duplicate"):
            raise ConnectionError("snapshot was rejected")


def socket_candidates():
    stable = codex_home() / "app-server-control/app-server-control.sock"
    yield stable
    roots = {Path(tempfile.gettempdir()), Path("/tmp")}
    for root in roots:
        try:
            for directory in root.glob("codex-rc-*"):
                yield directory / "rc.sock"
        except OSError:
            pass


class UnixWebSocket:
    def __init__(self, path):
        self.connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.connection.settimeout(5)
        self.connection.connect(str(path))
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        request = (
            "GET / HTTP/1.1\r\nHost: localhost\r\nUpgrade: websocket\r\n"
            "Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n" % key
        ).encode()
        self.connection.sendall(request)
        response = bytearray()
        while not response.endswith(b"\r\n\r\n") and len(response) < 16384:
            response.extend(receive_exact(self.connection, 1))
        expected = base64.b64encode(hashlib.sha1(
            (key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()
        ).digest()).decode()
        text = response.decode("latin-1")
        if not text.startswith(("HTTP/1.1 101", "HTTP/1.0 101")) or expected.lower() not in text.lower():
            raise ConnectionError("invalid WebSocket handshake")
        self.connection.settimeout(None)

    def close(self):
        self.connection.close()

    def send_json(self, value):
        payload = json.dumps(value, separators=(",", ":"), sort_keys=True).encode()
        header = bytearray([0x81])
        if len(payload) < 126:
            header.append(0x80 | len(payload))
        elif len(payload) <= 65535:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", len(payload)))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", len(payload)))
        mask = secrets.token_bytes(4)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        self.connection.sendall(bytes(header) + mask + masked)

    def receive_json(self):
        first = receive_exact(self.connection, 2)
        opcode = first[0] & 0x0F
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", receive_exact(self.connection, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", receive_exact(self.connection, 8))[0]
        mask = receive_exact(self.connection, 4) if first[1] & 0x80 else None
        payload = bytearray(receive_exact(self.connection, length))
        if mask:
            for index in range(len(payload)):
                payload[index] ^= mask[index % 4]
        if opcode == 0x8:
            raise ConnectionError("WebSocket closed")
        if opcode == 0x9:
            self.send_control(0xA, payload)
            return None
        if opcode != 0x1:
            return None
        return json.loads(payload)

    def send_control(self, opcode, payload):
        mask = secrets.token_bytes(4)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        self.connection.sendall(bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked)


def iso_time(timestamp=None):
    value = datetime.datetime.fromtimestamp(
        timestamp if timestamp is not None else time.time(), datetime.timezone.utc
    )
    return value.isoformat(timespec="seconds").replace("+00:00", "Z")


def clean_optional(value, maximum):
    cleaned = " ".join(str(value or "").split())
    return cleaned[:maximum] or None


def canonical_thread_id(value):
    try:
        return str(uuid.UUID(str(value)))
    except (TypeError, ValueError, AttributeError):
        return None


def project_label(cwd):
    if not isinstance(cwd, str) or not cwd:
        return None
    return clean_optional(os.path.basename(os.path.normpath(cwd)), 80)


def thread_nodes(rows):
    nodes = {}
    for row in rows:
        thread_id = canonical_thread_id(row.get("id"))
        if not thread_id or thread_id in nodes:
            continue
        parent_id = canonical_thread_id(row.get("parentThreadId"))
        nodes[thread_id] = {
            "id": thread_id,
            "parent_id": parent_id,
            "title": clean_optional(row.get("name") or "Codex task running", 180),
            "row": row,
        }
    return nodes


def root_thread_id(node, nodes):
    current_id = node["id"]
    seen = {current_id}
    while nodes.get(current_id, {}).get("parent_id"):
        parent_id = nodes[current_id]["parent_id"]
        if parent_id in seen:
            return node["id"]
        seen.add(parent_id)
        current_id = parent_id
        if current_id not in nodes:
            return current_id
    return current_id


def snapshot_from_rows(rows):
    global sequence
    tasks = []
    nodes = thread_nodes(rows)
    for row in rows:
        status = row.get("status") or {}
        if status.get("type") != "active":
            continue
        flags = status.get("activeFlags") or []
        state = "waiting_for_approval" if "waitingOnApproval" in flags else (
            "waiting_for_input" if "waitingOnUserInput" in flags else "running"
        )
        thread_id = canonical_thread_id(row.get("id"))
        if not thread_id or thread_id not in nodes:
            continue
        node = nodes[thread_id]
        root_id = root_thread_id(node, nodes)
        task = {
            "thread_id": thread_id,
            "title": node["title"] or "Codex task running",
            "state": state,
            "updated_at": iso_time(row.get("updatedAt")),
            "root_thread_id": root_id,
        }
        if node["parent_id"]:
            task["parent_thread_id"] = node["parent_id"]
        if root_id != thread_id and root_id in nodes:
            task["root_title"] = nodes[root_id]["title"]
        context = {
            "project_label": project_label(row.get("cwd")),
            "branch": clean_optional((row.get("gitInfo") or {}).get("branch"), 160)
                if isinstance(row.get("gitInfo"), dict) else None,
            "agent_nickname": clean_optional(row.get("agentNickname"), 80),
            "agent_role": clean_optional(row.get("agentRole"), 80),
        }
        task.update({key: value for key, value in context.items() if value})
        tasks.append(task)
        if len(tasks) == MAX_TASKS:
            break
    sequence += 1
    return {
        "schema_version": PROTOCOL_VERSION,
        "generation": generation,
        "sequence": sequence,
        "generated_at": iso_time(),
        "tasks": tasks,
    }


def request_list(client, request_id):
    client.send_json({
        "id": request_id,
        "method": "thread/list",
        "params": {
            "archived": False,
            "limit": 100,
            "sortKey": "updated_at",
            "sortDirection": "desc",
            "useStateDbOnly": True,
        },
    })


def observe(path, configuration):
    client = UnixWebSocket(path)
    request_id = 2
    client.send_json({
        "id": 1,
        "method": "initialize",
        "params": {
            "clientInfo": {"name": "codex-notch-live", "title": "Codex Notch", "version": "1"},
            "capabilities": {"experimentalApi": False},
        },
    })
    initialized = False
    last_request = 0
    try:
        while True:
            ready, _, _ = select.select([client.connection], [], [], 10)
            if not ready:
                if initialized:
                    request_list(client, request_id)
                    request_id += 1
                    last_request = time.monotonic()
                continue
            message = client.receive_json()
            if not message:
                continue
            if message.get("id") == 1 and "result" in message:
                client.send_json({"method": "initialized"})
                initialized = True
                request_list(client, request_id)
                request_id += 1
                last_request = time.monotonic()
            elif isinstance(message.get("result"), dict) and isinstance(message["result"].get("data"), list):
                try:
                    send_remote_snapshot(configuration, snapshot_from_rows(message["result"]["data"]))
                except (OSError, ValueError, KeyError, ConnectionError, json.JSONDecodeError):
                    pass
            elif message.get("method") in {
                "thread/status/changed", "thread/name/updated", "thread/started", "thread/closed"
            } and time.monotonic() - last_request > 0.2:
                request_list(client, request_id)
                request_id += 1
                last_request = time.monotonic()
    finally:
        client.close()


def run_forever():
    while True:
        try:
            configuration = load_configuration()
            for candidate in socket_candidates():
                if not candidate.exists():
                    continue
                try:
                    observe(candidate, configuration)
                except (OSError, ValueError, KeyError, ConnectionError, json.JSONDecodeError):
                    continue
        except (OSError, ValueError, KeyError, json.JSONDecodeError):
            pass
        time.sleep(2)


if __name__ == "__main__":
    try:
        run_forever()
    except KeyboardInterrupt:
        sys.exit(0)
