#!/usr/bin/env bash
# Dev-only substitutions stay in the dev harness.
#
# `DiscardingVirtualCameraSink` accepts every frame and sends it nowhere; it exists for
# `swift run dev-harness`, which has no extension to send to. Shipped code must never
# resolve it, and the harness must keep applying it. Two rules:
#
#   1. `DiscardingVirtualCameraSink` and `useDiscardingVirtualCameraSink` are named only by
#      the harness's session, the DI helper that applies it, and the type's own module. A
#      reference anywhere else (a live registration, an entry point of the app) fails.
#   2. The harness applies it through `HarnessSession.live()` and nothing else constructs the
#      session: `HarnessSession.swift` calls the helper, and `HarnessAppDelegate.swift` uses
#      `HarnessSession.live()` and never `HarnessSession()`.
#
# That `live()` really reaches the pipeline is `HarnessLiveWiringTests`' to prove; this
# keeps the pieces it depends on from being moved out from under it.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

SUBSTITUTION=Sources/HostDependencyInjection/DevelopmentSubstitutions.swift
SESSION=Sources/DevHarness/HarnessSession.swift
DELEGATE=Sources/DevHarness/HarnessAppDelegate.swift
SINK_MODULE=Sources/VirtualCameraRepository

for file in "$SUBSTITUTION" "$SESSION" "$DELEGATE"; do
    [ -f "$file" ] || fail "$file:1" "file missing: the dev harness substitution is wired through it"
done

# Rule 1.
while IFS=: read -r file line_no text; do
    [ -n "$file" ] || continue
    case "$file" in
        "$SUBSTITUTION" | "$SESSION" | "$SINK_MODULE"/*) ;;
        *) fail "$file:$line_no" "dev-only sink referenced outside the harness: ${text## }" ;;
    esac
done < <(grep -rnE 'DiscardingVirtualCameraSink|useDiscardingVirtualCameraSink' Sources || true)

# Rule 2.
if [ -f "$SESSION" ] && ! grep -qE '\.useDiscardingVirtualCameraSink\(\)' "$SESSION"; then
    fail "$SESSION:1" "HarnessSession.live() must apply useDiscardingVirtualCameraSink()"
fi
if [ -f "$DELEGATE" ]; then
    grep -qE 'HarnessSession\.live\(\)' "$DELEGATE" || fail "$DELEGATE:1" "the app delegate must build its session with HarnessSession.live()"
    while IFS=: read -r line_no text; do
        [ -n "$line_no" ] || continue
        fail "$DELEGATE:$line_no" "the session is built by HarnessSession.live(), not directly: ${text## }"
    done < <(grep -nE 'HarnessSession\(\)' "$DELEGATE" || true)
fi

finish "check-dev-substitutions"
