#!/usr/bin/env bash
# Phase 3 redactor for embercap charge-limit research.
# See charter §4.1–§4.5 at
#   docs/superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md
# and plan "Phase 3 roadmap" at
#   docs/superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md
#
# Phase 3 collects existing-tool evidence (AlDente, bclm, related charge
# helpers) — observation only, no execution. The artifacts mostly come
# from `mdfind`, `find`, `ls -la`, `launchctl list`, `command -v`,
# `plutil -p`, `codesign -dvv`, `otool -L`, and `defaults read`.
# Compared to Phase 1/2, none of these emit raw battery serials or
# AppleSMC IOReg blobs, so the redactor's main job here is:
#
#   1. Strip the live username from `ls -la` owner columns and any
#      `/Users/<username>` paths.
#   2. Strip the local hostname defensively even though we did not
#      observe it in Phase 3 raw output.
#   3. Apply the Phase 2 field-scoped serial/UUID rules defensively in
#      case discovered Info.plist / defaults blobs surface an identifier.
#
# Phase 1 (`redact-baseline.sh`) and Phase 2 (`redact-phase2.sh`) remain
# the canonical redactors for their own artifact sets; this script does
# not modify them.
#
# Usage:
#   bash scripts/redact-phase3.sh <input_dir> <output_dir>
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

# plutil -p keys use the form  "Key" => "val"  — same shape, different
# separator. Cover it explicitly so any Info.plist string-valued
# identifier is masked symmetrically with the ioreg/JSON forms.
field_scoped_plutil_sed() {
  local key="$1" placeholder="$2"
  printf 's/(\"%s\"[[:space:]]*=>[[:space:]]*\")[^\"]*(\")/\\1%s\\2/g;' "$key" "$placeholder"
}

REDACT_SED=""
# Defensive coverage: same identifier-bearing keys as Phase 2 so that any
# Info.plist / defaults blob discovered under a third-party charge-tool
# bundle gets the same treatment.
for k in BatterySerialNumber "Hardware Serial Number" "Serial Number" \
         IOPlatformSerialNumber PlatformSerialNumber MACAddress IOMACAddress \
         Serial SerialString SerialNumber kUSBSerialNumberString \
         iSerialNumber DisplaySerialNumber FirmwareSerialNumber \
         "USB Serial Number"; do
  REDACT_SED+="$(field_scoped_sed "$k" "<SERIAL-REDACTED>")"
  REDACT_SED+="$(field_scoped_plutil_sed "$k" "<SERIAL-REDACTED>")"
done
REDACT_SED+="$(field_scoped_sed IOPlatformUUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed UUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed serial "<SERIAL-REDACTED>")"
REDACT_SED+="$(field_scoped_plutil_sed UUID "<UUID-REDACTED>")"

# License-style keys that may live inside third-party defaults / Info.plist
# bundles. None of these were observed in Phase 3 raw output but masking
# them defensively means a future re-run that finds an active install
# does not silently disclose a licence.
for k in LicenseKey licenseKey "license-key" "License Key" \
         RegistrationKey ActivationCode UserEmail UserName CustomerID; do
  REDACT_SED+="$(field_scoped_sed "$k" "<APP-SECRET-REDACTED>")"
  REDACT_SED+="$(field_scoped_plutil_sed "$k" "<APP-SECRET-REDACTED>")"
done

# Fallback: any UUID-shaped token (XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX).
UUID_FALLBACK_SED='s/[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}/<UUID-REDACTED>/g'

# Home path and username (paths and standalone words). The `ls -la`
# owner column is the principal Phase 3 username surface, so the
# word-boundary rule must catch tokens like `mgh3326  staff`.
USER_SED="s|/Users/${LIVE_USER}|/Users/<USER-REDACTED>|g;"
USER_SED+="s/[[:<:]]${LIVE_USER}[[:>:]]/<USER-REDACTED>/g;"

HOST_SED="s/[[:<:]]${LIVE_HOST}[[:>:]]/<HOSTNAME-REDACTED>/g;"

# Materialize the full sed program one rule per line for the same
# BSD-sed-friendliness reason as Phase 2.
SED_SCRIPT="$(mktemp -t embercap-phase3-sed)"
trap 'rm -f "$SED_SCRIPT"' EXIT
{
  printf '%s' "$REDACT_SED" | tr ';' '\n'
  printf '%s' "$USER_SED" | tr ';' '\n'
  printf '%s' "$HOST_SED" | tr ';' '\n'
  printf '%s\n' "$UUID_FALLBACK_SED"
} | sed '/^$/d' > "$SED_SCRIPT"

redact() {
  local src="$1" dst="$2"
  sed -E -f "$SED_SCRIPT" "$src" > "$dst"
}

# Phase 3 artifact set. Order is presentational — the README cites them
# in the same order. Missing files are skipped (some discovery commands
# legitimately produce no candidates).
ARTIFACTS=(
  mdfind-aldente.txt
  mdfind-bclm.txt
  mdfind-charge.txt
  which-aldente.txt
  which-bclm.txt
  applications.txt
  launchdaemons.txt
  launchagents.txt
  privileged-helpers.txt
  launchctl-list.txt
  launchctl-aldente-grep.txt
  find-app-launch-helper-charge-tools.txt
  ls-aldente-contents.txt
  ls-aldente-launchservices.txt
  ls-aldente-macos.txt
  plutil-aldente-info-plist.txt
  plutil-aldente-launchdaemon-plist.txt
  codesign-aldente-app.txt
  codesign-aldente-bundled-helper.txt
  otool-aldente-main.txt
  otool-aldente-bundled-helper.txt
  defaults-aldente.txt
  ls-user-launchagents.txt
  ls-user-prefs-charge-grep.txt
  ls-user-app-support-charge-grep.txt
  ls-user-logs-charge-grep.txt
)

count=0
for f in "${ARTIFACTS[@]}"; do
  if [ -f "$IN_DIR/$f" ]; then
    redact "$IN_DIR/$f" "$OUT_DIR/$f"
    count=$((count + 1))
  fi
done

cat > "$OUT_DIR/README.md" <<EOF
# Phase 3 artifacts — 2026-04-25

Per charter §7.1 and plan "Phase 3 roadmap". Redacted outputs of the
Phase 3 read-only investigation into existing charge-limit tool
installation evidence (AlDente / bclm / related helpers). Raw inputs
remained under \`/tmp/embercap-phase3/\` and were not committed
(charter R6).

Redaction rules reuse the Phase 2 field-scoped \`sed\` approach
(\`scripts/redact-phase2.sh\`) plus a plutil-form variant
(\`"Key" => "val"\`) for Info.plist dumps. The principal masking
surface in Phase 3 is the live username appearing in \`ls -la\` owner
columns; UUID/serial/MAC rules from Phase 2 are carried forward
defensively. Placeholders: \`<SERIAL-REDACTED>\`, \`<UUID-REDACTED>\`,
\`<HOSTNAME-REDACTED>\`, \`<USER-REDACTED>\`, \`<MAC-REDACTED>\`,
\`<APP-SECRET-REDACTED>\`.

Tool names, bundle identifiers (\`com.apphousekitchen.aldente-pro\`
and friends), launchd labels, file paths after username redaction,
code-signing authorities, and bundle versions are preserved
intentionally per charter §4.2 (preserve evidentiary content).

Files (missing entries simply mean no candidate was found):

- \`mdfind-aldente.txt\` / \`mdfind-bclm.txt\` / \`mdfind-charge.txt\`
  — Spotlight searches for tool-name files.
- \`which-aldente.txt\` / \`which-bclm.txt\` — \`command -v\` PATH probes.
- \`applications.txt\` — \`ls -la /Applications/\` snapshot.
- \`launchdaemons.txt\` / \`launchagents.txt\` — \`/Library/LaunchDaemons\` and
  \`/Library/LaunchAgents\` snapshots.
- \`privileged-helpers.txt\` — \`ls -la /Library/PrivilegedHelperTools/\`
  (note: directory absent on this Mac; output is the \`ls\` error).
- \`launchctl-list.txt\` — full \`launchctl list\` for the user domain.
- \`launchctl-aldente-grep.txt\` — \`launchctl list\` filtered by
  charge-tool keywords.
- \`find-app-launch-helper-charge-tools.txt\` — recursive \`find\` across
  Applications / LaunchDaemons / LaunchAgents / PrivilegedHelperTools.
- \`ls-aldente-contents.txt\` / \`ls-aldente-launchservices.txt\` /
  \`ls-aldente-macos.txt\` — bundle structure for the AlDente.app
  installation discovered by \`find\`.
- \`plutil-aldente-info-plist.txt\` — AlDente.app \`Info.plist\` dump.
- \`plutil-aldente-launchdaemon-plist.txt\` — \`/Library/LaunchDaemons/com.apphousekitchen.aldente-pro.helper.plist\`.
- \`codesign-aldente-app.txt\` /
  \`codesign-aldente-bundled-helper.txt\` — \`codesign -dvv\` metadata for
  the app and the bundled helper binary.
- \`otool-aldente-main.txt\` /
  \`otool-aldente-bundled-helper.txt\` — \`otool -L\` linkage for the same
  two binaries.
- \`defaults-aldente.txt\` — \`defaults read com.apphousekitchen.aldente-pro\`
  (returns "Domain does not exist" on this Mac — strong negative
  evidence for user-domain operation).
- \`ls-user-launchagents.txt\` — \`ls -la ~/Library/LaunchAgents\` snapshot.
- \`ls-user-prefs-charge-grep.txt\` /
  \`ls-user-app-support-charge-grep.txt\` /
  \`ls-user-logs-charge-grep.txt\` — \`ls -la\` of
  \`~/Library/Preferences\`, \`~/Library/Application Support\`, and
  \`~/Library/Logs\` filtered by charge-tool keywords (all empty).

Generated by \`scripts/redact-phase3.sh\`.
EOF

echo "ok: wrote $count redacted file(s) + README.md to $OUT_DIR"
