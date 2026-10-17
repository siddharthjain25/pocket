#!/usr/bin/env bash
set -Eeuo pipefail

DIR="${HOME}/.config/pocket"
CONFIG="${DIR}/tcp.conf"

mkdir -p "$DIR"
chmod 700 "$DIR"

if [[ -e "$CONFIG" ]]; then
    echo "Config already exists: $CONFIG"
    echo "Edit it manually; leaving it unchanged."
    exit 0
fi

cat > "$CONFIG" <<'EOF'
# Pocket Key TCP client configuration.
# Replace these example values before connecting.
POCKET_HOST="tcp.example.com"
POCKET_PORT="443"
POCKET_CA="${HOME}/.config/pocket/ca.pem"
EOF

chmod 600 "$CONFIG"

echo "Created $CONFIG"
echo "Edit the host, port, and trusted CA certificate path."
echo "Obtain the CA certificate from your trusted server administrator."
