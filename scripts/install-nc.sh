#!/usr/bin/env bash
set -Eeuo pipefail

# Pocket Key: download a portable Ncat binary and expose it as `nc`.
# Installs into ~/.local/bin; no root privileges required.

REPO="https://raw.githubusercontent.com/andrew-d/static-binaries/master"
INSTALL_DIR="${HOME}/.local/bin"
TMP_FILE=""

cleanup() {
    [[ -z "${TMP_FILE}" ]] || rm -f -- "${TMP_FILE}"
}
trap cleanup EXIT

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

command -v curl >/dev/null 2>&1 || die "curl is required."
command -v chmod >/dev/null 2>&1 || die "chmod is required."
command -v uname >/dev/null 2>&1 || die "uname is required."

OS="$(uname -s)"
ARCH="$(uname -m)"

[[ "$OS" == "Linux" ]] || die "Unsupported OS: ${OS}. This installer supports Linux only."

case "$ARCH" in
    x86_64|amd64)
        PLATFORM="linux/x86_64"
        ;;
    *)
        die "No verified Ncat mapping configured for architecture: ${ARCH}"
        ;;
esac

URL="${REPO}/binaries/${PLATFORM}/ncat"

mkdir -p -- "$INSTALL_DIR"
TMP_FILE="$(mktemp "${INSTALL_DIR}/.ncat.XXXXXX")"

printf 'Detected OS: %s\nArchitecture: %s\n' "$OS" "$ARCH"
printf 'Downloading Ncat from:\n%s\n' "$URL"

curl --fail --location --silent --show-error \
    --proto '=https' --tlsv1.2 \
    "$URL" --output "$TMP_FILE" ||
    die "Download failed."

# Verify the download is an executable Linux ELF file before installing.
if ! command -v file >/dev/null 2>&1; then
    die "'file' is needed to verify the downloaded binary. Install it and retry."
fi

FILE_INFO="$(file -b "$TMP_FILE")"
printf 'Downloaded file: %s\n' "$FILE_INFO"

[[ "$FILE_INFO" == *ELF* ]] ||
    die "Downloaded content is not an ELF executable; refusing to install."

chmod 0755 "$TMP_FILE"
"$TMP_FILE" --version >/dev/null 2>&1 ||
    die "The downloaded Ncat binary failed its startup check."

# Keep the actual Ncat executable, plus an `nc` command name.
mv -f -- "$TMP_FILE" "${INSTALL_DIR}/ncat"
TMP_FILE=""
ln -sfn ncat "${INSTALL_DIR}/nc"

printf '\nInstalled:\n  %s/ncat\n  %s/nc\n' "$INSTALL_DIR" "$INSTALL_DIR"

case ":${PATH}:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        printf '\nAdd this to your shell config if needed:\n'
        printf '  export PATH="$HOME/.local/bin:$PATH"\n'
        ;;
esac

printf '\nTest with:\n  %s/nc --help\n' "$INSTALL_DIR"
