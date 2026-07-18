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
MAX_APP_SERVER_FRAME_SIZE = 4 * 1024 * 1024
MAX_TASKS = 50
LOADED_PAGE_SIZE = 100
MAX_LOADED_PAGES = 10
MAX_LOADED_IDS = LOADED_PAGE_SIZE * MAX_LOADED_PAGES
MAX_CANDIDATE_READS = MAX_TASKS
MAX_ANCESTOR_READS = MAX_TASKS
MAX_CONCURRENT_READS = 8
MAX_CYCLE_REQUESTS = 1 + MAX_LOADED_PAGES + MAX_CANDIDATE_READS + MAX_ANCESTOR_READS
MAX_CYCLE_MESSAGES = 512
DEFAULT_CYCLE_TIMEOUT = 8
POLL_INTERVAL = 10
PUBLISHED = "published"
RECONCILIATION_FAILED = "reconciliation_failed"
PUBLICATION_FAILED = "publication_failed"
RECONCILIATION_NOTIFICATIONS = {
    "thread/status/changed",
    "thread/name/updated",
    "thread/started",
    "thread/closed",
    "thread/archived",
    "thread/unarchived",
    "thread/deleted",
}
generation = str(uuid.uuid4())
sequence = 0


def codex_home():
    return Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))


def configuration_file():
    return (
        Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        / "codex-notch/remote.json"
    )


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


def receive_exact_until(connection, length, deadline, clock=time.monotonic):
    result = bytearray()
    while len(result) < length:
        remaining = deadline - clock()
        if remaining <= 0:
            raise TimeoutError("App Server response deadline exceeded")
        connection.settimeout(remaining)
        try:
            chunk = connection.recv(length - len(result))
        except socket.timeout as error:
            raise TimeoutError("App Server response deadline exceeded") from error
        if clock() > deadline:
            raise TimeoutError("App Server response deadline exceeded")
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
        if not isinstance(acknowledgement, dict):
            raise ValueError("snapshot acknowledgement must be a JSON object")
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

    def send_json(self, value, deadline=None):
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
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("App Server request deadline exceeded")
            self.connection.settimeout(remaining)
        try:
            self.connection.sendall(bytes(header) + mask + masked)
        except socket.timeout as error:
            raise TimeoutError("App Server request deadline exceeded") from error

    def receive_json(self, deadline=None):
        read = (
            (lambda length: receive_exact_until(self.connection, length, deadline))
            if deadline is not None else
            (lambda length: receive_exact(self.connection, length))
        )
        first = read(2)
        opcode = first[0] & 0x0F
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", read(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", read(8))[0]
        if length > MAX_APP_SERVER_FRAME_SIZE:
            raise ValueError("App Server frame is too large")
        mask = read(4) if first[1] & 0x80 else None
        payload = bytearray(read(length))
        if mask:
            for index in range(len(payload)):
                payload[index] ^= mask[index % 4]
        if opcode == 0x8:
            raise ConnectionError("WebSocket closed")
        if opcode == 0x9:
            self.send_control(0xA, payload, deadline=deadline)
            return None
        if opcode != 0x1:
            return None
        return json.loads(payload)

    def send_control(self, opcode, payload, deadline=None):
        mask = secrets.token_bytes(4)
        masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("App Server response deadline exceeded")
            self.connection.settimeout(remaining)
        try:
            self.connection.sendall(
                bytes([0x80 | opcode, 0x80 | len(payload)]) + mask + masked
            )
        except socket.timeout as error:
            raise TimeoutError("App Server response deadline exceeded") from error


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


def reconciliation_row(row):
    """Project an App Server thread to display-only reconciliation metadata."""
    if not isinstance(row, dict):
        return None
    thread_id = canonical_thread_id(row.get("id"))
    if not thread_id:
        return None
    status = row.get("status")
    if not isinstance(status, dict) or not isinstance(status.get("type"), str):
        return None
    flags = status.get("activeFlags")
    if flags is not None and (
        not isinstance(flags, list) or not all(isinstance(flag, str) for flag in flags)
    ):
        return None
    result = {
        "id": thread_id,
        "status": {"type": status["type"]},
    }
    if flags is not None:
        result["status"]["activeFlags"] = flags
    if isinstance(row.get("name"), str):
        result["name"] = row["name"]
    raw_parent = row.get("parentThreadId")
    if raw_parent is not None:
        parent_id = canonical_thread_id(raw_parent)
        if not parent_id:
            return None
        result["parentThreadId"] = parent_id
    updated_at = row.get("updatedAt")
    if isinstance(updated_at, (int, float)) and not isinstance(updated_at, bool):
        result["updatedAt"] = updated_at
    label = project_label(row.get("cwd"))
    if label:
        result["projectLabel"] = label
    git_info = row.get("gitInfo")
    if isinstance(git_info, dict) and isinstance(git_info.get("branch"), str):
        result["gitInfo"] = {"branch": git_info["branch"]}
    if isinstance(row.get("agentNickname"), str):
        result["agentNickname"] = row["agentNickname"]
    if isinstance(row.get("agentRole"), str):
        result["agentRole"] = row["agentRole"]
    return result


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
            "project_label": clean_optional(row.get("projectLabel"), 80)
                or project_label(row.get("cwd")),
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


class LoadedThreadReconciler:
    """Build complete, display-only active-task rows using read-only RPCs."""

    def __init__(self, cycle_timeout=DEFAULT_CYCLE_TIMEOUT, clock=time.monotonic):
        self.cycle_timeout = max(0.01, cycle_timeout)
        self.clock = clock
        self.loaded_thread_reads = None
        self.last_request_count = 0

    @staticmethod
    def method_unavailable(response):
        error = response.get("error") if isinstance(response, dict) else None
        return (
            isinstance(error, dict)
            and type(error.get("code")) is int
            and error["code"] == -32601
        )

    @staticmethod
    def result_object(response):
        if not isinstance(response, dict):
            raise ValueError("App Server response must be a JSON object")
        if response.get("error") is not None:
            raise ConnectionError("App Server request failed")
        result = response.get("result")
        if not isinstance(result, dict):
            raise ValueError("App Server result must be a JSON object")
        return result

    def reconcile(self, call, call_many=None):
        deadline = self.clock() + self.cycle_timeout
        self.last_request_count = 0
        batch_call = call_many or getattr(call, "call_many", None)

        def reserve_requests(count):
            if self.last_request_count + count > MAX_CYCLE_REQUESTS:
                raise TimeoutError("App Server reconciliation work bound reached")
            if self.clock() >= deadline:
                raise TimeoutError("App Server reconciliation deadline exceeded")
            self.last_request_count += count

        def validate_response(response):
            if self.clock() > deadline:
                raise TimeoutError("App Server reconciliation deadline exceeded")
            if not isinstance(response, dict):
                raise ValueError("App Server response must be a JSON object")
            return response

        def request(method, params):
            reserve_requests(1)
            return validate_response(call(method, params, deadline))

        def request_many(requests):
            if batch_call is None:
                return [request(method, params) for method, params in requests]
            reserve_requests(len(requests))
            responses = batch_call(requests, deadline)
            if not isinstance(responses, list) or len(responses) != len(requests):
                raise ValueError("App Server batch response was incomplete")
            return [validate_response(response) for response in responses]

        try:
            baseline_response = request("thread/list", {
                "archived": False,
                "limit": 100,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "useStateDbOnly": True,
            })
            baseline_result = self.result_object(baseline_response)
            raw_rows = baseline_result.get("data")
            if not isinstance(raw_rows, list):
                raise ValueError("thread/list data must be an array")
            listed_rows = {}
            listed_ids = []
            for raw_row in raw_rows:
                safe = reconciliation_row(raw_row)
                if safe is None:
                    raise ValueError("thread/list returned malformed metadata")
                thread_id = safe["id"]
                if thread_id not in listed_rows:
                    listed_ids.append(thread_id)
                listed_rows[thread_id] = safe
            baseline_rows = list(listed_rows.values())
            if self.loaded_thread_reads is False:
                return baseline_rows

            loaded_ids = []
            loaded_set = set()
            seen_cursors = set()
            cursor = None
            page_count = 0
            while True:
                if page_count >= MAX_LOADED_PAGES:
                    raise TimeoutError("loaded-thread page bound reached before EOF")
                params = {"limit": LOADED_PAGE_SIZE}
                if cursor is not None:
                    params["cursor"] = cursor
                loaded_response = request("thread/loaded/list", params)
                page_count += 1
                if self.method_unavailable(loaded_response):
                    self.loaded_thread_reads = False
                    return baseline_rows
                loaded_result = self.result_object(loaded_response)
                raw_ids = loaded_result.get("data")
                if not isinstance(raw_ids, list):
                    raise ValueError("thread/loaded/list data must be an array")
                self.loaded_thread_reads = True
                for raw_id in raw_ids:
                    if not isinstance(raw_id, str):
                        raise ValueError("loaded thread ID must be a string")
                    thread_id = canonical_thread_id(raw_id)
                    if not thread_id:
                        raise ValueError("loaded thread ID must be a UUID")
                    if thread_id in loaded_set:
                        continue
                    if len(loaded_ids) >= MAX_LOADED_IDS:
                        raise TimeoutError("loaded-thread ID bound reached before EOF")
                    loaded_set.add(thread_id)
                    loaded_ids.append(thread_id)

                next_cursor = loaded_result.get("nextCursor")
                if next_cursor in (None, ""):
                    break
                if not isinstance(next_cursor, str):
                    raise ValueError("loaded-thread cursor must be a string or null")
                if page_count >= MAX_LOADED_PAGES or len(loaded_ids) >= MAX_LOADED_IDS:
                    raise TimeoutError("loaded-thread enumeration was incomplete")
                if next_cursor in seen_cursors:
                    raise ValueError("loaded-thread cursor repeated")
                seen_cursors.add(next_cursor)
                cursor = next_cursor

            reconciled = dict(listed_rows)
            for thread_id, row in list(reconciled.items()):
                if row["status"].get("type") == "active":
                    updated = dict(row)
                    updated["status"] = {"type": "notLoaded"}
                    reconciled[thread_id] = updated

            candidates = []
            candidate_set = set()
            for thread_id in listed_ids:
                if thread_id not in loaded_set or thread_id in candidate_set:
                    continue
                candidates.append(thread_id)
                candidate_set.add(thread_id)
                if len(candidates) == MAX_CANDIDATE_READS:
                    break
            if len(candidates) < MAX_CANDIDATE_READS:
                for thread_id in reversed(loaded_ids):
                    if thread_id in candidate_set:
                        continue
                    candidates.append(thread_id)
                    candidate_set.add(thread_id)
                    if len(candidates) == MAX_CANDIDATE_READS:
                        break

            required_ids = list(candidates)
            scheduled_ids = set(candidates)
            ancestor_reads = 0
            index = 0
            while index < len(required_ids):
                batch_ids = required_ids[index:index + MAX_CONCURRENT_READS]
                index += len(batch_ids)
                responses = request_many([
                    ("thread/read", {
                        "threadId": thread_id,
                        "includeTurns": False,
                    })
                    for thread_id in batch_ids
                ])
                for requested_id, read_response in zip(batch_ids, responses):
                    if self.method_unavailable(read_response):
                        self.loaded_thread_reads = False
                        return baseline_rows
                    read_result = self.result_object(read_response)
                    safe = reconciliation_row(read_result.get("thread"))
                    if safe is None or safe["id"] != requested_id:
                        raise ValueError(
                            "thread/read returned malformed or mismatched metadata"
                        )
                    reconciled[requested_id] = safe
                    parent_id = safe.get("parentThreadId")
                    if (
                        parent_id
                        and parent_id not in reconciled
                        and parent_id not in scheduled_ids
                        and ancestor_reads < MAX_ANCESTOR_READS
                    ):
                        scheduled_ids.add(parent_id)
                        required_ids.append(parent_id)
                        ancestor_reads += 1
            return list(reconciled.values())
        except Exception:
            return None


class AppServerRPC:
    def __init__(self, client, first_request_id=2, clock=time.monotonic):
        self.client = client
        self.next_request_id = first_request_id
        self.clock = clock
        self.message_count = 0
        self.refresh_requested = False
        self.transport_failed = False

    def begin_cycle(self):
        self.message_count = 0
        self.refresh_requested = False
        self.transport_failed = False

    def call(self, method, params, deadline):
        return self.call_many([(method, params)], deadline)[0]

    def call_many(self, requests, deadline):
        responses = [None] * len(requests)
        pending = {}
        try:
            for index, (method, params) in enumerate(requests):
                request_id = self.next_request_id
                self.next_request_id += 1
                pending[request_id] = index
                self.client.send_json({
                    "id": request_id,
                    "method": method,
                    "params": params,
                }, deadline=deadline)
            while pending:
                remaining = deadline - self.clock()
                if remaining <= 0:
                    raise TimeoutError("App Server response deadline exceeded")
                ready, _, _ = select.select(
                    [self.client.connection], [], [], remaining
                )
                if not ready:
                    raise TimeoutError("App Server response deadline exceeded")
                message = self.client.receive_json(deadline=deadline)
                self.message_count += 1
                if self.message_count > MAX_CYCLE_MESSAGES:
                    raise TimeoutError("App Server message work bound reached")
                if message is None:
                    continue
                if not isinstance(message, dict):
                    raise ValueError("App Server message must be a JSON object")
                if "id" in message:
                    response_id = message["id"]
                    if type(response_id) is not int:
                        raise ValueError("App Server response ID must be an integer")
                    if response_id in pending:
                        responses[pending.pop(response_id)] = message
                        continue
                    # A timed-out request may answer during a later cycle. Its
                    # response is complete but stale, so it is safe to discard.
                    continue
                if message.get("method") in RECONCILIATION_NOTIFICATIONS:
                    self.refresh_requested = True
            return responses
        except (OSError, ValueError, ConnectionError, TimeoutError, json.JSONDecodeError):
            self.transport_failed = True
            raise


def publish_reconciliation(
    reconciler,
    call,
    configuration,
    sender=send_remote_snapshot,
    call_many=None,
):
    rows = reconciler.reconcile(call, call_many=call_many)
    if rows is None:
        return RECONCILIATION_FAILED
    try:
        sender(configuration, snapshot_from_rows(rows))
        return PUBLISHED
    except Exception:
        return PUBLICATION_FAILED


def retry_interval(_publication_result):
    # Repeated malformed or over-bound App Server state can be just as costly
    # as an offline Mac. Never turn either failure mode into a tight poll loop.
    return POLL_INTERVAL


def initialize_client(client, timeout=5, clock=time.monotonic):
    deadline = clock() + timeout
    client.send_json({
        "id": 1,
        "method": "initialize",
        "params": {
            "clientInfo": {
                "name": "codex-notch-live",
                "title": "Codex Notch",
                "version": "1",
            },
            "capabilities": {"experimentalApi": False},
        },
    }, deadline=deadline)
    messages = 0
    while True:
        remaining = deadline - clock()
        if remaining <= 0:
            raise TimeoutError("App Server initialization deadline exceeded")
        ready, _, _ = select.select([client.connection], [], [], remaining)
        if not ready:
            raise TimeoutError("App Server initialization deadline exceeded")
        message = client.receive_json(deadline=deadline)
        messages += 1
        if messages > MAX_CYCLE_MESSAGES:
            raise TimeoutError("App Server initialization work bound reached")
        if message is None:
            continue
        if not isinstance(message, dict):
            raise ValueError("App Server initialization response must be an object")
        if message.get("id") == 1:
            if message.get("error") is not None or not isinstance(
                message.get("result"), dict
            ):
                raise ConnectionError("App Server initialization failed")
            client.send_json({"method": "initialized"}, deadline=deadline)
            return


def observe(path, configuration):
    client = UnixWebSocket(path)
    try:
        initialize_client(client)
        reconciler = LoadedThreadReconciler()
        rpc = AppServerRPC(client)
        refresh_requested = True
        next_poll = time.monotonic()
        while True:
            now = time.monotonic()
            if refresh_requested or now >= next_poll:
                rpc.begin_cycle()
                publication_result = publish_reconciliation(
                    reconciler,
                    rpc.call,
                    configuration,
                    call_many=rpc.call_many,
                )
                if rpc.transport_failed:
                    raise ConnectionError("App Server reconciliation transport failed")
                refresh_requested = (
                    publication_result == PUBLISHED and rpc.refresh_requested
                )
                next_poll = time.monotonic() + retry_interval(publication_result)
                if refresh_requested:
                    continue

            remaining = max(0, next_poll - time.monotonic())
            ready, _, _ = select.select([client.connection], [], [], remaining)
            if not ready:
                continue
            deadline = time.monotonic() + min(DEFAULT_CYCLE_TIMEOUT, max(0.01, remaining))
            message = client.receive_json(deadline=deadline)
            if message is None:
                continue
            if not isinstance(message, dict):
                raise ValueError("App Server message must be a JSON object")
            if message.get("method") in RECONCILIATION_NOTIFICATIONS:
                refresh_requested = True
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
