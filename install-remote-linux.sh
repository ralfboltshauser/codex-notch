#!/bin/sh
set -eu

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
  echo "Usage: $0 MAC_TAILSCALE_HOST PAIRING_TOKEN [HOST_LABEL] [HOST_ID]" >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required" >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INSTALL_DIR="$HOME/.local/lib/codex-notch"
HOOK="$INSTALL_DIR/codex_notch_remote-v1.py"
SOURCE_NAME=${3:-$(hostname -s)}
HOST_ID=${4:-$(hostname -s)}

mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/remote/codex_notch_remote.py" "$HOOK"
ENDPOINT_HOST=$1 PAIRING_TOKEN=$2 HOST_ID=$HOST_ID SOURCE_NAME=$SOURCE_NAME \
  python3 -c 'import json, os; print(json.dumps({
    "endpoint_host": os.environ["ENDPOINT_HOST"],
    "endpoint_port": 47391,
    "token": os.environ["PAIRING_TOKEN"],
    "host_id": os.environ["HOST_ID"],
    "source_name": os.environ["SOURCE_NAME"],
  }))' | "$HOOK" --install-json

echo "Installed the Ubuntu publisher at $HOOK"
echo "Codex Notch will label notifications with: $SOURCE_NAME"
echo "Open Codex on this host, run /hooks, and trust 'Queueing completion for Codex Notch'."
