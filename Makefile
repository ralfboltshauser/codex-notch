SHELL := /bin/sh
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
MACOS_PACKAGE := $(REPO_ROOT)/apps/macos
SWIFT_SCRATCH := $(REPO_ROOT)/.build

.PHONY: check-linux test-linux test-scripts compile-python check-shell \
	validate-changelog test-macos build-macos

check-linux: test-linux test-scripts compile-python check-shell validate-changelog

test-linux:
	python3 -m unittest discover -s apps/linux/tests -v

test-scripts:
	python3 -m unittest discover -s scripts/tests -v

compile-python:
	python3 -m py_compile \
		apps/linux/codex_notch_remote.py \
		apps/linux/codex_notch_live.py \
		scripts/changelog.py

check-shell:
	@for script in scripts/*.sh; do sh -n "$$script"; done

validate-changelog:
	python3 scripts/changelog.py validate

test-macos:
	swift test --package-path "$(MACOS_PACKAGE)" \
		--scratch-path "$(SWIFT_SCRATCH)"

build-macos:
	./scripts/build-macos-app.sh
