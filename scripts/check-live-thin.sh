#!/usr/bin/env bash
# Thin-live rule for coverage-ignored Gateway modules
# (.claude/rules/coverage-ignored-modules.md, physical-abstraction.md).
#
# A Gateway that CI cannot exercise must be too simple to hide a bug: at most
# MAX_LINES per file, no branching (if / guard / switch / for / while), no `var`
# (a `private` / `fileprivate` / `internal` prefix does not hide one; a
# protocol-required `public var` is the one documented exception).
# The module list is read from codecov.yml so the two never drift.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

MAX_LINES=50

[ -f codecov.yml ] || { echo "check-live-thin: codecov.yml missing" >&2; exit 1; }

modules=$(sed -n -E 's/^[[:space:]]*-[[:space:]]*"Sources\/([A-Za-z0-9_]+Gateway)\/\*\*".*/\1/p' codecov.yml)

for module in $modules; do
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        lines=$(wc -l < "$file" | tr -d ' ')
        if [ "$lines" -gt "$MAX_LINES" ]; then
            fail "$file:1" "live Gateway file has $lines lines (max $MAX_LINES)"
        fi
        while IFS=: read -r line_no text; do
            [ -n "$line_no" ] || continue
            fail "$file:$line_no" "live Gateway must not branch or hold state: ${text## }"
        done < <(grep -nE '^[[:space:]]*((private|fileprivate|internal)[[:space:]]+)?(if|guard|switch|for|while|var)[[:space:]]' "$file" || true)
    done < <(swift_files "Sources/$module")
done

finish "check-live-thin"
