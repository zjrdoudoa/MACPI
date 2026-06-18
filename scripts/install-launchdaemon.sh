#!/bin/sh
set -eu

LABEL="com.local.macpi"
BINARY="/usr/local/sbin/macpi"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
STAGED_BINARY="${BINARY}.staged"
STAGED_PLIST="${PLIST}.staged.$$"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cleanup() {
  rm -f "$STAGED_BINARY" "$STAGED_PLIST"
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo: sudo $0" >&2
  exit 1
fi

cd "$ROOT_DIR"
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  sudo -u "$SUDO_USER" swift build -c release
else
  swift build -c release
fi

if [ -f "$PLIST" ] || launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout system "$PLIST" >/dev/null 2>&1 || true
fi
if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "Service ${LABEL} is still running after bootout; aborting install" >&2
  exit 1
fi

install -d -m 0755 /usr/local/sbin
install -m 0755 ".build/release/macpi" "$STAGED_BINARY"
chown root:wheel "$STAGED_BINARY"
chmod 0755 "$STAGED_BINARY"

cat > "$STAGED_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${BINARY}</string>
    <string>daemon</string>
    <string>--interval</string>
    <string>15</string>
    <string>--reapply-interval</string>
    <string>60</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/var/log/macpi.log</string>
  <key>StandardErrorPath</key>
  <string>/var/log/macpi.err</string>
</dict>
</plist>
PLIST

chown root:wheel "$STAGED_PLIST"
chmod 0644 "$STAGED_PLIST"
plutil -lint "$STAGED_PLIST" >/dev/null
mv -f "$STAGED_BINARY" "$BINARY"
mv -f "$STAGED_PLIST" "$PLIST"
launchctl bootstrap system "$PLIST"
launchctl kickstart -k "system/${LABEL}"

echo "Installed ${LABEL}"
echo "Logs: /var/log/macpi.log /var/log/macpi.err"
