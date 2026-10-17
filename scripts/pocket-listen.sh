#!/usr/bin/env bash
set -Eeuo pipefail

NC_BIN="${HOME}/.local/bin/nc"
PORT="${1:-5000}"

die() { printf 'Pocket listener: %s\n' "$*" >&2; exit 1; }

[[ -x "$NC_BIN" ]] || die "Ncat not found. Run scripts/run.sh first."
[[ "$PORT" =~ ^[0-9]+$ ]] || die "Usage: pocket-listen.sh [port]"
(( PORT >= 1 && PORT <= 65535 )) || die "Port must be between 1 and 65535."

printf 'Listening on TCP port %s. Press Ctrl+C to stop.\n' "$PORT"
printf 'Anyone who can reach this port may exchange plain text. Do not send secrets.\n'
exec "$NC_BIN" --listen --verbose "$PORT"
