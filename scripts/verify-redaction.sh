#!/usr/bin/env bash
# Phase 1 redaction verifier for embercap charge-limit research.
# See charter §4.5 at
#   docs/superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md
#
# Usage:
#   bash scripts/verify-redaction.sh \
#        <raw_status> <raw_probe> <raw_diag> <raw_pmset> <raw_ioreg> \
#        <redacted_dir>
#
# Env overrides (for fixture testing):
#   VERIFY_USER      — username to treat as a secret
#   VERIFY_HOSTNAME  — hostname to treat as a secret
#
# Emits a summary block on stdout suitable for pasting into the Phase 1
# report. Exits non-zero on any leak or missing preservation marker.
set -uo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: $0 <raw_status> <raw_probe> <raw_diag> <raw_pmset> <raw_ioreg> <redacted_dir>" >&2
  exit 2
fi

RAW_STATUS="$1"
RAW_PROBE="$2"
RAW_DIAG="$3"
RAW_PMSET="$4"
RAW_IOREG="$5"
RED_DIR="$6"

LIVE_USER="${VERIFY_USER:-${USER:-unknown}}"
if [ -n "${VERIFY_HOSTNAME:-}" ]; then
  LIVE_HOST="$VERIFY_HOSTNAME"
else
  LIVE_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
fi

extract_first() {
  # extract_first <regex_for_value> <file>
  # Prints the first captured value of the first match, or nothing.
  grep -oE "$1" "$2" 2>/dev/null | head -n1 | sed -E "s/$1/\\1/" 2>/dev/null || true
}

# Collect secrets from raw inputs.
SECRETS=()

# battery.serial from diag.json: "serial": "..."
val=$(grep -oE '"serial"[[:space:]]*:[[:space:]]*"[^"]+"' "$RAW_DIAG" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
[ -n "${val:-}" ] && SECRETS+=("$val")

# Hostname token from diag.json kernel string: "kernel": "Darwin <host> ..."
val=$(grep -oE '"kernel"[[:space:]]*:[[:space:]]*"Darwin [^[:space:]\\]+' "$RAW_DIAG" | head -n1 | sed -E 's/.*"Darwin ([^[:space:]\\]+).*/\1/')
[ -n "${val:-}" ] && SECRETS+=("$val")

# BatterySerialNumber from ioreg: "BatterySerialNumber" = "..."
val=$(grep -oE '"BatterySerialNumber"[[:space:]]*=[[:space:]]*"[^"]+"' "$RAW_IOREG" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
[ -n "${val:-}" ] && SECRETS+=("$val")

# IOPlatformUUID from ioreg (if present)
val=$(grep -oE '"IOPlatformUUID"[[:space:]]*=[[:space:]]*"[^"]+"' "$RAW_IOREG" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
[ -n "${val:-}" ] && SECRETS+=("$val")

# IOPlatformSerialNumber from ioreg (if present)
val=$(grep -oE '"IOPlatformSerialNumber"[[:space:]]*=[[:space:]]*"[^"]+"' "$RAW_IOREG" | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')
[ -n "${val:-}" ] && SECRETS+=("$val")

# Live user + home path.
SECRETS+=("$LIVE_USER")
SECRETS+=("/Users/$LIVE_USER")

# Live hostname (short and long form).
SECRETS+=("$LIVE_HOST")

# Absence check.
leak_count=0
echo "Verify-redaction summary"
echo "------------------------"
echo "Redacted dir: $RED_DIR"
echo "Secrets searched: ${#SECRETS[@]}"
for secret in "${SECRETS[@]}"; do
  [ -z "$secret" ] && continue
  hits=$(grep -r -c -F "$secret" "$RED_DIR" 2>/dev/null | awk -F: '{sum+=$2} END {print sum+0}')
  if [ "$hits" -gt 0 ]; then
    echo "LEAK: '$secret' -> $hits match(es)"
    leak_count=$((leak_count + hits))
  else
    echo "ok : '$secret' absent"
  fi
done
echo "Total leaks: $leak_count"
echo

# Presence check: per-artifact preserved marker(s).
miss_count=0
declare -a REQS=(
  "embercap-status.txt:%"
  "embercap-probe.txt:0x"
  "diag.json:currentCapacityMAh"
  "diag.json:cycleCount"
  "pmset-batt.txt:%"
  "ioreg-AppleSmartBattery.txt:CurrentCapacity"
  "ioreg-AppleSmartBattery.txt:CycleCount"
)
echo "Preservation checks"
echo "-------------------"
for req in "${REQS[@]}"; do
  file="${req%%:*}"
  pattern="${req##*:}"
  path="$RED_DIR/$file"
  if [ ! -f "$path" ]; then
    echo "MISS: $file (file absent)"
    miss_count=$((miss_count + 1))
    continue
  fi
  if grep -q -F "$pattern" "$path"; then
    echo "ok : $file contains '$pattern'"
  else
    echo "MISS: $file missing '$pattern'"
    miss_count=$((miss_count + 1))
  fi
done
echo "Total preservation misses: $miss_count"

if [ "$leak_count" -ne 0 ] || [ "$miss_count" -ne 0 ]; then
  exit 1
fi
exit 0
