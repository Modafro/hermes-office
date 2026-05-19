#!/usr/bin/env bash
# clawd3d-start — Start all Clawd3D services, auto-resolving port conflicts.
#
# Setup (once):
#   echo 'alias clawd3d="/absolute/path/to/Claw3D/scripts/clawd3d-start.sh"' >> ~/.zshrc
#   source ~/.zshrc
#
# Then just run:  clawd3d

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CLAWD3D_DIR="$(cd -- "$SCRIPT_DIR/.." >/dev/null 2>&1 && pwd)"
LOG_DIR="/tmp/clawd3d-logs"
mkdir -p "$LOG_DIR"
LOOPBACK_HOST="${CLAWD3D_HOST:-127.0.0.1}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[clawd3d]${NC} $*"; }
warn() { echo -e "${YELLOW}[clawd3d]${NC} $*"; }
info() { echo -e "${BLUE}[clawd3d]${NC} $*"; }

# ── Helpers ───────────────────────────────────────────────────────────────────

# Returns PIDs *listening* on a port (excludes client connections), or empty.
pids_on_port() { lsof -ti:"$1" -sTCP:LISTEN 2>/dev/null || true; }

# True if the port is free.
port_free() { [ -z "$(pids_on_port "$1")" ]; }

# Find first free port >= $1.
find_free_port() {
  local p=$1
  while ! port_free "$p"; do p=$((p + 1)); done
  echo "$p"
}

# True if every PID on $port matches the grep pattern in its command line.
port_owned_by() {
  local port=$1 pattern=$2
  local pids
  pids=$(pids_on_port "$port")
  [ -z "$pids" ] && return 1
  while IFS= read -r pid; do
    local cmd
    cmd=$(ps -p "$pid" -o command= 2>/dev/null || true)
    if ! echo "$cmd" | grep -qE "$pattern"; then
      return 1
    fi
  done <<< "$pids"
  return 0
}

# Find the first port in [start, end] owned by a matching process.
find_owned_port() {
  local start=$1 end=$2 pattern=$3 p
  for p in $(seq "$start" "$end"); do
    if port_owned_by "$p" "$pattern"; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

open_browser() {
  local url=$1
  if command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then
    open "$url" >/dev/null 2>&1 || true
  fi
}

# ── 1. Hermes gateway (API, default 8642) ────────────────────────────────────
HERMES_PORT=8642
if ! port_free $HERMES_PORT; then
  if port_owned_by $HERMES_PORT "hermes"; then
    warn "Hermes gateway already running on :$HERMES_PORT — reusing."
  else
    HERMES_PORT=$(find_free_port $((HERMES_PORT + 1)))
    warn "Port 8642 taken by another process → using :$HERMES_PORT for Hermes."
    log "Starting Hermes gateway on :$HERMES_PORT..."
    nohup env API_SERVER_PORT="$HERMES_PORT" hermes gateway run \
      > "$LOG_DIR/hermes-gateway.log" 2>&1 &
    sleep 2
  fi
else
  log "Starting Hermes gateway on :$HERMES_PORT..."
  nohup hermes gateway run > "$LOG_DIR/hermes-gateway.log" 2>&1 &
  sleep 2
fi
HERMES_API_URL="http://$LOOPBACK_HOST:$HERMES_PORT"

# ── 2. Hermes adapter (WebSocket bridge, default 18789) ──────────────────────
ADAPTER_PORT=18789
ADAPTER_PATTERN="node.*hermes-gateway-adapter"
if ! port_free $ADAPTER_PORT; then
  if port_owned_by $ADAPTER_PORT "$ADAPTER_PATTERN"; then
    warn "Hermes adapter already running on :$ADAPTER_PORT — reusing."
  else
    existing_adapter_port=$(find_owned_port $((ADAPTER_PORT + 1)) $((ADAPTER_PORT + 50)) "$ADAPTER_PATTERN" || true)
    if [ -n "$existing_adapter_port" ]; then
      ADAPTER_PORT="$existing_adapter_port"
      warn "Hermes adapter already running on :$ADAPTER_PORT — reusing."
    else
      ADAPTER_PORT=$(find_free_port $((ADAPTER_PORT + 1)))
      warn "Port 18789 taken by another process → using :$ADAPTER_PORT for adapter."
      log "Starting Hermes adapter on :$ADAPTER_PORT..."
      cd "$CLAWD3D_DIR"
      nohup env HERMES_ADAPTER_HOST="$LOOPBACK_HOST" HERMES_ADAPTER_PORT="$ADAPTER_PORT" HERMES_ADAPTER_STRICT_PORT=true HERMES_API_URL="$HERMES_API_URL" \
        npm run hermes-adapter > "$LOG_DIR/hermes-adapter.log" 2>&1 &
      sleep 1
    fi
  fi
else
  log "Starting Hermes adapter on :$ADAPTER_PORT..."
  cd "$CLAWD3D_DIR"
  nohup env HERMES_ADAPTER_HOST="$LOOPBACK_HOST" HERMES_ADAPTER_PORT="$ADAPTER_PORT" HERMES_ADAPTER_STRICT_PORT=true HERMES_API_URL="$HERMES_API_URL" \
    npm run hermes-adapter > "$LOG_DIR/hermes-adapter.log" 2>&1 &
  sleep 1
fi
GATEWAY_WS_URL="ws://$LOOPBACK_HOST:$ADAPTER_PORT"

# ── 3. Next.js dev server (default 3000) ─────────────────────────────────────
APP_PORT=3000
if ! port_free $APP_PORT; then
  if port_owned_by $APP_PORT "node.*next|next-server|server/index\.js"; then
    warn "Clawd3D dev server already running on :$APP_PORT — reusing."
  else
    APP_PORT=$(find_free_port $((APP_PORT + 1)))
    warn "Port 3000 taken by another process → using :$APP_PORT for Clawd3D."
    log "Starting Clawd3D dev server on :$APP_PORT..."
    cd "$CLAWD3D_DIR"
    nohup env HOST="$LOOPBACK_HOST" PORT="$APP_PORT" NEXT_PUBLIC_GATEWAY_URL="$GATEWAY_WS_URL" CLAW3D_GATEWAY_URL="$GATEWAY_WS_URL" CLAW3D_GATEWAY_ADAPTER_TYPE=hermes HERMES_ADAPTER_PORT="$ADAPTER_PORT" \
      npm run dev > "$LOG_DIR/clawd3d-dev.log" 2>&1 &
  fi
else
  log "Starting Clawd3D dev server on :$APP_PORT..."
  cd "$CLAWD3D_DIR"
  nohup env HOST="$LOOPBACK_HOST" PORT="$APP_PORT" NEXT_PUBLIC_GATEWAY_URL="$GATEWAY_WS_URL" CLAW3D_GATEWAY_URL="$GATEWAY_WS_URL" CLAW3D_GATEWAY_ADAPTER_TYPE=hermes HERMES_ADAPTER_PORT="$ADAPTER_PORT" \
    npm run dev > "$LOG_DIR/clawd3d-dev.log" 2>&1 &
fi

# ── 4. Wait until the app responds ───────────────────────────────────────────
log "Waiting for Clawd3D to be ready at :$APP_PORT..."
ready=0
for i in $(seq 1 90); do
  if curl -sf "http://$LOOPBACK_HOST:$APP_PORT" > /dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
if [ "$ready" -eq 0 ]; then
  warn "Timed out waiting for :$APP_PORT — check $LOG_DIR/clawd3d-dev.log"
fi

# ── 5. Open browser ───────────────────────────────────────────────────────────
if [ "${CLAWD3D_NO_OPEN:-0}" != "1" ]; then
  open_browser "http://$LOOPBACK_HOST:$APP_PORT"
fi

echo ""
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log " Clawd3D      →  http://$LOOPBACK_HOST:$APP_PORT"
info " Gateway WS   →  $GATEWAY_WS_URL"
info " Hermes API   →  $HERMES_API_URL"
info " Logs         →  $LOG_DIR/"
log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
