#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x server/.venv/bin/python ]]; then
  echo 'Run uv sync --directory server --locked first.' >&2
  exit 1
fi
# Refuse to use or stop an unrelated process on the fixture port.
server/.venv/bin/python - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(('127.0.0.1', 8765))
PY
run_dir="$(mktemp -d)"
(cd server && exec .venv/bin/python -m tests.contract_server) > "$run_dir/server.log" 2>&1 &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true; wait "$fixture_pid" 2>/dev/null || true; rm -rf "$run_dir"' EXIT
ready=false
for attempt in $(seq 1 30); do
  if curl --fail --silent http://127.0.0.1:8765/health > /dev/null; then
    ready=true
    break
  fi
  if ! kill -0 "$fixture_pid" 2>/dev/null; then
    cat "$run_dir/server.log" >&2
    exit 1
  fi
  sleep 0.2
done
if [[ "$ready" != true ]]; then
  cat "$run_dir/server.log" >&2
  exit 1
fi
LINGUAMATE_TEST_BASE_URL=http://127.0.0.1:8765 bash scripts/test-core.sh
