#!/bin/sh
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${MACPI_PACKAGE_DIR:-$ROOT_DIR/dist}"
VERSION="${MACPI_VERSION:-dev}"
ARCHIVE="$OUT_DIR/MACPI-source-${VERSION}.zip"

cd "$ROOT_DIR"
mkdir -p "$OUT_DIR"
rm -f "$ARCHIVE"

INCLUDE="Package.swift README.md .gitignore assets Sources Tests scripts"
if [ -d ".github" ]; then
  INCLUDE="$INCLUDE .github"
fi
if [ -f "LICENSE" ]; then
  INCLUDE="$INCLUDE LICENSE"
fi

/usr/bin/zip -r "$ARCHIVE" $INCLUDE \
  -x '*.DS_Store' \
  -x '*/.DS_Store' \
  -x '._*' \
  -x '*/._*' \
  -x '__MACOSX/*' \
  -x '.git/*' \
  -x '.build/*' \
  -x '.swiftpm/*' \
  -x 'dist/*'

echo "Built $ARCHIVE"
