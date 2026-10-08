#!/usr/bin/env bash
# Shared helpers for the `make check` scripts. Source it; do not execute it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

fail_count=0

# fail <file>:<line> <message>
fail() {
    printf '%s: %s\n' "$1" "$2" >&2
    fail_count=$((fail_count + 1))
}

# finish <check name> — exit 1 if anything failed, otherwise print one OK line.
finish() {
    if [ "$fail_count" -gt 0 ]; then
        printf '%s: %d violation(s)\n' "$1" "$fail_count" >&2
        exit 1
    fi
    printf '%s: OK\n' "$1"
}

# swift_files <dir>... — every .swift file under the given directories that exist.
swift_files() {
    local dir
    for dir in "$@"; do
        [ -d "$dir" ] && find "$dir" -name '*.swift' -type f
    done
    return 0
}

# module_name <path under Sources/> — the first path component after Sources/.
module_name() {
    local rel="${1#Sources/}"
    printf '%s\n' "${rel%%/*}"
}

# product_name — the `name:` key of project.yml, empty when the shell does not exist yet.
product_name() {
    [ -f project.yml ] || return 0
    sed -n -E 's/^name:[[:space:]]*"?([^"[:space:]]+)"?.*/\1/p' project.yml | head -1
}
