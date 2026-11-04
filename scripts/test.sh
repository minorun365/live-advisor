#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="${TMPDIR:-/tmp}/live-advisor-policy-test"
MODULE_CACHE="${PROJECT_DIR}/.build/test-module-cache"
SOURCES="${PROJECT_DIR}/Sources/LiveAdvisor"

mkdir -p "${MODULE_CACHE}"

swiftc \
    -parse-as-library \
    -module-cache-path "${MODULE_CACHE}" \
    "${SOURCES}/Models.swift" \
    "${SOURCES}/EventTailer.swift" \
    "${SOURCES}/AdvisorPolicy.swift" \
    "${SOURCES}/AppConfig.swift" \
    "${PROJECT_DIR}/Tests/AdvisorPolicySelfTest.swift" \
    -o "${TEST_BINARY}"

"${TEST_BINARY}"
