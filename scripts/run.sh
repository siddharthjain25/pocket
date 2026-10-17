
#!/usr/bin/env bash
set -Eeuo pipefail

CLIENT="${HOME}/.local/bin/tcp-connect.sh"

if [[ ! -x "$CLIENT" ]]; then
    echo "Pocket Key TCP client not installed."
    echo "Place tcp-connect.sh at: $CLIENT"
    exit 1
fi

exec "$CLIENT"
