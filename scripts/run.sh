
#!/usr/bin/env bash
set -Eeuo pipefail

BASE="https://raw.githubusercontent.com/siddharthjain25/pocket/main"
BIN_DIR="${HOME}/.local/bin"
CONFIG_DIR="${HOME}/.config/pocket"
CLIENT="${BIN_DIR}/tcp-connect.sh"
CONFIG="${CONFIG_DIR}/tcp.conf"

die() {
    echo "Pocket Key: $*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required."
command -v uname >/dev/null 2>&1 || die "uname is required."

[[ "$(uname -s)" == Linux ]] || die "Linux only for now."

case "$(uname -m)" in
    x86_64|amd64) PLATFORM="linux/x86_64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

mkdir -p "$BIN_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR"

download() {
    local url="$1" output="$2"
    curl --fail --location --silent --show-error \
        --proto '=https' --tlsv1.2 "$url" -o "$output"
}

# Bootstrap the Ncat installer from the Pocket repository.
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "[1/3] Downloading Ncat installer..."
download "$BASE/scripts/install-nc.sh" "$TMP"
bash "$TMP"

# Install the TCP client script locally.
echo "[2/3] Installing TCP client..."
download "$BASE/scripts/tcp-connect.sh" "$CLIENT"
chmod 700 "$CLIENT"

# Create config template if this is the first run.
if [[ ! -f "$CONFIG" ]]; then
    cat > "$CONFIG" <<'EOF'
# Configure your trusted TLS endpoint before connecting.
POCKET_HOST="replace-with-your-server-hostname"
POCKET_PORT="443"
POCKET_CA="${HOME}/.config/pocket/ca.pem"
EOF
    chmod 600 "$CONFIG"

    echo
    echo "Bootstrap complete. One-time configuration is required:"
    echo "  $CONFIG"
    echo "Place your trusted CA certificate at:"
    echo "  $CONFIG_DIR/ca.pem"
    echo "Then run this script again."
    exit 0
fi

# Do not silently connect with placeholder settings.
if grep -q 'replace-with-your-server-hostname' "$CONFIG"; then
    die "Edit $CONFIG and configure your server first."
fi

echo "[3/3] Starting authenticated TLS TCP client..."
exec "$CLIENT"
