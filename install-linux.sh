#!/usr/bin/env bash
# Pocket Key Linux installer. This script is downloaded and run by the ESP32 HID launcher.
set -Eeuo pipefail

fail() { printf '\n[POCKET INSTALL] ERROR: %s\n' "$*" >&2; exit 1; }
log() { printf '[POCKET INSTALL] %s\n' "$*"; }

[[ "$(uname -s)" == Linux ]] || fail "This installer currently supports Linux only. Windows agent is not included."
for v in POCKET_PI POCKET_ENROLLMENT_TOKEN POCKET_LISTENER_HOST_PUBLIC_KEY POCKET_AGENT_BINARY_URL_AMD64 POCKET_AGENT_BINARY_URL_ARM64; do
  [[ -n "${!v:-}" ]] || fail "$v is not configured in the ESP32 sketch."
done
[[ "$POCKET_ENROLLMENT_TOKEN" != CHANGE_ME* ]] || fail "Set a strong POCKET_ENROLLMENT_TOKEN first."
[[ "$POCKET_LISTENER_HOST_PUBLIC_KEY" == ssh-* ]] || fail "POCKET_LISTENER_HOST_PUBLIC_KEY must be the listener's verified public host-key line."
command -v curl >/dev/null 2>&1 || fail "curl is required. Install curl and retry."
command -v systemctl >/dev/null 2>&1 || fail "systemd is required for automatic user-service startup."

BASE="${XDG_CONFIG_HOME:-$HOME/.config}/pocket-agent"
BIN_DIR="${HOME}/.local/bin"
KEY_PATH="${BASE}/id_ed25519"
HOST_KEY_PATH="${BASE}/listener_host.pub"
BIN_PATH="${BIN_DIR}/pocket-agent"
UNIT_PATH="${HOME}/.config/systemd/user/pocket-agent.service"

umask 077
mkdir -p "$BASE" "$BIN_DIR" "$(dirname "$UNIT_PATH")"
chmod 700 "$BASE"

case "$(uname -m)" in
  x86_64|amd64) AGENT_URL="$POCKET_AGENT_BINARY_URL_AMD64" ;;
  aarch64|arm64) AGENT_URL="$POCKET_AGENT_BINARY_URL_ARM64" ;;
  *) fail "Unsupported Linux architecture: $(uname -m). Build and publish an agent binary for this architecture first." ;;
esac

log "Downloading the configured Linux agent binary for $(uname -m)..."
TMP_BIN="$(mktemp)"
trap 'rm -f "$TMP_BIN"' EXIT
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$AGENT_URL" -o "$TMP_BIN" || fail "Could not download the agent binary. Publish the rebuilt Linux agent at the configured URL."
file "$TMP_BIN" >/dev/null 2>&1 || true
install -m 700 "$TMP_BIN" "$BIN_PATH"

# The public host key is pinned locally; SSH host verification is never disabled.
printf '%s\n' "$POCKET_LISTENER_HOST_PUBLIC_KEY" > "$HOST_KEY_PATH"
chmod 600 "$HOST_KEY_PATH"

export POCKET_AGENT_KEY="$KEY_PATH"
export POCKET_LISTENER_HOST_PUBLIC_KEY="$HOST_KEY_PATH"
export POCKET_AGENT_NAME="$(hostname | tr -cs 'A-Za-z0-9._-' '-')"
export POCKET_PI
export POCKET_ENROLLMENT_TOKEN

log "Generating a unique private key on this computer and enrolling its public key with the Pi..."
"$BIN_PATH" --enroll-only || fail "Enrollment failed. Check the Pi address, pinned host key, enrollment token, and listener logs."

cat > "$UNIT_PATH" <<EOF
[Unit]
Description=Pocket Key Linux Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=POCKET_PI=$POCKET_PI
Environment=POCKET_AGENT_KEY=$KEY_PATH
Environment=POCKET_LISTENER_HOST_PUBLIC_KEY=$HOST_KEY_PATH
ExecStart=$BIN_PATH
Restart=on-failure
RestartSec=5
NoNewPrivileges=true

[Install]
WantedBy=default.target
EOF
chmod 600 "$UNIT_PATH"

log "Enabling the agent user service..."
systemctl --user daemon-reload || fail "Could not reload the user systemd manager."
systemctl --user enable --now pocket-agent.service || fail "Could not start the service. Check 'journalctl --user -u pocket-agent.service'."

log "Installed and enrolled. The private key remains on this computer."
log "Service status: systemctl --user status pocket-agent.service"
log "Agent logs: journalctl --user -u pocket-agent.service -f"
log "Check the Pi listener console for the device's connected status."
