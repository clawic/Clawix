#!/usr/bin/env bash
# Run from a macOS host with Swift toolchain installed. Regenerates the
# canonical Swift-owned Bridge V1 fixture corpus and mirrors it into
# Clawix.Tests/Fixtures/ for legacy review.
#
# Usage:
#   bash clawix/windows/scripts/dump-fixtures.sh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGES_DIR="$(cd "$ROOT/../packages" && pwd)"
CANONICAL_OUT="$PACKAGES_DIR/ClawixCore/Fixtures/BridgeV1"
FIXTURES_OUT="$ROOT/Clawix.Tests/Fixtures"

mkdir -p "$FIXTURES_OUT"

if ! command -v swift >/dev/null 2>&1; then
    echo "swift CLI not found; install Xcode CLT first." >&2
    exit 2
fi

# Build and run the canonical bridge fixture exporter from ClawixCore.
pushd "$PACKAGES_DIR/ClawixCore" >/dev/null
swift run BridgeFixtureExporter "$CANONICAL_OUT"
popd >/dev/null

find "$FIXTURES_OUT" -maxdepth 1 -name '*.json' -delete
find "$CANONICAL_OUT" -maxdepth 1 -name '*.json' ! -name 'manifest.json' -exec cp {} "$FIXTURES_OUT" \;

echo "Canonical fixtures landed in $CANONICAL_OUT"
echo "Legacy mirror refreshed in $FIXTURES_OUT"
ls "$FIXTURES_OUT" | head -20
