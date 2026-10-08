#!/usr/bin/env bash
# Shells stay thin (.claude/CLAUDE.md → Non-negotiables).
#
# Apps/** may contain only main.swift and assets (plus the Info.plist and
# entitlements xcodegen generates there); the one Swift file per shell is a
# handful of lines that calls into an SPM product.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

MAX_MAIN_LINES=30

[ -d Apps ] || { finish "check-shell-thin"; exit 0; }

while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in
        */main.swift|*/Info.plist|*.entitlements|*.xcassets/*|*.icns|*.png|*.strings|*.lproj/*) ;;
        *) fail "$file:1" "shells may hold only main.swift, Info.plist, entitlements and assets" ;;
    esac
done < <(find Apps -type f ! -name '.DS_Store')

while IFS= read -r file; do
    [ -n "$file" ] || continue
    lines=$(grep -cvE '^[[:space:]]*(//.*)?$' "$file" || true)
    if [ "$lines" -gt "$MAX_MAIN_LINES" ]; then
        fail "$file:1" "shell main.swift has $lines non-comment lines (max $MAX_MAIN_LINES) — move logic into an SPM target"
    fi
done < <(find Apps -name 'main.swift' -type f)

finish "check-shell-thin"
