#!/usr/bin/env bash
# Thin-live rule for coverage-ignored Gateway modules
# (.claude/rules/coverage-ignored-modules.md, physical-abstraction.md).
#
# A Gateway that CI cannot exercise must be too simple to hide a bug: at most
# MAX_LINES per file, no branching (if / guard / switch / for / while), no `var`
# at any access level (`public var` on a box is still state the tests never see).
# The module list is read from codecov.yml so the two never drift.
#
# The same rule holds for the dev-only substitution helpers in a DI target, which are
# coverage-ignored too: each member only assigns one value, so the file is listed below
# (Sources/HostDependencyInjection/DevelopmentSubstitutions.swift).

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

MAX_LINES=50

# Coverage-ignored files outside a Gateway module that follow the thin-live rule.
EXTRA_FILES=(
    Sources/HostDependencyInjection/DevelopmentSubstitutions.swift
)

[ -f codecov.yml ] || { echo "check-live-thin: codecov.yml missing" >&2; exit 1; }

modules=$(sed -n -E 's/^[[:space:]]*-[[:space:]]*"Sources\/([A-Za-z0-9_]+Gateway)\/\*\*".*/\1/p' codecov.yml)

# check_thin <file> <what> — the line cap and the no-branch, no-`var` rule for one file.
check_thin() {
    local file="$1" what="$2" lines line_no text
    lines=$(wc -l < "$file" | tr -d ' ')
    if [ "$lines" -gt "$MAX_LINES" ]; then
        fail "$file:1" "$what file has $lines lines (max $MAX_LINES)"
    fi
    while IFS=: read -r line_no text; do
        [ -n "$line_no" ] || continue
        fail "$file:$line_no" "$what must not branch or hold state: ${text## }"
    done < <(grep -nE '^[[:space:]]*((open|public|package|internal|fileprivate|private)[[:space:]]+)?(if|guard|switch|for|while|var)[[:space:]]' "$file" || true)
}

for module in $modules; do
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        check_thin "$file" "live Gateway"
    done < <(swift_files "Sources/$module")
done

for file in "${EXTRA_FILES[@]}"; do
    if [ -f "$file" ]; then
        check_thin "$file" "dev substitution helper"
    else
        fail "$file:1" "listed in EXTRA_FILES but missing"
    fi
done

finish "check-live-thin"
