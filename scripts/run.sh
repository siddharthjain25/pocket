#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Pocket Key: this script supports Linux only."
  exit 1
fi

echo "Pocket Key Linux helper"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  echo "Detected: ${PRETTY_NAME:-Linux}"
fi
echo
echo "Safe starter script: add your intended, non-sensitive action here."
echo "No passwords are stored, printed, or transmitted by this script."
