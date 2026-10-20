SHELL := /bin/bash
DERIVED_DATA ?= /tmp/tero-p0-build
ARCHIVE ?= /tmp/tero-v001-release.xcarchive
OUTPUT ?= /tmp/tero-v001-distribution
.PHONY: dev check check-db release notarize

dev:
	xcodebuild -project Tero.xcodeproj -scheme 'Tero Dev' -destination 'platform=macOS,arch=arm64' -derivedDataPath '$(DERIVED_DATA)' build
	codesign --verify --strict '$(DERIVED_DATA)/Build/Products/Development/Tero Dev.app'

check:
	node --experimental-strip-types Scripts/test-account-gateway.mjs
	node --experimental-strip-types Scripts/test-ranking-gateway.mjs
	node --experimental-strip-types --test Scripts/test-retired-ranking.mjs

# Requires a disposable local PostgreSQL; never targets Supabase.
check-db:
	python3 Scripts/test-usage-database.py

# Compatibility aliases: distribution always uses the complete signed Sparkle pipeline.
release notarize: publish

# Local distribution: build, notarize once, publish and mark latest without manual steps.
.PHONY: publish release-check
publish:
	python3 Scripts/publish-release.py $(if $(VERSION),--version $(VERSION),)

release-check:
	python3 Scripts/publish-release.py --check
