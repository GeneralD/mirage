#!/usr/bin/env bash
# The stateful catalog live values have one owner among the tests.
#
# `effectInteractor` and `effectCatalogUseCase` hold a task and a session, so the first scope
# that builds each of them (a process-wide `static let` in `HostRegistrations`) stays theirs for
# the life of the process, and the test bundle is one process whose suites run concurrently. The
# one suite that resolves them under `.live` is `HarnessLiveWiringTests`. Another that resolved
# either would be handed whichever scope built it first, and go red or green by the order the
# suites happen to run in.
#
# This checks the mechanical half: no Tests file but the owner names either key as a key path
# (`\.effectInteractor`, `\.effectCatalogUseCase`: what `@Dependency(...)` takes). An override,
# `$0.effectInteractor = fake`, is no key path and stays free, because it resolves nothing. What
# the grep cannot see, a live `AppRouter()` or `EffectInteractorImpl()` that resolves the key
# through its own `@Dependency`, stays with review (`docs/ARCHITECTURE.md` -> *The effect catalog
# follows the same rule*).

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

OWNER=Tests/DevHarnessTests/HarnessLiveWiringTests.swift

[ -f "$OWNER" ] || fail "$OWNER:1" "file missing: the one suite that resolves the stateful catalog values live"

while IFS=: read -r file line_no text; do
    [ -n "$file" ] || continue
    [ "$file" = "$OWNER" ] && continue
    fail "$file:$line_no" "only HarnessLiveWiringTests resolves effectInteractor and effectCatalogUseCase (they freeze the scope that built them); override them with \$0.<key> = ... instead: ${text## }"
done < <(grep -rnE '\\\.(effectInteractor|effectCatalogUseCase)([^A-Za-z0-9_]|$)' Tests --include='*.swift' || true)

finish "check-live-owner"
