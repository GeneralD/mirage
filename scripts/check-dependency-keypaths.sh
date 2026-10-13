#!/usr/bin/env bash
# Key-path allow-list per layer (.claude/rules/architecture-boundaries.md).
#
# The import lint bounds what a module can see; this one bounds what it may resolve. Every
# `Dependency(\.key)` under Sources/ — the `@Dependency` wrapper in any layout, and the
# wrapper's initializer in an `init` — is found through the AST (ast-grep), so comments and
# strings never count, and is checked against the lane of the module that resolves it. A key's
# port kind is the `Sources/Domain/<Kind>/` directory that declares its `DependencyValues`
# member, so a new port needs no entry here: its directory is its kind. A lane may resolve the
# kind of the layer right below it plus Support; the few keys a lane may resolve beyond that
# are listed per key, each with the decision it rests on, and an exception nothing resolves any
# more fails, so the list cannot outlive its reason. Only the plain `\.key` form is understood:
# a key-path chain, `Key.self` or `\DependencyValues.key` fails instead of passing unchecked.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

for tool in sg jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "check-dependency-keypaths: $tool is required (brew install ast-grep jq)" >&2
        exit 1
    fi
done

# A property declared directly in the body of an `extension DependencyValues`, whatever its
# modifiers; `$NAME` is the member's name.
# shellcheck disable=SC2016
MEMBER_RULE='
id: dependency-values-member
language: swift
rule:
  kind: property_declaration
  has:
    field: name
    pattern: $NAME
  inside:
    kind: class_body
    inside:
      kind: class_declaration
      has:
        field: name
        regex: ^DependencyValues$
'

# KEY_TABLE — one "<key> <kind>" line per member under Sources/Domain/<Kind>/, plus the
# swift-dependencies built-ins this codebase treats as Support ports. A member declared at the
# root of Sources/Domain has no kind and fails.
KEY_TABLE=""
while IFS=' ' read -r file key; do
    [ -n "$key" ] || continue
    kind="${file#Sources/Domain/}"
    case "$kind" in
        */*) kind="${kind%%/*}" ;;
        *)
            fail "$file:1" "\\.$key is declared at the root of Sources/Domain; a port lives under Sources/Domain/<Kind>/"
            continue
            ;;
    esac
    KEY_TABLE="$KEY_TABLE$key $kind
"
done < <(sg scan --inline-rules "$MEMBER_RULE" --json=compact Sources/Domain 2>/dev/null \
    | jq -r '.[] | "\(.file) \(.metaVariables.single.NAME.text)"')
KEY_TABLE="${KEY_TABLE}continuousClock Support"

# kind_of_key <key> — the port kind of a key, empty when no Domain subdirectory declares it.
kind_of_key() {
    awk -v key="$1" '$1 == key { print $2; exit }' <<< "$KEY_TABLE"
}

# lane_of <module> — the layer a module belongs to, by name. `None` resolves nothing: Entity,
# Domain, the Gateway and Support lives, and the DI targets have no ports to pull.
lane_of() {
    case "$1" in
        App | DevHarness | ExtensionApp) echo "Entry" ;;
        Views | AppRouter)               echo "View" ;;
        Presenters | *Presenter)         echo "Presenter" ;;
        *Interactor)                     echo "Interactor" ;;
        *UseCase)                        echo "UseCase" ;;
        *Repository)                     echo "Repository" ;;
        *DataSource | *DataStore)        echo "DataSource" ;;
        *)                               echo "None" ;;
    esac
}

# allowed_kinds <lane> — the port kinds a lane may resolve: the layer right below it, and Support.
allowed_kinds() {
    case "$1" in
        Entry)      echo "Interactor Support" ;;
        View)       echo "Presenter Support" ;;
        Presenter)  echo "Interactor Support" ;;
        Interactor) echo "UseCase Support" ;;
        UseCase)    echo "Repository Support" ;;
        Repository) echo "DataSource DataStore Support" ;;
        DataSource) echo "Gateway Support" ;;
        *)          echo "" ;;
    esac
}

# EXCEPTIONS — "<module glob> <key>": a key a module may resolve beyond its lane's kinds, and
# why. An entry no module resolves any more is a violation: remove it with its reason.
#
#   *UseCase    — the frame path runs on the execution context the UseCase owns: no actors on
#                 the frame path (docs/ARCHITECTURE.md → Key Design Decisions).
#   *Repository — off-path work (shader compiles) runs on the work runner; the frame executor
#                 and the scheduler stay with the UseCase and the DataSources (→ Effect
#                 runtime, D14, #36).
#   GPURenderDataSource, PreviewDataSource — the two GPU DataSources resolve their leases
#                 through the pool, which is confined to the frame executor they hop onto
#                 first (→ One effect, one command buffer, D4).
#   ExtensionApp — the extension process's entry point. That process has no GUI, so it has no
#                 Interactor lane (Interactors are Combine pipelines over UseCases for the GUI,
#                 wired by the host's DI only); its DI target wires the relay UseCase directly
#                 (→ the dependency graph, and "The extension's entry point resolves the relay
#                 UseCase" under Key Design Decisions).
EXCEPTIONS='
*UseCase frameExecutor
*UseCase frameScheduler
*UseCase workRunner
*Repository workRunner
GPURenderDataSource surfacePool
PreviewDataSource surfacePool
ExtensionApp extensionRelayUseCase
'
USED_EXCEPTIONS=""

# excepted <module> <key> — 0 when an EXCEPTIONS entry covers the pair, recording it as used.
excepted() {
    local module="$1" key="$2" glob entry_key
    while IFS=' ' read -r glob entry_key; do
        [ -n "$glob" ] || continue
        [ "$entry_key" = "$key" ] || continue
        # The glob is the pattern.
        # shellcheck disable=SC2254
        case "$module" in
            $glob)
                USED_EXCEPTIONS="$USED_EXCEPTIONS$glob $entry_key
"
                return 0
                ;;
        esac
    done <<< "$EXCEPTIONS"
    return 1
}

# resolutions — "<file>\t<line>\t<argument>" for every `Dependency(...)` under Sources/: the
# `@Dependency` wrapper (whatever its layout) and the wrapper's own initializer.
resolutions() {
    local pattern
    # shellcheck disable=SC2016
    for pattern in '@Dependency($ARG)' 'Dependency($ARG)'; do
        sg run --lang swift --pattern "$pattern" --json=compact Sources 2>/dev/null \
            | jq -r '.[] | "\(.file)\t\(.range.start.line + 1)\t\(.metaVariables.single.ARG.text)"'
    done | sort -t "$(printf '\t')" -k1,1 -k2,2n
}

while IFS="$(printf '\t')" read -r file line_no arg; do
    [ -n "$file" ] || continue
    module=$(module_name "$file")
    lane=$(lane_of "$module")
    kinds=$(allowed_kinds "$lane")
    case "$arg" in
        '\.'*) key="${arg#'\.'}" ;;
        *) key="" ;;
    esac
    case "$key" in
        '' | *[!A-Za-z0-9_]*)
            fail "$file:$line_no" "resolve a port as Dependency(\\.key), not Dependency($arg)"
            continue
            ;;
    esac
    kind=$(kind_of_key "$key")
    if [ -z "$kind" ]; then
        fail "$file:$line_no" "\\.$key is not a port declared under Sources/Domain/<Kind>/"
        continue
    fi
    excepted "$module" "$key" && continue
    case " $kinds " in
        *" $kind "*) ;;
        *)
            if [ "$lane" = "None" ]; then
                fail "$file:$line_no" "module $module resolves \\.$key, but a module outside the layer chain (Entity, Domain, Gateway and Support lives, DI targets) resolves nothing"
            else
                fail "$file:$line_no" "module $module may not resolve \\.$key (port kind $kind); the $lane lane resolves: $kinds"
            fi
            ;;
    esac
done < <(resolutions)

while IFS=' ' read -r glob entry_key; do
    [ -n "$glob" ] || continue
    case "$USED_EXCEPTIONS" in
        *"$glob $entry_key
"*) ;;
        *) fail "scripts/check-dependency-keypaths.sh:1" "no module matching $glob resolves \\.$entry_key any more; remove the exception with its reason" ;;
    esac
done <<< "$EXCEPTIONS"

finish "check-dependency-keypaths"
