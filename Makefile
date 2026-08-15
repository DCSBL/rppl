.PHONY: check test-core lint gate install-hooks

export PATH := $(CURDIR)/tools/bin:$(HOME)/Library/Python/3.9/bin:$(PATH)

# Full gate: Core tests + xcodebuild build + analyze (ignores skip cache).
check:
	XCODE_GATE_FULL=1 bash scripts/git-hooks/xcode-gate.sh

test-core:
	cd RpplCore && swift test

lint:
	bash scripts/git-hooks/run-swiftlint.sh

# Same as pre-push: skip unchanged steps; no analyze.
gate:
	bash scripts/git-hooks/xcode-gate.sh

install-hooks:
	pre-commit install
	@echo "Hooks installed. Commit: hygiene/codespell/SwiftLint. Push: xcode-gate when build files change."
