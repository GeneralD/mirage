#!/usr/bin/env bash
# Key-path allow-list per layer (.claude/rules/architecture-boundaries.md).
#
# The import lint bounds what a module can see; this one bounds what it may resolve. Every
# `@Dependency(\.key)` under Sources/ is checked against the lane of the module that resolves
# it. A key's port kind is the `Sources/Domain/<Kind>/` directory that declares its
# `DependencyValues` member, so a new port needs no entry here: its directory is its kind. A
# lane may resolve the kind of the layer right below it plus Support; the few keys a lane may
# resolve beyond that are listed per key, each with the decision it rests on.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

# key_table — one "<key> <kind>" line per `var <key>` inside an `extension DependencyValues`
# under Sources/Domain/<Kind>/, plus the swift-dependencies built-ins this codebase treats as
# Support ports.
key_table() {
    local file kind
    while IFS= read -r file; do
        kind="${file#Sources/Domain/}"
        kind="${kind%%/*}"
        awk -v kind="$kind" '
            /^extension DependencyValues/ { inside = 1; next }
            inside && /^}/ { inside = 0; next }
            inside && /^[[:space:]]*(public[[:space:]]+)?var[[:space:]]+[A-Za-z_]/ {
                name = $0
                sub(/^[[:space:]]*(public[[:space:]]+)?var[[:space:]]+/, "", name)
                sub(/[^A-Za-z0-9_].*$/, "", name)
                print name, kind
            }' "$file"
    done < <(find Sources/Domain -mindepth 2 -name '*.swift' -type f | sort)
    echo "continuousClock Support"
}

KEY_TABLE=$(key_table)

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
        Presenters)                      echo "Presenter" ;;
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
        Repository) echo "DataSource Support" ;;
        DataSource) echo "Gateway Support" ;;
        *)          echo "" ;;
    esac
}

# allowed_keys <module> — keys a module may resolve beyond its lane's kinds, and why.
allowed_keys() {
    case "$1" in
        # The frame path runs on the execution context the UseCase owns: no actors on the
        # frame path (docs/ARCHITECTURE.md → Key Design Decisions).
        *UseCase) echo "frameExecutor frameScheduler workRunner" ;;
        # Off-path work (shader compiles) runs on the work runner; the frame executor and the
        # scheduler stay with the UseCase and the DataSources (→ Effect runtime, D14, #36).
        *Repository) echo "workRunner" ;;
        # The two GPU DataSources resolve their leases through the pool, which is confined to
        # the frame executor they hop onto first (→ One effect, one command buffer, D4).
        GPURenderDataSource | PreviewDataSource) echo "surfacePool" ;;
        # The extension has no Interactor yet; `ExtensionInteractor` arrives with MVP-B (→ the
        # legend under the Layer Summary), and this exception leaves with it.
        ExtensionApp) echo "extensionRelayUseCase" ;;
        *) echo "" ;;
    esac
}

while IFS= read -r file; do
    [ -n "$file" ] || continue
    module=$(module_name "$file")
    lane=$(lane_of "$module")
    kinds=$(allowed_kinds "$lane")
    keys=$(allowed_keys "$module")
    while IFS=: read -r line_no key; do
        [ -n "$key" ] || continue
        case " $keys " in
            *" $key "*) continue ;;
        esac
        kind=$(kind_of_key "$key")
        if [ -z "$kind" ]; then
            fail "$file:$line_no" "\\.$key is not a port declared under Sources/Domain/<Kind>/"
            continue
        fi
        case " $kinds " in
            *" $kind "*) ;;
            *) fail "$file:$line_no" "module $module ($lane) may not resolve \\.$key, a $kind port; the lane resolves: ${kinds:-nothing}" ;;
        esac
    done < <(grep -noE 'Dependency\(\\\.[A-Za-z_][A-Za-z0-9_]*\)' "$file" \
        | sed -E 's/^([0-9]+):Dependency\(\\\.([A-Za-z0-9_]+)\)/\1:\2/')
done < <(swift_files Sources)

finish "check-dependency-keypaths"
