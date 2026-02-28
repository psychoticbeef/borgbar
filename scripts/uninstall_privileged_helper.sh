#!/bin/zsh
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo ./scripts/uninstall_privileged_helper.sh"
  exit 1
fi

rm -f /usr/local/libexec/borgbar-helper
echo "Removed /usr/local/libexec/borgbar-helper"
