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

# ── Detect display mode ──────────────────────────────────────────
# Force a mode with: FIRASIM_MODE=x11 or FIRASIM_MODE=vnc
MODE="${FIRASIM_MODE:-auto}"

if [[ "$MODE" == "auto" ]]; then
    # Check if X11 socket exists (works on X11, not on Wayland-only)
    if [[ -n "${DISPLAY:-}" ]] && [[ -e "/tmp/.X11-unix/X${DISPLAY#:}" || -e "/tmp/.X11-unix/X0" ]]; then
        MODE="x11"
    else
        MODE="vnc"
    fi
fi

echo "Display mode: $MODE"

if [[ "$MODE" == "x11" ]]; then
    # ── X11 mode: share host display directly ────────────────────
    echo "Starting FIRASim with host X11 display ($DISPLAY)..."

    # Allow the container to access the X server
    xhost +local:docker 2>/dev/null || true

    docker run --rm -it \
        --network=host \
        -e DISPLAY="$DISPLAY" \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        --name "$CONTAINER" \
        "$IMAGE" "$@"

    # Revoke X access when done
    xhost -local:docker 2>/dev/null || true
    echo "FIRASim closed."

else
    # ── VNC mode: virtual display + VNC viewer ───────────────────
    echo "Starting FIRASim container in VNC mode (geometry: $GEOMETRY)..."
    docker run --rm -d \
        --network=host \
        -e VNC_PASSWORD="$VNC_PASS" \
        -e VNC_GEOMETRY="$GEOMETRY" \
        --name "$CONTAINER" \
        "$IMAGE" vnc "$@" >/dev/null

    # ── Wait for VNC server to be ready ──────────────────────────
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

    # ── Store VNC password for vncviewer ─────────────────────────
    VNC_PASSWD_FILE=$(mktemp)
    trap 'rm -f "$VNC_PASSWD_FILE"; docker stop "$CONTAINER" &>/dev/null || true; echo "Container stopped."' EXIT

    vncpasswd -f <<< "$VNC_PASS" > "$VNC_PASSWD_FILE" 2>/dev/null

    # ── Connect with vncviewer ───────────────────────────────────
    echo "Connecting to FIRASim..."
    vncviewer -passwd "$VNC_PASSWD_FILE" localhost:"$VNC_PORT" 2>/dev/null || true

    echo "VNC viewer closed."
fi
