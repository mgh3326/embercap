#!/usr/bin/env bash
# Phase 2 redactor for embercap charge-limit research.
# See charter §4.1–§4.5 at
#   docs/superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md
# and plan "Phase 2 roadmap" at
#   docs/superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md
#
# Extends the Phase 1 field-scoped sed approach with AppleSMC-specific
# coverage (IOConsoleUsers session UUID + user names, IOMACAddress hex
# form, SerialString in AdapterDetails). Keeps the Phase 1 rules intact
# so Phase 1 behavior is unaffected.
#
# Usage:
#   bash scripts/redact-phase2.sh <input_dir> <output_dir>
#
# Input files expected under <input_dir> (missing files are skipped):
#   pmset-custom.txt
#   pmset-rawlog.txt
#   pmset-assertions.txt
#   ioreg-AppleSmartBattery-full.txt
#   ioreg-AppleSMC-full.txt
#   power-prefs.txt
#   power-prefs.stderr
#
# Env overrides (for fixture testing):
#   REDACT_USER      — override the username treated as a secret
#   REDACT_HOSTNAME  — override the local hostname treated as a secret
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <input_dir> <output_dir>" >&2
  exit 2
fi

IN_DIR="$1"
OUT_DIR="$2"

mkdir -p "$OUT_DIR"

LIVE_USER="${REDACT_USER:-${USER:-unknown}}"
if [ -n "${REDACT_HOSTNAME:-}" ]; then
  LIVE_HOST="$REDACT_HOSTNAME"
else
  LIVE_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
fi

# Field-scoped masker: matches  "Key" = "val"  (ioreg)  and  "Key" : "val"  (JSON).
# Handles both spaced ("Key" = "val") and compact ("Key"="val") forms via [[:space:]]*.
field_scoped_sed() {
  local key="$1" placeholder="$2"
  printf 's/(\"%s\"[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\\1%s\\2/g;' "$key" "$placeholder"
  printf 's/(\"%s\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\\1%s\\2/g;' "$key" "$placeholder"
}

# Hex-bracketed field masker: matches  "Key" = <hexhexhex>  (ioreg raw hex).
field_scoped_hex_sed() {
  local key="$1" placeholder="$2"
  printf 's/(\"%s\"[[:space:]]*=[[:space:]]*)<[0-9a-fA-F]+>/\\1%s/g;' "$key" "$placeholder"
}

REDACT_SED=""
# Same serial-bearing keys as Phase 1, plus AppleSMC-/USB-bus-specific keys
# observed in the live Phase 2 ioreg dumps:
#   SerialString          — USB-C power adapter serial (AppleSmartBattery
#                           AdapterDetails / AppleRawAdapterDetails).
#   SerialNumber          — generic single-word serial key used by NVMe
#                           controllers, BCMRAID, USB devices ("APPLE
#                           Storage Engine"-style) under AppleSMC's IOService
#                           subtree. Distinct from the spaced "Serial Number"
#                           key used by IOMedia/IOBlockStorageDevice.
#   kUSBSerialNumberString — USB device-descriptor iSerialNumber string
#                           value, surfaces under IOUSBHostDevice nodes.
#   iSerialNumber, DisplaySerialNumber, FirmwareSerialNumber — defensive
#                           coverage for related identifier-bearing keys
#                           that appear in macOS ioreg dumps even if they
#                           are empty on this machine.
for k in BatterySerialNumber "Hardware Serial Number" "Serial Number" \
         IOPlatformSerialNumber PlatformSerialNumber MACAddress IOMACAddress \
         Serial SerialString SerialNumber kUSBSerialNumberString \
         iSerialNumber DisplaySerialNumber FirmwareSerialNumber \
         "USB Serial Number"; do
  REDACT_SED+="$(field_scoped_sed "$k" "<SERIAL-REDACTED>")"
done
REDACT_SED+="$(field_scoped_sed IOPlatformUUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed UUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed serial "<SERIAL-REDACTED>")"

# IOConsoleUsers session fields (AppleSMC ioreg).
REDACT_SED+="$(field_scoped_sed CGSSessionUniqueSessionUUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed kCGSSessionUserNameKey "<USER-REDACTED>")"
REDACT_SED+="$(field_scoped_sed kCGSessionLongUserNameKey "<USER-REDACTED>")"

# IOMACAddress raw hex form.
REDACT_SED+="$(field_scoped_hex_sed IOMACAddress "<MAC-REDACTED>")"
REDACT_SED+="$(field_scoped_hex_sed MACAddress  "<MAC-REDACTED>")"

# ThunderboltUUID ships as raw hex (no dashes) inside angle brackets.
REDACT_SED+="$(field_scoped_hex_sed ThunderboltUUID "<UUID-REDACTED>")"

# Fallback: any UUID-shaped token (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX).
# Covers remaining machine-scoped fields (BootSessionUUID, SleepWakeUUID,
# "Domain UUID", VolGroupUUID, IOSkywalkNexusUUID, previous-system-uuid,
# embedded "network [UUID]" Thunderbolt keys, and disk partition UUIDs
# nested inside plist-XML string blobs). Partition-type GUIDs (APFS/EFI
# content types) are masked by the same rule — acceptable since those
# public constants are not diagnostic markers for charge-limit research.
UUID_FALLBACK_SED='s/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<UUID-REDACTED>/g'

# Home path and username (paths and standalone words).
USER_SED="s|/Users/${LIVE_USER}|/Users/<USER-REDACTED>|g;"
USER_SED+="s/[[:<:]]${LIVE_USER}[[:>:]]/<USER-REDACTED>/g;"

HOST_SED="s/[[:<:]]${LIVE_HOST}[[:>:]]/<HOSTNAME-REDACTED>/g;"

# Materialize the full sed program into a file with ONE rule per line.
# BSD sed (macOS default) parses each line of a -f script as an
# independent expression, which avoids both (a) the practical length
# limit on a single -e argument and (b) the bracket-balancing parser
# bug that triggers on very long single-line scripts containing many
# [[:space:]] / [^"] character classes.
SED_SCRIPT="$(mktemp -t embercap-phase2-sed)"
trap 'rm -f "$SED_SCRIPT"' EXIT
{
  # Split semicolon-joined rule strings into one rule per line. The rule
  # bodies do not contain literal semicolons, so a plain `tr ';' '\n'`
  # is a faithful split.
  printf '%s' "$REDACT_SED" | tr ';' '\n'
  printf '%s' "$USER_SED" | tr ';' '\n'
  printf '%s' "$HOST_SED" | tr ';' '\n'
  printf '%s\n' "$UUID_FALLBACK_SED"
} | sed '/^$/d' > "$SED_SCRIPT"

redact() {
  local src="$1" dst="$2"
  sed -E -f "$SED_SCRIPT" "$src" > "$dst"
}

count=0
for f in pmset-custom.txt pmset-rawlog.txt pmset-assertions.txt \
         ioreg-AppleSmartBattery-full.txt ioreg-AppleSMC-full.txt \
         power-prefs.txt power-prefs.stderr; do
  if [ -f "$IN_DIR/$f" ]; then
    redact "$IN_DIR/$f" "$OUT_DIR/$f"
    count=$((count + 1))
  fi
done

cat > "$OUT_DIR/README.md" <<EOF
# Phase 2 artifacts — 2026-04-25

Per charter §7.1 and plan "Phase 2 roadmap". Redacted outputs of the
Phase 2 read-only investigation into non-invasive charge-control
surfaces. Raw inputs remained under \`/tmp/embercap-phase2/\` and were
not committed (charter R6).

Redaction rules extend the Phase 1 field-scoped \`sed\` approach
(\`scripts/redact-baseline.sh\`) with additional coverage for
AppleSMC-specific fields: \`SerialString\` (USB-C adapter),
\`CGSSessionUniqueSessionUUID\`, \`kCGSSessionUserNameKey\`,
\`kCGSessionLongUserNameKey\`, and \`IOMACAddress\` in raw-hex form.
Placeholders: \`<SERIAL-REDACTED>\`, \`<UUID-REDACTED>\`,
\`<HOSTNAME-REDACTED>\`, \`<USER-REDACTED>\`, \`<MAC-REDACTED>\`.

Files:

- \`pmset-custom.txt\`                 — redacted \`pmset -g custom\`.
- \`pmset-rawlog.txt\`                 — redacted \`pmset -g rawlog\` (sampled).
- \`pmset-assertions.txt\`             — redacted \`pmset -g assertions\`.
- \`ioreg-AppleSmartBattery-full.txt\` — redacted \`ioreg -l -w0 -r -c AppleSmartBattery\`.
- \`ioreg-AppleSMC-full.txt\`          — redacted \`ioreg -l -w0 -p IOService -n AppleSMC\`.
- \`power-prefs.txt\`                  — redacted \`defaults read com.apple.PowerManagement\` stdout.
- \`power-prefs.stderr\`               — redacted \`defaults read com.apple.PowerManagement\` stderr.

Generated by \`scripts/redact-phase2.sh\`.
EOF

echo "ok: wrote $count redacted file(s) + README.md to $OUT_DIR"
