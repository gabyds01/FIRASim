#!/usr/bin/env bash
set -euo pipefail

IMAGE="firasim"
CONTAINER="firasim"
VNC_PORT=5900
VNC_PASS="vncpassword"
GEOMETRY="${VNC_GEOMETRY:-1920x1080}"

# ── Build image if it doesn't exist ──────────────────────────────
if ! docker image inspect "$IMAGE" &>/dev/null; then
    echo "Image '$IMAGE' not found, building..."
    docker build -t "$IMAGE" "$(dirname "$0")"
fi

# ── Stop any previous container ──────────────────────────────────
if docker ps -q -f name="^${CONTAINER}$" | grep -q .; then
    echo "Stopping previous container..."
    docker stop "$CONTAINER" &>/dev/null || true
fi

# ── Start container in background ────────────────────────────────
echo "Starting FIRASim container (geometry: $GEOMETRY)..."
docker run --rm -d \
    -p "${VNC_PORT}:5900" \
    -e VNC_PASSWORD="$VNC_PASS" \
    -e VNC_GEOMETRY="$GEOMETRY" \
    --name "$CONTAINER" \
    "$IMAGE" vnc >/dev/null

# ── Wait for VNC server to be ready ──────────────────────────────
echo -n "Waiting for VNC server"
VNC_READY=false
for i in $(seq 1 60); do
    # Check for actual VNC handshake (server sends "RFB" when ready)
    if timeout 1 bash -c "head -c3 </dev/tcp/localhost/${VNC_PORT}" 2>/dev/null | grep -q "RFB"; then
        echo " ready"
        VNC_READY=true
        break
    fi
    echo -n "."
    sleep 0.5
done

if [ "$VNC_READY" = false ]; then
    echo ""
    echo "ERROR: VNC server did not start. Container logs:"
    docker logs "$CONTAINER" 2>&1 | tail -20
    docker stop "$CONTAINER" &>/dev/null || true
    exit 1
fi

# ── Store VNC password for vncviewer ─────────────────────────────
VNC_PASSWD_FILE=$(mktemp)
trap 'rm -f "$VNC_PASSWD_FILE"; docker stop "$CONTAINER" &>/dev/null || true; echo "Container stopped."' EXIT

vncpasswd -f <<< "$VNC_PASS" > "$VNC_PASSWD_FILE" 2>/dev/null

# ── Connect with vncviewer ───────────────────────────────────────
echo "Connecting to FIRASim..."
vncviewer -passwd "$VNC_PASSWD_FILE" localhost:"$VNC_PORT" 2>/dev/null || true

echo "VNC viewer closed."
