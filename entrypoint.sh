#!/usr/bin/env bash
set -e

AUTO_UPDATE="${AUTO_UPDATE:-true}"

if [ "$AUTO_UPDATE" = "true" ]; then
    echo "Checking for Hermes updates..."
    cd /opt/hermes-agent
    if git pull --recurse-submodules 2>&1 | grep -v 'Already up to date'; then
        echo "Updating dependencies..."
        VIRTUAL_ENV=/opt/hermes-agent/venv uv pip install -e ".[all]" --quiet
        echo "Update complete."
    else
        echo "Already up to date."
    fi
fi

# ── Tailscale (userspace networking — Railway has no /dev/net/tun) ──
echo "[tailscale] Starting daemon..."
tailscaled \
    --tun=userspace-networking \
    --state=/root/.hermes/tailscale \
    --socket=/run/tailscale/tailscaled.sock &

# Wait for socket
for i in $(seq 1 30); do
    [ -S /run/tailscale/tailscaled.sock ] && break
    sleep 1
done

if [ -n "${TS_AUTHKEY:-}" ]; then
    if tailscale --socket=/run/tailscale/tailscaled.sock status >/dev/null 2>&1; then
        echo "[tailscale] Already authenticated"
    else
        echo "[tailscale] Authenticating..."
        tailscale --socket=/run/tailscale/tailscaled.sock up \
            --auth-key="${TS_AUTHKEY}" \
            --hostname="${TS_HOSTNAME:-railway-hermes}" \
            --accept-routes
        echo "[tailscale] Authenticated"
    fi
else
    echo "[tailscale] TS_AUTHKEY not set — daemon running, not authenticated" >&2
fi

# ── Hermes Dashboard ──
# Bind 0.0.0.0 for Tailscale access (Desktop app + web browser)
echo "[hermes] Starting dashboard on 0.0.0.0:9119..."
hermes dashboard --host 0.0.0.0 --port 9119 --no-open &

# ── Hermes WebUI ──
# Mobile-friendly chat interface on port 8787
echo "[webui] Starting on 0.0.0.0:8787..."
cd /opt/hermes-webui
HERMES_WEBUI_HOST=0.0.0.0 HERMES_WEBUI_PORT=8787 python server.py &

# ── Auth Proxy ──
# Public-facing proxy (port 8080) — also reachable via Tailscale
cd /
echo "[proxy] Starting auth proxy on 0.0.0.0:8080..."
exec python /auth_proxy.py
