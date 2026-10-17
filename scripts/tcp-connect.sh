
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG="${HOME}/.config/pocket/tcp.conf"
NC_BIN="${HOME}/.local/bin/nc"

die() {
    printf 'Pocket Key: %s\n' "$*" >&2
    exit 1
}

[[ -r "$CONFIG" ]] || die "Missing config: $CONFIG"
[[ -x "$NC_BIN" ]] || die "Ncat not installed. Run install-nc.sh first."

# Config is a local, user-owned shell configuration file.
# Never download or source this file from GitHub.
# shellcheck disable=SC1090
source "$CONFIG"

: "${POCKET_HOST:?Set POCKET_HOST in $CONFIG}"
: "${POCKET_PORT:?Set POCKET_PORT in $CONFIG}"
: "${POCKET_CA:?Set POCKET_CA in $CONFIG}"

[[ "$POCKET_PORT" =~ ^[0-9]+$ ]] ||
    die "Port must be numeric."

(( POCKET_PORT >= 1 && POCKET_PORT <= 65535 )) ||
    die "Port must be between 1 and 65535."

[[ -r "$POCKET_CA" ]] || die "CA certificate not found: $POCKET_CA"

printf 'Connecting to %s:%s using TLS...\n' "$POCKET_HOST" "$POCKET_PORT"
printf 'Press Ctrl+C to disconnect.\n'

exec "$NC_BIN" \
    --ssl \
    --ssl-verify \
    --ssl-trustfile "$POCKET_CA" \
    --idle-timeout 60s \
    "$POCKET_HOST" "$POCKET_PORT"
