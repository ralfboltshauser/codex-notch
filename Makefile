SHELL := /bin/sh

.PHONY: check-linux test-linux compile-python check-shell validate-changelog test-macos build-macos

check-linux: test-linux compile-python check-shell validate-changelog

test-linux:
	python3 -m unittest discover -s apps/linux/tests -v

compile-python:
	python3 -m py_compile \
		apps/linux/codex_notch_remote.py \
		apps/linux/codex_notch_live.py

check-shell:
	@for script in scripts/*.sh; do sh -n "$$script"; done

validate-changelog:
	python3 scripts/changelog.py validate

test-macos:
	swift test

build-macos:
	./scripts/build-macos-app.sh
