# Remote protocol v1

Codex Notch remote delivery is a small authenticated protocol carried over a
private Tailscale TCP connection.

## Transport

- TCP port: `47391`
- Listener address: the Mac's Tailscale IPv4 address only
- Frame: unsigned 32-bit big-endian length followed by UTF-8 JSON
- Maximum JSON payload: 4096 bytes
- One request and one acknowledgement per connection

## Request

```json
{
  "protocol_version": 1,
  "kind": "completion",
  "token": "64 lowercase hexadecimal characters",
  "event": {
    "schema_version": 1,
    "event_id": "sha256(v1\\0 + lowercase thread_id + \\0 + turn_id)",
    "thread_id": "UUID",
    "turn_id": "opaque string",
    "title": "Codex task finished",
    "source_id": "host UUID",
    "source_label": "Ubuntu",
    "completed_at": "2026-07-14T12:00:00Z"
  }
}
```

The receiver recomputes `event_id`, and replaces `source_id` and `source_label`
with the identity belonging to the authenticated token. `kind: "ping"` omits
`event`.

## Acknowledgement

```json
{
  "protocol_version": 1,
  "status": "accepted",
  "event_id": "matching event id"
}
```

Valid completion statuses are `accepted`, `duplicate`, and `rejected`. A sender
deletes an outbox entry only after `accepted` or `duplicate` with the matching
event ID. A ping succeeds with `status: "pong"`.
