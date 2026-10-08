#!/usr/bin/env bash
# The product name lives in exactly three files (docs/ARCHITECTURE.md → Rename-safe naming):
#   README.md, project.yml, Sources/Entity/ProductIdentity.swift
# Anywhere else under Sources/, Tests/, Apps/ or in a file name is a violation —
# the name may change, and a rename must stay a three-file edit. Info.plist and
# entitlements necessarily carry bundle IDs, so xcodegen generates them from
# project.yml (gitignored) and they are not scanned here.
#
# The name is read from project.yml (`name:`); until the Xcode shell exists the
# check falls back to the repository directory name.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

name=$(product_name)
[ -n "$name" ] || name=$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")
name_lc=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

ALLOWED="README.md project.yml Sources/Entity/ProductIdentity.swift"

is_allowed() {
    case " $ALLOWED " in *" $1 "*) return 0 ;; esac
    return 1
}

# Path components (module, directory, file names) must never carry the product name.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    is_allowed "$path" && continue
    base=$(basename "$path" | tr '[:upper:]' '[:lower:]')
    case "$base" in
        *"$name_lc"*) fail "$path:1" "file or directory name contains the product name" ;;
    esac
done < <(find Sources Tests Apps -mindepth 1 2>/dev/null)

# Contents: identifiers, strings and comments in Swift and Metal sources.
while IFS= read -r path; do
    [ -n "$path" ] || continue
    is_allowed "$path" && continue
    while IFS=: read -r line_no text; do
        [ -n "$line_no" ] || continue
        fail "$path:$line_no" "product name appears outside the three allowed files: ${text## }"
    done < <(grep -niE "(^|[^A-Za-z0-9])${name_lc}([^A-Za-z0-9]|$)" "$path" || true)
done < <(find Sources Tests Apps -type f \( -name '*.swift' -o -name '*.metal' \) 2>/dev/null)

finish "check-product-name"
