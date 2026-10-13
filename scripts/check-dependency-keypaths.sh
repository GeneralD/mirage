#!/usr/bin/env bash
# Key-path allow-list per layer (.claude/rules/architecture-boundaries.md).
#
# The import lint bounds what a module can see; this one bounds what it may resolve. Every
# resolution under Sources/ — the `@Dependency(...)` attribute in any layout, and the wrapper's
# initializer spelled `Dependency(...)`, `Dependency<T>(...)`, `Dependencies.Dependency(...)`
# or `Dependency.init(...)` — is found through the AST (ast-grep), so comments and strings
# never count, and is checked against the lane of the module that resolves it. An initializer
# reached through inference (`.init(\.key)`) or spelled `Dependency<T>.init(...)` is not seen; a
# `withDependencies` override is an assignment, not a resolution, and is not checked either
# (any other type named `Dependency` would be reported as a non-plain form; none exists). A key's
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

# run_sg <label> <args>... — `sg` with "no match" (exit 1) treated as an empty result. Any other
# failure names the step and returns 1; every caller assigns the result in the main shell and
# exits on it, so a broken ast-grep ends the run instead of passing as green or as a wall of
# misleading violations.
run_sg() {
    local label="$1" out status
    shift
    out=$(sg "$@" 2>/dev/null) && status=0 || status=$?
    if [ "$status" -gt 1 ]; then
        echo "check-dependency-keypaths: ast-grep failed with status $status while $label" >&2
        return 1
    fi
    printf '%s\n' "$out"
}

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
MEMBERS=$(run_sg "listing the DependencyValues members under Sources/Domain" \
    scan --inline-rules "$MEMBER_RULE" --json=compact Sources/Domain) || exit 1
KEY_TABLE=""
while IFS="$(printf '\t')" read -r file key; do
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
done < <(jq -r '.[] | "\(.file)\t\(.metaVariables.single.NAME.text)"' <<< "$MEMBERS")
if [ -z "$KEY_TABLE" ]; then
    echo "check-dependency-keypaths: no DependencyValues member found under Sources/Domain/<Kind>/ (did the ports move, or did ast-grep not run?)" >&2
    exit 1
fi
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
#   *UseCase    — the frame path runs on the execution context the UseCase owns
#                 (docs/ARCHITECTURE.md → Physical Abstraction Table, the "Frame execution
#                 context" and "Frame pacing" rows; → Effect runtime, where the apply's
#                 lifetime starts on the work runner).
#   *Repository — off-path work (shader compiles) runs on the work runner; a Repository does
#                 not reach for the executor or the scheduler (→ Effect runtime, epic #14
#                 D14, the decision of #36).
#   GPURenderDataSource, PreviewDataSource — both resolve their leases through the pool, which
#                 is confined to the frame executor they hop onto first (→ One effect, one
#                 command buffer, epic #14 D4; → Physical Abstraction Table, the "Texture
#                 binding" row: the DataSource resolves SurfaceToken → SurfaceHandle through
#                 the pool first).
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

# exception_keys_for <module> — the keys EXCEPTIONS grants a module, for the violation message.
exception_keys_for() {
    local module="$1" glob entry_key keys=""
    while IFS=' ' read -r glob entry_key; do
        [ -n "$glob" ] || continue
        # shellcheck disable=SC2254
        case "$module" in
            $glob) keys="$keys $entry_key" ;;
        esac
    done <<< "$EXCEPTIONS"
    printf '%s\n' "${keys# }"
}

# RESOLUTIONS — "<file>\t<line>\t<arguments>" for every resolution under Sources/: the
# `@Dependency` attribute (whatever its layout) and the wrapper's initializer in each spelling
# ast-grep can name. The argument list is joined and its whitespace collapsed, so a second
# argument or a layout across lines reaches the check as one readable string. Collected in the
# main shell, so a failing pattern ends the run; sorted on all three fields, so two resolutions
# on one line both survive and only an exact duplicate goes.
RESOLUTIONS=""
# shellcheck disable=SC2016
for pattern in '@Dependency($$$ARGS)' 'Dependency($$$ARGS)' 'Dependency<$T>($$$ARGS)' \
    '$Q.Dependency($$$ARGS)' '$Q.Dependency<$T>($$$ARGS)' 'Dependency.init($$$ARGS)'; do
    matches=$(run_sg "matching $pattern under Sources" run --lang swift --pattern "$pattern" --json=compact Sources) || exit 1
    RESOLUTIONS="$RESOLUTIONS$(jq -r '.[] | "\(.file)\t\(.range.start.line + 1)\t\((.metaVariables.multi.ARGS // []) | map(.text) | join(" ") | gsub("\\s+"; " "))"' <<< "$matches")
"
done
RESOLUTIONS=$(sort -u -t "$(printf '\t')" -k1,1 -k2,2n -k3 <<< "$RESOLUTIONS")

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
                granted=$(exception_keys_for "$module")
                fail "$file:$line_no" "module $module may not resolve \\.$key (port kind $kind); the $lane lane resolves: $kinds${granted:+, plus by exception: $granted}"
            fi
            ;;
    esac
done <<< "$RESOLUTIONS"

while IFS=' ' read -r glob entry_key; do
    [ -n "$glob" ] || continue
    case "$USED_EXCEPTIONS" in
        *"$glob $entry_key
"*) ;;
        *) fail "scripts/check-dependency-keypaths.sh:1" "no module matching $glob resolves \\.$entry_key any more; remove the exception with its reason" ;;
    esac
done <<< "$EXCEPTIONS"

finish "check-dependency-keypaths"
