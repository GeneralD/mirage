#!/usr/bin/env bash
# Import allow-list per layer (.claude/rules/architecture-boundaries.md).
#
# Every module under Sources/ falls into one lane by name; each lane may import
# only the modules listed for it. OS frameworks are importable only in Gateway
# modules (the one framework each wraps) and the View/Router/App lane.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

COMMON="Foundation Combine Dependencies Domain Entity"
UI_FRAMEWORKS="AppKit SwiftUI MetalKit Presenters"

# Gateway / Support live modules and the one OS framework (or family) each may import.
gateway_allow() {
    case "$1" in
        AVFoundationGateway)      echo "AVFoundation CoreMedia CoreVideo" ;;
        MetalGateway)             echo "Metal CoreVideo IOSurface" ;;
        MetalKitPreviewGateway)   echo "Metal MetalKit AppKit" ;;
        IOSurfaceGateway)         echo "IOSurface CoreVideo Darwin" ;;
        MachGateway)              echo "Darwin IOSurface" ;;
        SystemExtensionGateway)   echo "SystemExtensions" ;;
        CMIOExtensionGateway)     echo "CoreMediaIO CoreMedia CoreVideo IOSurface" ;;
        FileSystemGateway)        echo "" ;;
        FileWatchGateway)         echo "Dispatch System" ;;
        UserDefaultsGateway)      echo "" ;;
        WorkspaceGateway)         echo "AppKit" ;;
        DispatchExecutorGateway)  echo "Dispatch CoreVideo QuartzCore" ;;
        UnifiedLog)               echo "os" ;;
        HostTime)                 echo "Darwin" ;;
        RandomSource)             echo "" ;;
        AppDirectories)           echo "" ;;
        *)                        return 1 ;;
    esac
}

allowed_for() {
    local module="$1"
    case "$module" in
        Entity)                                  echo "Foundation" ;;
        Domain)                                  echo "Foundation Combine Dependencies Entity" ;;
        *DependencyInjection)                    echo "*" ;;
        Views|AppRouter)              echo "$COMMON $UI_FRAMEWORKS" ;;
        App)                          echo "$COMMON $UI_FRAMEWORKS HostDependencyInjection AppRouter Views" ;;
        DevHarness)                   echo "$COMMON AppKit SwiftUI Views HostDependencyInjection" ;;
        ExtensionApp)                 echo "$COMMON $UI_FRAMEWORKS ExtensionDependencyInjection" ;;
        Presenters)                   echo "$COMMON" ;;  # display state: no AppKit / SwiftUI / MetalKit
        *)
            if gw=$(gateway_allow "$module"); then
                echo "$COMMON $gw"
            else
                echo "$COMMON"
            fi
            ;;
    esac
}

while IFS= read -r file; do
    [ -n "$file" ] || continue
    module=$(module_name "$file")
    allowed=$(allowed_for "$module")
    [ "$allowed" = "*" ] && continue
    while IFS=: read -r line_no imported; do
        [ -n "$imported" ] || continue
        case " $allowed " in
            *" $imported "*) ;;
            *) fail "$file:$line_no" "module $module may not import $imported" ;;
        esac
    done < <(grep -nE '^[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+' "$file" \
        | sed -E 's/^([0-9]+):[[:space:]]*(@_exported[[:space:]]+)?import[[:space:]]+((class|struct|enum|protocol|func|var|let|typealias)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*).*/\1:\5/')
done < <(swift_files Sources)

finish "check-imports"
