.PHONY: build test test-gpu lint format check generate clean

# Build only the shipped SPM products: a bare `swift build` also compiles the
# test helper targets (TestSupport, TestDoubles), so a test-only diagnostic on
# the release runner's older toolchain would block the release build.
build:
	swift build --disable-sandbox -c release --product dev-harness

# The main run skips GPU suites; they need a Metal device and their own process.
test:
	swift test --skip GPUSmokeTests

# GPU suites in a separate process, local by default (see .claude/rules/gpu-testing.md).
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
	scripts/check-physical-symbols.sh
	scripts/check-live-thin.sh
	scripts/check-shell-thin.sh
	scripts/check-service-names.sh
	scripts/check-product-name.sh

# The Xcode project, Info.plists and entitlements are gitignored output
# regenerated from project.yml (the one place bundle IDs live). A no-op until
# the shell exists.
generate:
	test -f project.yml && xcodegen generate || echo "generate: no project.yml yet"

clean:
	swift package clean
