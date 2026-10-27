.PHONY: build build-dev-harness test test-gpu lint format check generate clean

# Build the shipped SPM products, one invocation each: `--product` takes a
# single value and a repeated flag is last-one-wins, so one command would
# silently skip the host app.
build:
	swift build --disable-sandbox -c release --product App
	swift build --disable-sandbox -c release --product ExtensionApp

# The development harness, in the configuration `swift run dev-harness` uses.
# Not shipped. `make build` compiles it as well (SwiftPM ignores `--product` for
# the automatic App / ExtensionApp products and builds every non-test target),
# but in release, not in the configuration `swift run` uses.
# SwiftPM does not track Tools/DevHarness/Info.plist (only a linker flag names
# it), so an edit to the plist alone would not relink: the binary goes first.
build-dev-harness:
	rm -f "$$(swift build --show-bin-path)/dev-harness"
	swift build --product dev-harness

# The main run skips GPU suites; they need a Metal device and their own process.
test:
	swift test --skip GPUSmokeTests

# GPU suites in their own process, never in the coverage run; CI runs this as the
# `test-gpu` job on a runner with a Metal device (.claude/rules/gpu-testing.md).
test-gpu:
	swift test --filter GPUSmokeTests

lint:
	swift format lint --strict --recursive Sources/ Tests/ Apps/

format:
	swift format --in-place --recursive Sources/ Tests/ Apps/

# Mechanical guards the compiler cannot express. Each script is small and
# documented in .claude/rules/{architecture-boundaries,physical-abstraction}.md.
check:
	scripts/check-imports.sh
	scripts/check-dependency-keypaths.sh
	scripts/check-physical-symbols.sh
	scripts/check-live-thin.sh
	scripts/check-shell-thin.sh
	scripts/check-service-names.sh
	scripts/check-product-name.sh
	scripts/check-extension-no-metal.sh
	scripts/check-dev-substitutions.sh
	scripts/check-live-owner.sh

# The Xcode project, Info.plists and entitlements are gitignored output
# regenerated from project.yml (the one place bundle IDs live). A no-op until
# the shell exists.
generate:
	test -f project.yml && xcodegen generate || echo "generate: no project.yml yet"

clean:
	swift package clean
