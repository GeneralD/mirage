#!/usr/bin/env bash
# The Mach service-name triple must agree (docs/ARCHITECTURE.md → Service-name triple).
#
#   1. Sources/Entity/ProductIdentity.swift   — the constant the code uses
#   2. the host app entitlements              — com.apple.security.temporary-exception.mach-lookup.global-name
#   3. the extension entitlements             — com.apple.security.temporary-exception.mach-register.global-name
#
# The entitlements are declared in project.yml and generated into gitignored
# files by `make generate`, so project.yml is what a clean checkout is checked
# against; generated files, when present, are checked as well so a stale
# `make generate` cannot hide a mismatch either.
#
# A mismatch makes bootstrap_look_up fail silently (learned the hard way in decoy).

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

IDENTITY=Sources/Entity/ProductIdentity.swift
SPEC=project.yml
LOOKUP_KEY=com.apple.security.temporary-exception.mach-lookup.global-name
REGISTER_KEY=com.apple.security.temporary-exception.mach-register.global-name

[ -f "$IDENTITY" ] || { finish "check-service-names (no ProductIdentity yet)"; exit 0; }

# The constant is declared as: static let machServiceName = "<value>"
constant=$(sed -n -E 's/.*machServiceName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$IDENTITY" | head -1)
if [ -z "$constant" ]; then
    fail "$IDENTITY:1" "machServiceName constant not found"
    finish "check-service-names"
fi

# spec_values <key> — "<file>:<line>\t<value>" for every list item under <key> in project.yml.
spec_values() {
    local key="$1"
    [ -f "$SPEC" ] || return 0
    awk -v key="$key" -v file="$SPEC" '
        $0 ~ "^[[:space:]]*" key ":[[:space:]]*$" { collecting = 1; next }
        collecting && /^[[:space:]]*-[[:space:]]*/ {
            value = $0
            sub(/^[[:space:]]*-[[:space:]]*/, "", value)
            sub(/[[:space:]]*$/, "", value)
            printf "%s:%d\t%s\n", file, NR, value
            next
        }
        collecting { collecting = 0 }
    ' "$SPEC"
}

# entitlement_values <key> — "<file>:1\t<value>" for every string under <key> in Apps/**/*.entitlements.
entitlement_values() {
    local key="$1" file value
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        while IFS= read -r value; do
            [ -n "$value" ] || continue
            printf '%s:1\t%s\n' "$file" "$value"
        done < <(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null \
            | grep -vE '^(Array \{|\})$' | sed -E 's/^[[:space:]]+//')
    done < <(find Apps -name '*.entitlements' -type f 2>/dev/null)
}

lookups=$(spec_values "$LOOKUP_KEY")
registers=$(spec_values "$REGISTER_KEY")

[ -n "$lookups" ] || fail "$SPEC:1" "no target declares $LOOKUP_KEY for $constant"
[ -n "$registers" ] || fail "$SPEC:1" "no target declares $REGISTER_KEY for $constant"

while IFS=$'\t' read -r location value; do
    [ -n "$location" ] || continue
    if [ "$value" != "$constant" ]; then
        fail "$location" "service name '$value' differs from ProductIdentity.machServiceName '$constant'"
    fi
done < <(printf '%s\n%s\n%s\n%s\n' "$lookups" "$registers" "$(entitlement_values "$LOOKUP_KEY")" "$(entitlement_values "$REGISTER_KEY")")

finish "check-service-names"
