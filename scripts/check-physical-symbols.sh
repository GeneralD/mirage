#!/usr/bin/env bash
# Physical symbols are forbidden outside Gateway / Support live modules
# (.claude/rules/physical-abstraction.md).
#
# Uses ast-grep (`sg`) so string literals and comments never false-match; the
# only escape hatch is a trailing `// allow-physical: <PortName>` comment, and
# only inside the live module that implements that port.

# shellcheck source=scripts/lib.sh
source "$(dirname "$0")/lib.sh"

for tool in sg jq; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "check-physical-symbols: $tool is required (brew install ast-grep jq)" >&2
        exit 1
    fi
done

# Modules allowed to touch the physical world directly.
LIVE_MODULES="AVFoundationGateway MetalGateway MetalKitPreviewGateway IOSurfaceGateway MachGateway SystemExtensionGateway CMIOExtensionGateway FileSystemGateway FileWatchGateway UserDefaultsGateway WorkspaceGateway DispatchExecutorGateway UnifiedLog HostTime RandomSource AppDirectories"

# ast-grep patterns (Swift). One per line: <pattern>|<label>
# shellcheck disable=SC2016
PATTERNS='
Date()|Date() (wall clock)
Date.now|Date.now (wall clock)
ContinuousClock()|ContinuousClock() (inject \.continuousClock)
SuspendingClock()|SuspendingClock() (inject a clock)
Task.sleep($$$)|Task.sleep (use the injected clock)
DispatchQueue($$$)|DispatchQueue (use FrameExecutor)
DispatchQueue.main|DispatchQueue.main (use FrameExecutor / @MainActor)
DispatchQueue.global($$$)|DispatchQueue.global (use FrameExecutor)
DispatchSource.$METHOD($$$)|DispatchSource (use FileWatchGateway / FrameScheduler)
DispatchSemaphore($$$)|DispatchSemaphore (record into a Collector)
Thread.$METHOD($$$)|Thread (use FrameExecutor)
Task.detached($$$)|Task.detached (structured concurrency on FrameExecutor)
UUID()|UUID() (use RandomSource)
$X.random(in: $$$)|.random(in:) (use RandomSource)
$X.randomElement()|.randomElement() (use RandomSource)
$X.shuffled()|.shuffled() (use RandomSource)
SystemRandomNumberGenerator()|SystemRandomNumberGenerator (use RandomSource)
FileManager.default|FileManager.default (use FileSystemGateway)
ProcessInfo.processInfo|ProcessInfo.processInfo (inject what you need)
Bundle.main|Bundle.main (use BundleInfoProvider)
NotificationCenter.default|NotificationCenter.default (expose events through a Gateway)
setenv($$$)|setenv (inject paths)
getenv($$$)|getenv (inject paths)
print($$$)|print (use DeveloperLog / ErrorLog)
debugPrint($$$)|debugPrint (use DeveloperLog)
NSLog($$$)|NSLog (use DeveloperLog / ErrorLog)
Logger($$$)|os.Logger (use DeveloperLog / ErrorLog)
mach_absolute_time()|mach_absolute_time (use HostTimeProvider)
CFAbsoluteTimeGetCurrent()|CFAbsoluteTimeGetCurrent (use HostTimeProvider)
MTLCreateSystemDefaultDevice()|MTLCreateSystemDefaultDevice (use GPUGateway)
OSAllocatedUnfairLock($$$)|OSAllocatedUnfairLock (no locks above the Gateway)
NSLock()|NSLock (no locks above the Gateway)
'

# Names no code outside the live modules may spell, in any form: a call, `.init`, a static member,
# a type annotation, a type argument, a module-qualified name. One "<identifier>|<label>" per line.
# Matched by the token, not by a call shape: `let d: UserDefaults = .standard` holds the user's
# defaults and spells neither `UserDefaults.standard` nor `UserDefaults(...)`. Comments and string
# literals are not code and never match.
FORBIDDEN_IDENTIFIERS='
UserDefaults|UserDefaults (use KeyValueStoreGateway)
'

is_live_module() {
    case " $LIVE_MODULES " in *" $1 "*) return 0 ;; esac
    return 1
}

# match_lines <pattern> <file> — 1-based line numbers of every AST match.
match_lines() {
    sg run --lang swift --pattern "$1" --json=compact "$2" 2>/dev/null \
        | jq -r '.[].range.start.line + 1' | sort -un
}

# report <file> <line> <label> — one violation; a line that carries an allow-physical comment
# gets the message for a comment in the wrong place.
report() {
    local file="$1" line_no="$2" label="$3"
    if sed -n "${line_no}p" "$file" | grep -qE '//[[:space:]]*allow-physical:[[:space:]]*[A-Za-z]+'; then
        fail "$file:$line_no" "allow-physical is valid only inside the live module that implements the port"
    else
        fail "$file:$line_no" "physical symbol $label"
    fi
}

check_file() {
    local file="$1" module="$2"
    while IFS='|' read -r pattern label; do
        [ -n "$pattern" ] || continue
        while IFS= read -r line_no; do
            [ -n "$line_no" ] || continue
            report "$file" "$line_no" "$label"
        done < <(match_lines "$pattern" "$file")
    done <<< "$PATTERNS"
}

# check_identifier <identifier> <label> — every code occurrence of the identifier under Sources,
# outside the live modules: a type name or an expression name (`type_identifier` /
# `simple_identifier`), whole-token match, so `UserDefaultsGateway` is not `UserDefaults`. One scan
# over all of Sources, collected in the main shell: a failing `sg` ends the run instead of passing
# as green, because a rule that silently matches nothing is no check at all. A scan with matches
# still exits 0 (the rule carries no severity), so any nonzero status is a failure.
check_identifier() {
    local identifier="$1" label="$2" rule matches status file line_no
    rule=$(jq -nc --arg id "$identifier" \
        '{id: "forbidden-identifier", language: "swift", rule: {any: [{kind: "type_identifier"}, {kind: "simple_identifier"}], regex: ("^" + $id + "$")}}')
    matches=$(sg scan --inline-rules "$rule" --json=compact Sources 2>/dev/null) && status=0 || status=$?
    if [ "$status" -ne 0 ]; then
        echo "check-physical-symbols: ast-grep failed with status $status while scanning for $identifier" >&2
        exit 1
    fi
    while IFS=$'\t' read -r file line_no; do
        [ -n "$file" ] || continue
        is_live_module "$(module_name "$file")" && continue
        report "$file" "$line_no" "$label"
    done < <(jq -r '[.[] | [.file, (.range.start.line + 1)]] | unique | sort_by(.[0], .[1])[] | @tsv' <<< "$matches")
}

while IFS= read -r file; do
    [ -n "$file" ] || continue
    module=$(module_name "$file")
    is_live_module "$module" && continue
    check_file "$file" "$module"
done < <(swift_files Sources)

while IFS='|' read -r identifier label; do
    [ -n "$identifier" ] || continue
    check_identifier "$identifier" "$label"
done <<< "$FORBIDDEN_IDENTIFIERS"

finish "check-physical-symbols"
