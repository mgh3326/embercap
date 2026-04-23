#!/usr/bin/env bash
# Spec §11 acceptance criterion #8: main must contain no write-path code.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
hits=$(cd "$root" && grep -REn 'writeKey|kSMCWriteKey|\.writeKey|selector=6|selector: *6' Sources/ || true)
if [ -n "$hits" ]; then
    echo "FAIL: write-path references found in Sources/:" >&2
    echo "$hits" >&2
    exit 1
fi
echo "ok: no write-path references in Sources/"
