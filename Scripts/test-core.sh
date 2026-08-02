#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CHECK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/no-focus-count-check.XXXXXX")
trap '/bin/rm -rf "$CHECK_DIR"' EXIT

swiftc \
  "$PROJECT_DIR/Sources/NoFocusCount/Models.swift" \
  "$PROJECT_DIR/Checks/FocusPolicyCheck.swift" \
  -o "$CHECK_DIR/FocusPolicyCheck"

"$CHECK_DIR/FocusPolicyCheck"
