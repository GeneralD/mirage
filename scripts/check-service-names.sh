#!/usr/bin/env bash
# The Mach service-name triple must agree (docs/ARCHITECTURE.md → Service-name triple).
#
#   1. Sources/Entity/ProductIdentity.swift   — the constant the code uses
#   2. the host app entitlements              — com.apple.security.temporary-exception.mach-lookup.global-name
#   3. the extension entitlements             — com.apple.security.temporary-exception.mach-register.global-name
#
# A mismatch makes bootstrap_look_up fail silently (learned the hard way in decoy).

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

IDENTITY=Sources/Entity/ProductIdentity.swift
LOOKUP_KEY=com.apple.security.temporary-exception.mach-lookup.global-name
REGISTER_KEY=com.apple.security.temporary-exception.mach-register.global-name

[ -f "$IDENTITY" ] || { finish "check-service-names (no ProductIdentity yet)"; exit 0; }

# The constant is declared as: static let machServiceName = "<value>"
constant=$(sed -n -E 's/.*machServiceName[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$IDENTITY" | head -1)
if [ -z "$constant" ]; then
    fail "$IDENTITY:1" "machServiceName constant not found"
    finish "check-service-names"
fi

# entitlement_values <key> — "<file>\t<value>" for every string under <key> in Apps/**/*.entitlements.
entitlement_values() {
    local key="$1" file value
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        while IFS= read -r value; do
            [ -n "$value" ] || continue
            printf '%s\t%s\n' "$file" "$value"
        done < <(/usr/libexec/PlistBuddy -c "Print :$key" "$file" 2>/dev/null \
            | grep -vE '^(Array \{|\})$' | sed -E 's/^[[:space:]]+//')
    done < <(find Apps -name '*.entitlements' -type f 2>/dev/null)
}

lookups=$(entitlement_values "$LOOKUP_KEY")
registers=$(entitlement_values "$REGISTER_KEY")

# Entitlements are generated from project.yml by `make generate`; an absent file is a missing step, not a pass.
[ -n "$lookups" ] || fail "Apps:1" "no host entitlements declare $LOOKUP_KEY for $constant (run make generate)"
[ -n "$registers" ] || fail "Apps:1" "no extension entitlements declare $REGISTER_KEY for $constant (run make generate)"

while IFS=$'\t' read -r file value; do
    [ -n "$file" ] || continue
    if [ "$value" != "$constant" ]; then
        fail "$file:1" "service name '$value' differs from ProductIdentity.machServiceName '$constant'"
    fi
done < <(printf '%s\n%s\n' "$lookups" "$registers")

finish "check-service-names"
