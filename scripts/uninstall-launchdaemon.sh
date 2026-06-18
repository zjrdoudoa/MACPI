#!/bin/sh
set -eu

LABEL="com.local.macpi"
BINARY="/usr/local/sbin/macpi"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo $0" >&2
  exit 1
fi

if [ -f "$PLIST" ]; then
  launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
fi

rm -f "$BINARY"

echo "Uninstalled ${LABEL}"
