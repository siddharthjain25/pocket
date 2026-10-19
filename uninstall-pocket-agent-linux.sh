```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# Pocket Agent uninstaller — current user only.
# Does not modify the Raspberry Pi or unrelated ~/.ssh files.

BIN="$HOME/.local/bin/pocket-agent"
SERVICE="$HOME/.config/systemd/user/pocket-agent.service"

TARGETS=(
  "$HOME/.config/pocket-agent"
  "$HOME/.config/pocket-key"
  "$HOME/.config/pocket/tcp.conf"
  "$BIN"
  "$SERVICE"
)

echo "Pocket Agent uninstall"
echo "User: $USER"
echo
echo "The following paths may be removed:"
for path in "${TARGETS[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then
    printf '  [found] %s\n' "$path"
  else
    printf '  [absent] %s\n' "$path"
  fi
done

echo
echo "This will not delete ~/.ssh, the Pi installation, or system-wide files."
read -r -p "Type REMOVE to continue: " answer
[[ "$answer" == "REMOVE" ]] || {
  echo "Cancelled."
  exit 0
}

# Stop and disable only the named user service.
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user disable --now pocket-agent.service \
    >/dev/null 2>&1 || true
fi

# Remove only the listed, known installation paths.
for path in "${TARGETS[@]}"; do
  if [[ -L "$path" || -f "$path" ]]; then
    rm -f -- "$path"
  elif [[ -d "$path" ]]; then
    rm -rf -- "$path"
  fi
done

# Refresh the user service manager.
if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user reset-failed pocket-agent.service \
    >/dev/null 2>&1 || true
fi

echo
echo "Pocket Agent uninstall finished."
echo "Unrelated SSH files and the Raspberry Pi were left untouched."
echo "This does not erase system logs, shell history, backups, or other copies."
```
