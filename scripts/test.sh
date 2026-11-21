#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vigil-test.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 -strict-concurrency=complete -parse-as-library \
    -module-cache-path "$TEST_DIR/modules" \
    Vigil/Sources/Core/*.swift tests/CoreTests.swift tests/IntroFlowTests.swift -o "$TEST_DIR/t"
"$TEST_DIR/t"
