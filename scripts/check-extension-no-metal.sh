#!/usr/bin/env bash
# The Camera Extension process never links Metal (docs/ARCHITECTURE.md →
# "Three DI targets"; epic #14, D15).
#
# Walks the package graph from the extension's composition root and its DI
# target and fails when a Metal gateway module, the preview DataSource that
# carries the preview kernel's MSL, or the MetalKit-importing Views target is
# reachable. Reads
# `swift package dump-package`, which evaluates the manifest only — no
# dependency resolution, no build — so it is cheap enough for `make check`.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

if ! command -v jq >/dev/null 2>&1; then
    echo "check-extension-no-metal: jq is required (brew install jq)" >&2
    exit 1
fi

ROOTS="ExtensionApp ExtensionDependencyInjection"
FORBIDDEN="MetalGateway MetalKitPreviewGateway PreviewDataSource Views"

if ! manifest=$(swift package dump-package 2>/dev/null); then
    echo "check-extension-no-metal: swift package dump-package failed" >&2
    exit 1
fi

# has_target <name> — the manifest declares this target.
has_target() {
    jq -e --arg name "$1" '.targets[] | select(.name == $name)' <<< "$manifest" >/dev/null
}

# closure <root> — every target reachable from <root> through target dependencies, one per line.
closure() {
    jq -r --arg root "$1" '
        . as $manifest
        | def deps($n): [ $manifest.targets[] | select(.name == $n) | .dependencies[] | (.byName // .target // empty) | .[0] | select(. != null) ];
          def grow($seen): ([ $seen[] | deps(.) ] | add // [] | unique) - $seen
              | if length == 0 then $seen else grow($seen + .) end;
          grow([$root])[]
    ' <<< "$manifest"
}

for root in $ROOTS; do
    if ! has_target "$root"; then
        fail "Package.swift:1" "target $root is missing; the extension lint has nothing to guard"
        continue
    fi
    reachable=$(closure "$root")
    for module in $FORBIDDEN; do
        if grep -qx "$module" <<< "$reachable"; then
            fail "Package.swift:1" "$root reaches $module; the extension process never links Metal"
        fi
    done
done

finish "check-extension-no-metal"
