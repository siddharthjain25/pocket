#!/usr/bin/env bash
set -Eeuo pipefail

BASE="https://raw.githubusercontent.com/siddharthjain25/pocket/main"
BIN_DIR="${HOME}/.local/bin"
NC_BIN="${BIN_DIR}/nc"
LISTENER="${BIN_DIR}/pocket-listen.sh"

die() { printf 'Pocket Key: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "curl is required."
[[ "$(uname -s)" == "Linux" ]] || die "Linux only for now."
case "$(uname -m)" in
    x86_64|amd64) ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
esac

mkdir -p "$BIN_DIR"
chmod 700 "$BIN_DIR"

download() {
    curl --fail --location --silent --show-error \
        --proto '=https' --tlsv1.2 "$1" -o "$2"
}

if [[ ! -x "$NC_BIN" ]]; then
    printf '[1/3] Installing Ncat...\n'
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    download "$BASE/scripts/install-nc.sh" "$tmp"
    bash "$tmp"
    rm -f "$tmp"
    trap - EXIT
else
    printf '[1/3] Ncat already installed: %s\n' "$NC_BIN"
fi

printf '[2/3] Installing listener script...\n'
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
download "$BASE/scripts/pocket-listen.sh" "$tmp"
install -m 700 "$tmp" "$LISTENER"
rm -f "$tmp"
trap - EXIT

PORT="${1:-5000}"
[[ "$PORT" =~ ^[0-9]+$ ]] || die "Usage: run.sh [port]"
(( PORT >= 1 && PORT <= 65535 )) || die "Port must be between 1 and 65535."

printf '[3/3] Starting TCP listener on port %s...\n' "$PORT"
printf 'Plain TCP only; no authentication, encryption, or remote shell.\n'
exec "$LISTENER" "$PORT"
