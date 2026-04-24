# embercap Charge-Limit Research Implementation Plan (2026-04-24)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Operationalize the research charter at
[docs/superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md](../specs/2026-04-24-embercap-charge-limit-research-charter-design.md)
by shipping the two redaction tools, running the Phase 1 read-only baseline
on `main`, and committing redacted artifacts plus the first section of the
research report. Phases 2–3 are left as detailed roadmaps for a future
session. Phase 4 is a deliberately gated stub. Phase 5 ships two templates.

**Architecture:** All observation commands are read-only. The redaction
pipeline is a pair of shell scripts: `scripts/redact-baseline.sh` applies
field-scoped `sed` rules to five known inputs and emits five redacted files
plus an index `README.md`; `scripts/verify-redaction.sh` grep-checks the
redacted directory for residues of the live user/host/serial/UUID values
and for presence of preserved diagnostic markers, exiting non-zero on any
failure so the commit does not proceed on a leak. The research report
`docs/research/charge-limit-experiment-2026-04-24.md` is the growing
record; Phase 1 is filled this session, Phases 2–5 are placeholder
headings. The `main` no-write-path guardrail (`scripts/check-no-write-path.sh`)
is re-run before and after the baseline capture and cited in the report.

**Tech Stack:** bash 3.2+ (macOS default), BSD `sed`, `grep`, `ioreg`,
`pmset`, `scutil`, Swift 6.3 + swift-testing for the existing CLI.
No new runtime dependencies.

---

## Scope

This plan covers work for the **2026-04-24 session only** unless a task is
explicitly marked "next session". In-session deliverables are Tasks 1–6.
Out-of-session content (Phase 2–5 roadmap) appears below Task 6 so the
executor has the full picture but does not execute it now.

**Binding constraints for this session (charter §3):**

- **R1** No SMC/IOKit write (binds Phase 4 too — see charter §1.2).
- **R2** No SIP change.
- **R3** No privileged helper/KEXT install.
- **R4** `main` read-only; `scripts/check-no-write-path.sh` passes before
  and after every change.
- **R6** No raw artifact commits — only redacted.
- **R7** No research branch/worktree creation this session.

## File Structure

Created by this plan:

- `scripts/redact-baseline.sh` — field-scoped `sed` redactor. Takes 5
  explicit input paths plus an output directory. Env-overridable
  `REDACT_USER` / `REDACT_HOSTNAME` for fixture testability.
- `scripts/verify-redaction.sh` — absence-grep and presence-grep
  verifier. Takes 5 raw input paths plus a redacted directory. Extracts
  secrets from the raws, grep-checks the redacted directory, and emits a
  summary block. Exits non-zero on any leak or missing preservation
  marker.
- `docs/research/charge-limit-experiment-2026-04-24.md` — phase-by-phase
  report. Phase 1 filled this session; Phases 2–5 are stub headings.
- `docs/research/baseline/2026-04-24/README.md` — index, written by
  `redact-baseline.sh`.
- `docs/research/baseline/2026-04-24/embercap-status.txt` — redacted
  human-readable status.
- `docs/research/baseline/2026-04-24/embercap-probe.txt` — redacted
  probe output.
- `docs/research/baseline/2026-04-24/diag.json` — redacted diag JSON.
- `docs/research/baseline/2026-04-24/pmset-batt.txt` — redacted
  `pmset -g batt` output.
- `docs/research/baseline/2026-04-24/ioreg-AppleSmartBattery.txt` —
  redacted `ioreg -rn AppleSmartBattery` dump.

Not modified: anything under `Sources/`, `Tests/`, `Package.swift`,
`README.md`, or `scripts/check-no-write-path.sh`.

Raw inputs live under `/tmp/embercap-baseline-*.{txt,json}` and are
**not** committed (charter R6).

---

## Task 1: `scripts/redact-baseline.sh` with fixture-driven check

**Files:**
- Create: `scripts/redact-baseline.sh`
- Fixtures (ephemeral): `/tmp/embercap-redact-fixtures/`

- [ ] **Step 1.1: Create failing fixtures**

Fixtures mimic real inputs and contain known-fake identifiers the script
must remove.

```bash
mkdir -p /tmp/embercap-redact-fixtures
cd /tmp/embercap-redact-fixtures

cat > raw-diag.json <<'JSON'
{
  "battery": {
    "currentCapacityMAh": 7210,
    "currentCapacityPercent": 100,
    "cycleCount": 160,
    "maxCapacityMAh": 7505,
    "serial": "FAKE-FIXTURE-SERIAL-1234ABCD",
    "temperatureCelsius": 30.56
  },
  "machine": {
    "kernel": "Darwin fixture-host 25.4.0 Darwin Kernel Version 25.4.0: root:xnu-12377.101.15 x86_64",
    "model": "MacBookPro16,1",
    "swVers": { "buildVersion": "25E253", "productVersion": "26.4.1" }
  },
  "tool": { "commitSHA": "abcdef0123456789abcdef0123456789abcdef01" }
}
JSON

cat > raw-ioreg.txt <<'IOR'
+-o AppleSmartBattery  <class AppleSmartBattery>
  | {
  |   "BatterySerialNumber" = "FAKE-BAT-SERIAL-W0LF"
  |   "IOPlatformSerialNumber" = "FAKE-PLATFORM-SERIAL-99QQ"
  |   "IOPlatformUUID" = "11111111-2222-3333-4444-555555555555"
  |   "UUID" = "99999999-aaaa-bbbb-cccc-eeeeeeeeeeee"
  |   "CurrentCapacity" = 7210
  |   "MaxCapacity" = 7505
  |   "CycleCount" = 160
  |   "Temperature" = 3056
  |   "IsCharging" = No
  |   "ExternalConnected" = Yes
  | }
IOR

cat > raw-status.txt <<'EOF'
embercap status
present: yes
power source: AC Power
charging: false
current %: 100%
cycle count: 160
serial: FAKE-FIXTURE-SERIAL-1234ABCD
Loaded from /Users/fixtureuser/embercap/.build/debug/embercap
EOF

cat > raw-probe.txt <<'EOF'
IOServiceOpen(AppleSMC) -> 0x00000000 (KERN_SUCCESS)
openSession selector=0 -> 0
getKeyInfo("TB0T") -> 0xe00002c2 (kIOReturnBadArgument)
getKeyInfo("BCLM") -> 0xe00002c2 (kIOReturnBadArgument)
EOF

cat > raw-pmset.txt <<'EOF'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=0)	100%; charged; 0:00 remaining present: true
EOF
```

Expected: files exist at `/tmp/embercap-redact-fixtures/raw-*`.

- [ ] **Step 1.2: Write the script**

Create `scripts/redact-baseline.sh` with this exact content:

```bash
#!/usr/bin/env bash
# Phase 1 baseline redactor for embercap charge-limit research.
# See charter §4.1–§4.5 at
#   docs/superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md
#
# Usage:
#   bash scripts/redact-baseline.sh \
#        <status_txt> <probe_txt> <diag_json> <pmset_txt> <ioreg_txt> \
#        <output_dir>
#
# Env overrides (for fixture testing):
#   REDACT_USER      — override the username treated as a secret
#   REDACT_HOSTNAME  — override the local hostname treated as a secret
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: $0 <status> <probe> <diag> <pmset> <ioreg> <output_dir>" >&2
  exit 2
fi

IN_STATUS="$1"
IN_PROBE="$2"
IN_DIAG="$3"
IN_PMSET="$4"
IN_IOREG="$5"
OUT_DIR="$6"

mkdir -p "$OUT_DIR"

LIVE_USER="${REDACT_USER:-${USER:-unknown}}"
if [ -n "${REDACT_HOSTNAME:-}" ]; then
  LIVE_HOST="$REDACT_HOSTNAME"
else
  LIVE_HOST="$(scutil --get LocalHostName 2>/dev/null || hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
fi

# Kernel-line hostname token: "Darwin <host> ..." -> "Darwin <HOSTNAME-REDACTED> ..."
KERNEL_HOST_SED='s/(Darwin )([^[:space:]\\"]+)/\1<HOSTNAME-REDACTED>/g'

# Field-scoped masker: matches  "Key" = "val"  (ioreg)  and  "Key" : "val"  (JSON).
field_scoped_sed() {
  local key="$1" placeholder="$2"
  printf 's/(\"%s\"[[:space:]]*=[[:space:]]*\")[^\"]*(\")/\\1%s\\2/g;' "$key" "$placeholder"
  printf 's/(\"%s\"[[:space:]]*:[[:space:]]*\")[^\"]*(\")/\\1%s\\2/g;' "$key" "$placeholder"
}

REDACT_SED=""
for k in BatterySerialNumber "Hardware Serial Number" "Serial Number" \
         IOPlatformSerialNumber PlatformSerialNumber MACAddress IOMACAddress; do
  REDACT_SED+="$(field_scoped_sed "$k" "<SERIAL-REDACTED>")"
done
REDACT_SED+="$(field_scoped_sed IOPlatformUUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed UUID "<UUID-REDACTED>")"
REDACT_SED+="$(field_scoped_sed serial "<SERIAL-REDACTED>")"

# serial: <value>  (human-readable status form, colon-separated, not quoted)
STATUS_SERIAL_SED='s/(^[[:space:]]*serial:[[:space:]]*)[^[:space:]].*$/\1<SERIAL-REDACTED>/'

# Home path and username (both forms: in paths, and as standalone words).
USER_SED="s|/Users/${LIVE_USER}|/Users/<USER-REDACTED>|g;"
USER_SED+="s/[[:<:]]${LIVE_USER}[[:>:]]/<USER-REDACTED>/g;"

HOST_SED="s/[[:<:]]${LIVE_HOST}[[:>:]]/<HOSTNAME-REDACTED>/g;"

redact() {
  local src="$1" dst="$2"
  sed -E \
    -e "$REDACT_SED" \
    -e "$KERNEL_HOST_SED" \
    -e "$STATUS_SERIAL_SED" \
    -e "$USER_SED" \
    -e "$HOST_SED" \
    "$src" > "$dst"
}

redact "$IN_STATUS" "$OUT_DIR/embercap-status.txt"
redact "$IN_PROBE"  "$OUT_DIR/embercap-probe.txt"
redact "$IN_DIAG"   "$OUT_DIR/diag.json"
redact "$IN_PMSET"  "$OUT_DIR/pmset-batt.txt"
redact "$IN_IOREG"  "$OUT_DIR/ioreg-AppleSmartBattery.txt"

cat > "$OUT_DIR/README.md" <<EOF
# Baseline artifacts — 2026-04-24

Per charter §7.1 and plan Phase 1. Redacted outputs of read-only Phase 1
commands. Raw inputs remained under \`/tmp\` and were not committed
(charter R6). Redaction rules: charter §4.1–§4.3. Placeholders:
\`<SERIAL-REDACTED>\`, \`<UUID-REDACTED>\`, \`<HOSTNAME-REDACTED>\`,
\`<USER-REDACTED>\`, \`<MAC-REDACTED>\`.

Files:

- \`embercap-status.txt\` — redacted \`.build/debug/embercap status\`.
- \`embercap-probe.txt\`  — redacted \`.build/debug/embercap probe\`.
- \`diag.json\`           — redacted \`.build/debug/embercap diag --format=json\`.
- \`pmset-batt.txt\`      — redacted \`pmset -g batt\`.
- \`ioreg-AppleSmartBattery.txt\` — redacted \`ioreg -rn AppleSmartBattery\`.

Generated by \`scripts/redact-baseline.sh\`.
EOF

echo "ok: wrote 5 redacted files + README.md to $OUT_DIR"
```

- [ ] **Step 1.3: Make executable and run against fixtures**

```bash
chmod +x scripts/redact-baseline.sh
REDACT_USER=fixtureuser REDACT_HOSTNAME=fixture-host \
  bash scripts/redact-baseline.sh \
    /tmp/embercap-redact-fixtures/raw-status.txt \
    /tmp/embercap-redact-fixtures/raw-probe.txt \
    /tmp/embercap-redact-fixtures/raw-diag.json \
    /tmp/embercap-redact-fixtures/raw-pmset.txt \
    /tmp/embercap-redact-fixtures/raw-ioreg.txt \
    /tmp/embercap-redact-fixtures/redacted
```

Expected stdout: `ok: wrote 5 redacted files + README.md to /tmp/embercap-redact-fixtures/redacted`.

- [ ] **Step 1.4: Assert fixture secrets are absent from redacted outputs**

```bash
set +e
count=0
for pattern in \
  "FAKE-FIXTURE-SERIAL-1234ABCD" \
  "FAKE-BAT-SERIAL-W0LF" \
  "FAKE-PLATFORM-SERIAL-99QQ" \
  "11111111-2222-3333-4444-555555555555" \
  "99999999-aaaa-bbbb-cccc-eeeeeeeeeeee" \
  "fixtureuser" \
  "fixture-host"; do
  hits=$(grep -r -F "$pattern" /tmp/embercap-redact-fixtures/redacted 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "LEAK: $pattern still present:" >&2
    echo "$hits" >&2
    count=$((count+1))
  fi
done
if [ "$count" -ne 0 ]; then
  echo "FAIL: $count leak(s) detected" >&2
  exit 1
fi
echo "ok: no fixture secrets leaked"
set -e
```

Expected: `ok: no fixture secrets leaked`. If any leak is printed, tighten
the rule that missed it in `scripts/redact-baseline.sh` and rerun Step 1.3.

- [ ] **Step 1.5: Assert preserved diagnostic markers survive**

```bash
set +e
count=0
for req in \
  "redacted/ioreg-AppleSmartBattery.txt:CurrentCapacity" \
  "redacted/ioreg-AppleSmartBattery.txt:CycleCount" \
  "redacted/ioreg-AppleSmartBattery.txt:Temperature" \
  "redacted/diag.json:currentCapacityMAh" \
  "redacted/diag.json:cycleCount" \
  "redacted/embercap-probe.txt:0xe00002c2" \
  "redacted/embercap-probe.txt:kIOReturnBadArgument" \
  "redacted/embercap-status.txt:cycle count"; do
  file="${req%%:*}"
  pattern="${req##*:}"
  if ! grep -q "$pattern" "/tmp/embercap-redact-fixtures/$file"; then
    echo "MISS: $pattern not found in $file" >&2
    count=$((count+1))
  fi
done
grep -q "abcdef0123456789abcdef0123456789abcdef01" \
  /tmp/embercap-redact-fixtures/redacted/diag.json \
  || { echo "MISS: commitSHA was incorrectly masked" >&2; count=$((count+1)); }
if [ "$count" -ne 0 ]; then
  echo "FAIL: $count preservation miss(es)" >&2
  exit 1
fi
echo "ok: all preservation markers present"
set -e
```

Expected: `ok: all preservation markers present`.

- [ ] **Step 1.6: Clean fixtures and commit the script**

```bash
rm -rf /tmp/embercap-redact-fixtures
git add scripts/redact-baseline.sh
git commit -m "feat(scripts): redact-baseline.sh for Phase 1 artifact sanitization

Field-scoped sed redactor per charter §4.1–§4.3. Takes 5 explicit input
paths plus an output directory. Masks battery/platform serials,
IOPlatformUUID, standalone UUID field, MAC addresses, username, home
path, and the Darwin-kernel hostname token. Preserves all diagnostic
numerics and IOKit return codes. Emits a README.md index alongside the
five redacted files. Env-overridable REDACT_USER and REDACT_HOSTNAME
for fixture testing.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: single commit on `main` touching only `scripts/redact-baseline.sh`.

---

## Task 2: `scripts/verify-redaction.sh` with fixture-driven check

**Files:**
- Create: `scripts/verify-redaction.sh`
- Fixtures (ephemeral): `/tmp/embercap-verify-fixtures/`

- [ ] **Step 2.1: Create fixtures (raws + good redacted dir + leaky redacted dir)**

```bash
mkdir -p /tmp/embercap-verify-fixtures/raw
mkdir -p /tmp/embercap-verify-fixtures/good
mkdir -p /tmp/embercap-verify-fixtures/leak
cd /tmp/embercap-verify-fixtures

# Same raws as Task 1 fixtures.
cat > raw/raw-diag.json <<'JSON'
{
  "battery": {
    "currentCapacityMAh": 7210,
    "cycleCount": 160,
    "maxCapacityMAh": 7505,
    "serial": "FAKE-FIXTURE-SERIAL-1234ABCD"
  },
  "machine": {
    "kernel": "Darwin fixture-host 25.4.0 x86_64"
  }
}
JSON

cat > raw/raw-ioreg.txt <<'IOR'
"BatterySerialNumber" = "FAKE-BAT-SERIAL-W0LF"
"IOPlatformUUID" = "11111111-2222-3333-4444-555555555555"
"CurrentCapacity" = 7210
"CycleCount" = 160
"Temperature" = 3056
IOR

cat > raw/raw-status.txt <<'EOF'
current %: 100%
cycle count: 160
serial: FAKE-FIXTURE-SERIAL-1234ABCD
/Users/fixtureuser/embercap
EOF

cat > raw/raw-probe.txt <<'EOF'
IOServiceOpen -> 0x00000000
getKeyInfo("TB0T") -> 0xe00002c2 (kIOReturnBadArgument)
EOF

cat > raw/raw-pmset.txt <<'EOF'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=0)	100%; charged; present: true
EOF

# Good redacted dir: no secrets, preservation markers present.
cat > good/diag.json <<'JSON'
{ "battery": { "currentCapacityMAh": 7210, "cycleCount": 160, "serial": "<SERIAL-REDACTED>" } }
JSON
cat > good/ioreg-AppleSmartBattery.txt <<'IOR'
"BatterySerialNumber" = "<SERIAL-REDACTED>"
"CurrentCapacity" = 7210
"CycleCount" = 160
"Temperature" = 3056
IOR
cat > good/embercap-status.txt <<'EOF'
current %: 100%
cycle count: 160
serial: <SERIAL-REDACTED>
/Users/<USER-REDACTED>/embercap
EOF
cat > good/embercap-probe.txt <<'EOF'
IOServiceOpen -> 0x00000000
getKeyInfo("TB0T") -> 0xe00002c2 (kIOReturnBadArgument)
EOF
cat > good/pmset-batt.txt <<'EOF'
Now drawing from 'AC Power'
 -InternalBattery-0 (id=0)	100%; charged
EOF

# Leak redacted dir: identical to good, but with the battery serial left in diag.json.
cp good/*.txt leak/
cat > leak/diag.json <<'JSON'
{ "battery": { "currentCapacityMAh": 7210, "cycleCount": 160, "serial": "FAKE-FIXTURE-SERIAL-1234ABCD" } }
JSON
```

Expected: three subdirectories `raw/`, `good/`, `leak/` under
`/tmp/embercap-verify-fixtures/`.

- [ ] **Step 2.2: Write the script**

Create `scripts/verify-redaction.sh` with this exact content:

```bash
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
```

- [ ] **Step 2.3: Make executable and run happy-path**

```bash
chmod +x scripts/verify-redaction.sh
VERIFY_USER=fixtureuser VERIFY_HOSTNAME=fixture-host \
  bash scripts/verify-redaction.sh \
    /tmp/embercap-verify-fixtures/raw/raw-status.txt \
    /tmp/embercap-verify-fixtures/raw/raw-probe.txt \
    /tmp/embercap-verify-fixtures/raw/raw-diag.json \
    /tmp/embercap-verify-fixtures/raw/raw-pmset.txt \
    /tmp/embercap-verify-fixtures/raw/raw-ioreg.txt \
    /tmp/embercap-verify-fixtures/good
echo "exit=$?"
```

Expected: `Total leaks: 0`, `Total preservation misses: 0`, and `exit=0`.

- [ ] **Step 2.4: Run sad-path (intentional leak), expect non-zero exit**

```bash
set +e
VERIFY_USER=fixtureuser VERIFY_HOSTNAME=fixture-host \
  bash scripts/verify-redaction.sh \
    /tmp/embercap-verify-fixtures/raw/raw-status.txt \
    /tmp/embercap-verify-fixtures/raw/raw-probe.txt \
    /tmp/embercap-verify-fixtures/raw/raw-diag.json \
    /tmp/embercap-verify-fixtures/raw/raw-pmset.txt \
    /tmp/embercap-verify-fixtures/raw/raw-ioreg.txt \
    /tmp/embercap-verify-fixtures/leak
rc=$?
set -e
if [ "$rc" -eq 0 ]; then
  echo "FAIL: sad-path did not fail" >&2
  exit 1
fi
echo "ok: sad-path correctly exited $rc"
```

Expected: `ok: sad-path correctly exited 1` (or any non-zero).

- [ ] **Step 2.5: Clean fixtures and commit the script**

```bash
rm -rf /tmp/embercap-verify-fixtures
git add scripts/verify-redaction.sh
git commit -m "feat(scripts): verify-redaction.sh absence + presence gate

Grep-checks a redacted directory against secrets extracted from the five
raw Phase 1 inputs (battery serial, hostname in kernel string, ioreg
BatterySerialNumber/IOPlatformUUID/IOPlatformSerialNumber if present,
live USER, home path, live hostname). Also confirms per-artifact
preservation markers survive (charge %, IOKit return codes,
currentCapacityMAh, cycleCount, CurrentCapacity, CycleCount). Exits
non-zero on any leak or missing marker so downstream commits abort on
a dirty baseline. Emits a summary block on stdout for copy-pasting
into the Phase 1 report.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: single commit touching only `scripts/verify-redaction.sh`.

---

## Task 3: Execute Phase 1 live baseline capture

**Files:**
- Read-only from repo (no edits here).
- Raw outputs → `/tmp/embercap-baseline-*` (not committed).

Every command below is read-only on the system. No writes, no installs.

- [ ] **Step 3.1: Pre-check `main` guardrail and tests**

```bash
git status --short --branch
bash scripts/check-no-write-path.sh
swift build
swift test
```

Expected:
- `git status` prints `## main...origin/main` with a clean working tree
  (or only untracked files outside `Sources/`).
- `check-no-write-path.sh` prints `ok: no write-path references in Sources/`.
- `swift build` succeeds; `swift test` reports all tests passing.

Record exact stdout/stderr for inclusion in the Phase 1 report
(verbatim, per R8).

- [ ] **Step 3.2: Capture five read-only snapshots to `/tmp`**

```bash
.build/debug/embercap status  > /tmp/embercap-baseline-status.txt
.build/debug/embercap probe   > /tmp/embercap-baseline-probe.txt
.build/debug/embercap diag --format=json > /tmp/embercap-baseline-diag.json
pmset -g batt                 > /tmp/embercap-baseline-pmset.txt
ioreg -rn AppleSmartBattery   > /tmp/embercap-baseline-ioreg.txt
ls -la /tmp/embercap-baseline-*
wc -l /tmp/embercap-baseline-*
```

Expected: all five files present with non-zero line counts.

- [ ] **Step 3.3: Redact with explicit file arguments**

```bash
mkdir -p docs/research/baseline/2026-04-24
bash scripts/redact-baseline.sh \
  /tmp/embercap-baseline-status.txt \
  /tmp/embercap-baseline-probe.txt \
  /tmp/embercap-baseline-diag.json \
  /tmp/embercap-baseline-pmset.txt \
  /tmp/embercap-baseline-ioreg.txt \
  docs/research/baseline/2026-04-24/
ls -la docs/research/baseline/2026-04-24/
```

Expected: six files in the output directory:
`README.md`, `embercap-status.txt`, `embercap-probe.txt`,
`diag.json`, `pmset-batt.txt`, `ioreg-AppleSmartBattery.txt`.

---

## Task 4: Verify redaction and commit baseline artifacts

**Files:**
- Commit: `docs/research/baseline/2026-04-24/**`

- [ ] **Step 4.1: Run verify-redaction (must pass before commit)**

```bash
bash scripts/verify-redaction.sh \
  /tmp/embercap-baseline-status.txt \
  /tmp/embercap-baseline-probe.txt \
  /tmp/embercap-baseline-diag.json \
  /tmp/embercap-baseline-pmset.txt \
  /tmp/embercap-baseline-ioreg.txt \
  docs/research/baseline/2026-04-24/ \
  | tee /tmp/embercap-baseline-verify-summary.txt
echo "verify exit=$?"
```

Expected: `Total leaks: 0`, `Total preservation misses: 0`, exit 0.
If exit non-zero: do **not** stage or commit. Investigate the leak or
miss, fix `scripts/redact-baseline.sh`, rerun Task 3 Step 3.3 and
Step 4.1. Record the incident in the Phase 1 report even if later
resolved (R8).

- [ ] **Step 4.2: Post-guardrail re-check (R4)**

```bash
bash scripts/check-no-write-path.sh
```

Expected: `ok: no write-path references in Sources/`.

- [ ] **Step 4.3: Commit the redacted baseline artifacts**

```bash
git add docs/research/baseline/2026-04-24/
git status --short
git commit -m "research(phase1): redacted baseline artifacts for 2026-04-24

Captures the Phase 1 read-only observation set per charter §7.1 and
plan Task 3. Includes embercap status/probe/diag.json, pmset -g batt,
and ioreg -rn AppleSmartBattery, each redacted via
scripts/redact-baseline.sh and verified by scripts/verify-redaction.sh
(0 leaks, 0 preservation misses) before this commit. Raw inputs
remain under /tmp and are not committed (R6).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: single commit adding six files under
`docs/research/baseline/2026-04-24/`.

---

## Task 5: Write Phase 1 section of the research report

**Files:**
- Create: `docs/research/charge-limit-experiment-2026-04-24.md`

- [ ] **Step 5.1: Extract observation values from the redacted artifacts**

Read these values out of the newly committed redacted files and keep
them handy — they become the Phase 1 "Observation summary" bullet
list.

```bash
# Charge state
grep -E 'current %|power source|charging:|cycle count' \
  docs/research/baseline/2026-04-24/embercap-status.txt

# Diag JSON fields — use a Python heredoc (macOS ships python3).
python3 <<'PY'
import json
d = json.load(open('docs/research/baseline/2026-04-24/diag.json'))
battery_keys = [
    'currentCapacityPercent', 'isCharging', 'externalConnected',
    'fullyCharged', 'notChargingReason', 'currentCapacityMAh',
    'maxCapacityMAh', 'designCapacityMAh', 'cycleCount',
    'temperatureCelsius', 'powerSourceState',
]
print(json.dumps({k: d['battery'].get(k) for k in battery_keys}, indent=2))
sw = d['machine']['swVers']
print('macOS', sw['productVersion'], '('+sw['buildVersion']+')',
      'SIP', d['machine']['sip'], 'model', d['machine']['model'])
print('probe verdict:', d['probe']['verdict'])
print('openKr:', d['probe']['openKr'])
print('openSessionKr:', d['probe']['openSessionKr'])
for r in d['probe']['keyResults']:
    print(' ', r['key'], 'infoKr =', r['infoKr'])
PY

# Probe verbose
cat docs/research/baseline/2026-04-24/embercap-probe.txt

# ioreg keys of interest
grep -E 'CurrentCapacity|MaxCapacity|DesignCapacity|CycleCount|Temperature|IsCharging|ExternalConnected|FullyCharged|NotChargingReason|Voltage|Amperage|InstantAmperage' \
  docs/research/baseline/2026-04-24/ioreg-AppleSmartBattery.txt

# Save verify summary already in /tmp from Task 4 Step 4.1
cat /tmp/embercap-baseline-verify-summary.txt
```

Expected: every command prints non-empty output. Copy the values
verbatim into the template below.

- [ ] **Step 5.2: Write the report using this template**

Create `docs/research/charge-limit-experiment-2026-04-24.md`. Fill the
bracketed `<...>` fields from Step 5.1 output. Leave Phases 2–5
headings as placeholders.

````markdown
# embercap charge-limit research — report (2026-04-24)

Companion to:

- Charter: [../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md](../superpowers/specs/2026-04-24-embercap-charge-limit-research-charter-design.md)
- Plan:    [../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md](../superpowers/plans/2026-04-24-embercap-charge-limit-research-plan.md)

All redacted artifacts for this report live under
[baseline/2026-04-24/](./baseline/2026-04-24/). Raw inputs remained
under `/tmp` and were not committed (charter R6).

---

## Phase 1 — baseline observation

- Executed on: 2026-04-24 (ISO timestamp from diag.json: `<generatedAt>`)
- Branch: `main` (no research branch created this session; charter R7)
- Guardrail pre-check: `bash scripts/check-no-write-path.sh` → `ok: no write-path references in Sources/`
- `swift build`: success
- `swift test`: <N> tests passing, <M> failing
- Commands run (in order):
  1. `git status --short --branch`
  2. `swift build`
  3. `swift test`
  4. `bash scripts/check-no-write-path.sh`
  5. `.build/debug/embercap status > /tmp/embercap-baseline-status.txt`
  6. `.build/debug/embercap probe  > /tmp/embercap-baseline-probe.txt`
  7. `.build/debug/embercap diag --format=json > /tmp/embercap-baseline-diag.json`
  8. `pmset -g batt > /tmp/embercap-baseline-pmset.txt`
  9. `ioreg -rn AppleSmartBattery > /tmp/embercap-baseline-ioreg.txt`
  10. `bash scripts/redact-baseline.sh <5 raw files> docs/research/baseline/2026-04-24/`
  11. `bash scripts/verify-redaction.sh <5 raw files> docs/research/baseline/2026-04-24/`
  12. `bash scripts/check-no-write-path.sh`

- Raw paths (out of repo, not committed):
  - `/tmp/embercap-baseline-status.txt`
  - `/tmp/embercap-baseline-probe.txt`
  - `/tmp/embercap-baseline-diag.json`
  - `/tmp/embercap-baseline-pmset.txt`
  - `/tmp/embercap-baseline-ioreg.txt`

- Redacted artifacts (committed):
  - [baseline/2026-04-24/embercap-status.txt](./baseline/2026-04-24/embercap-status.txt)
  - [baseline/2026-04-24/embercap-probe.txt](./baseline/2026-04-24/embercap-probe.txt)
  - [baseline/2026-04-24/diag.json](./baseline/2026-04-24/diag.json)
  - [baseline/2026-04-24/pmset-batt.txt](./baseline/2026-04-24/pmset-batt.txt)
  - [baseline/2026-04-24/ioreg-AppleSmartBattery.txt](./baseline/2026-04-24/ioreg-AppleSmartBattery.txt)

### Observation summary

- Environment:
  - Model: `<model>` (expected `MacBookPro16,1`)
  - macOS: `<productVersion> (<buildVersion>)` (expected `26.4.1 (25E…)`)
  - SIP: `<sip>` (expected `enabled`)
- Battery:
  - Charge percentage: `<currentCapacityPercent>%`
  - `isCharging`: `<value>`
  - `externalConnected`: `<value>`
  - `fullyCharged`: `<value>`
  - `notChargingReason`: `<value>`
  - `powerSourceState`: `<value>`
  - Capacities (design/max/current, mAh): `<design>/<max>/<current>`
  - CycleCount: `<value>`
  - Temperature: `<temperatureCelsius>` °C
- Probe (from `diag.json`):
  - Verdict: `<probe.verdict>`
  - `openKr`: `<value>` (expected `0`)
  - `openSessionKr`: `<value>` (expected `0`)
  - Key results (`infoKr`): `TB0T=<v>`, `BNum=<v>`, `BSIn=<v>`, `BCLM=<v>`, `CH0B=<v>`, `CH0C=<v>`, `CHWA=<v>`, `CHBI=<v>`, `CHLC=<v>`

### Redaction verification

(Copied from `/tmp/embercap-baseline-verify-summary.txt`.)

```
<verify-redaction.sh summary block pasted here verbatim>
```

### Verdict

- Phase 1 complete. All 5 redacted artifacts + index `README.md` committed.
- `main` guardrail green before and after (`check-no-write-path.sh` and
  `swift test` both passed pre- and post-capture).
- No branch created; all work on `main` (charter R7 honored).
- Observations pinned for comparison in later phases.

### Links

- Charter §3 (safety rules), §4 (redaction), §7 (artifact conventions)
- Plan Task 3, Task 4

---

## Phase 2 — non-invasive control investigation

> Not executed in this session. See plan "Phase 2 roadmap (next session)" below.
> This section will be filled when Phase 2 is executed.

## Phase 3 — existing-tool evidence

> Not executed in this session. See plan "Phase 3 roadmap (next session)" below.

## Phase 4 — 80% mutation test

> Gated. Not authorized until charter G3→4 H1–H5 are all satisfied.
> See plan "Phase 4 roadmap (STUB)" below.

## Phase 5 — report

> Template only; see plan "Phase 5 templates".
````

- [ ] **Step 5.3: Commit the Phase 1 report**

```bash
git add docs/research/charge-limit-experiment-2026-04-24.md
git status --short
git commit -m "research(phase1): Phase 1 baseline report for 2026-04-24

Records exact command sequence, environment (model, macOS build, SIP),
observed battery state (charge %, capacities, cycle count, temperature,
notChargingReason, powerSourceState), probe verdict and per-key infoKr,
and verify-redaction summary. Cites redacted artifacts under
docs/research/baseline/2026-04-24/. Phases 2–5 are placeholder headings.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

Expected: single commit adding the report.

---

## Task 6: Final guardrail verification

**Files:**
- No repo edits; verification only.

- [ ] **Step 6.1: Run the write-path guardrail one more time**

```bash
bash scripts/check-no-write-path.sh
```

Expected: `ok: no write-path references in Sources/`.

- [ ] **Step 6.2: Re-run tests**

```bash
swift test
```

Expected: all tests pass (same count and result as Task 3 Step 3.1).

- [ ] **Step 6.3: Summarize session**

Print a one-screen summary:

```bash
echo "=== Session summary ==="
git log --oneline -10
echo "---"
ls docs/research/baseline/2026-04-24/
echo "---"
ls docs/superpowers/specs/ | tail -3
ls docs/superpowers/plans/ | tail -3
```

Expected: at least four new commits since the charter (scripts ×2,
baseline artifacts, Phase 1 report), the six baseline files in place,
and both the charter and this plan listed.

---

## Phase 2 roadmap (next session, not executed now)

Reference content for the executor of a later session. Do not run these
commands in the 2026-04-24 session.

**Objective:** identify ≥0 public/semi-public control properties,
commands, or settings that could act as charge-limit surfaces. Charter
§5 G2→3 does **not** abort if 0 candidates are found here.

**Commands (save full outputs):**

```bash
pmset -g custom                             > /tmp/phase2-pmset-custom.txt
pmset -g rawlog                             > /tmp/phase2-pmset-rawlog.txt
pmset -g assertions                         > /tmp/phase2-pmset-assertions.txt
ioreg -l -w0 -r -c AppleSmartBattery        > /tmp/phase2-ioreg-battery.txt
ioreg -l -w0 -p IOService -n AppleSMC       > /tmp/phase2-ioreg-smc.txt
defaults read com.apple.PowerManagement 2>&1 > /tmp/phase2-power-prefs.txt
```

**Human preview (read only; do not substitute for full artifacts):**

```bash
head -200 /tmp/phase2-ioreg-battery.txt
head -200 /tmp/phase2-ioreg-smc.txt
tail -100 /tmp/phase2-pmset-rawlog.txt
```

**Redact + verify:** same pipeline as Phase 1, explicit file args, target
`docs/research/phase2/2026-04-24/` (or the date of the next session if
different). Note that the two scripts from Task 1 and Task 2 are
hard-coded to five Phase 1 filenames; for Phase 2 either extend the
scripts with a generic N-file mode OR write a tiny wrapper that calls
the same `sed` body against Phase 2 filenames. Prefer generalization if
both Phase 2 and Phase 3 need it.

**Observation targets:**

- Presence/absence of keywords: `optimized battery charging`,
  `charge inhibit`, `charge limit`, `battery health management`,
  `BatteryCharging`, `BCLM`, `CHWA`, `CH0C`, `CH0J`, `CH0I`, `CH0K`.
- Writable property candidates on `AppleSmartBattery` (fields flagged as
  settable in ioreg).
- `powerd`-managed keys of interest in `com.apple.PowerManagement`.

**Exit criteria:** all full outputs saved, redacted, verified, and
committed; report Phase 2 section states either
"N candidate(s) identified: [keys]" or
"0 candidates: evidence scan includes [list]".

## Phase 3 roadmap (next session, not executed now)

**Objective:** determine whether any charge-limit tool is *already*
installed and has operated on this system. Collect evidence without
installing, starting, loading, or registering anything new (charter R3).

**Commands (observation only):**

```bash
mdfind "kMDItemFSName == '*AlDente*'"           > /tmp/phase3-mdfind-aldente.txt
mdfind "kMDItemFSName == '*bclm*'"              > /tmp/phase3-mdfind-bclm.txt

command -v bclm     > /tmp/phase3-which-bclm.txt    2>&1 || true
command -v aldente  > /tmp/phase3-which-aldente.txt 2>&1 || true

ls -la /Library/LaunchDaemons/                  > /tmp/phase3-launchdaemons.txt 2>&1 || true
ls -la /Library/LaunchAgents/                   > /tmp/phase3-launchagents.txt  2>&1 || true
ls -la /Library/PrivilegedHelperTools/          > /tmp/phase3-privileged-helpers.txt 2>&1 || true
launchctl list                                  > /tmp/phase3-launchctl-list.txt 2>&1 || true
```

For any binary or bundle discovered, run **observation-only** tools
(no execution, no load, no start):

```bash
otool -L <path>
codesign -dvv <path>
defaults read <bundle_domain> 2>/dev/null || true
ls -la <preferences_path>
```

Do **not** run discovered binaries. Do **not** `launchctl load` or
`launchctl start` anything. Do **not** reinstall or upgrade.

**Observation targets:**

- For each candidate tool (AlDente, bclm, plus anything else found in
  `/Library/PrivilegedHelperTools`): verdict
  `"missing"` / `"installed-inactive"` / `"installed-active"`.
- If active: most recent log lines from observed log paths (redacted).
- Presence of agent/daemon labels in `launchctl list` matching
  `aldente|bclm|charge`.
- Anything named `*aldente*`, `*bclm*`, `*charge*` in
  `/Library/PrivilegedHelperTools/`.

`command -v` is a reference signal only; a hit is suggestive but an
absence is not proof of un-installation. The filesystem and LaunchDaemon
signals are primary.

**Exit criteria:** report Phase 3 section lists each candidate tool with
a concrete verdict and cites artifact paths.

## Gate G3→4 — hard checklist (next session)

Charter §5 G3→4 must be evaluated as a checklist. Phase 4 does **not**
proceed unless every item is checked.

- [ ] **H1** ≥1 concrete control candidate identified (Phase 2 property
      OR Phase 3 tool-operation evidence).
- [ ] **H2** reversible reset path documented (exact commands, or
      reboot/SMC-reset fallback with expected behavior and explicit
      risks).
- [ ] **H3** explicit user written Phase 4 approval recorded in the
      active session.
- [ ] **H4** `main` guardrail green re-checked immediately before any
      mutation step.
- [ ] **H5** raw-vs-redacted artifact policy re-confirmed (no raw dumps
      in repo).

Abort mapping (charter §6):

- H1 unmet → abort to Phase 5b.
- H2 unmet → abort to Phase 5b.
- H4 broken mid-execution → immediate abort.
- H3 or H5 unmet → do not proceed; re-seek approval / re-verify policy.

## Phase 4 roadmap (STUB, gated)

This section is intentionally left as a stub.

It will be filled in a **separate plan document** only after:

- Phase 3 completion,
- Gate G3→4 H1–H5 all satisfied,
- user explicit approval recorded.

Until then, do **not** attempt any mutation step. Reference: charter §5
(G3→4), §6 (abort), §1.2 (mutation terminology).

Placeholder structure (to be filled in the separate Phase 4 plan):

- Target: 80%.
- Mechanism: `<chosen public/semi-public control surface>` (never an
  SMC/IOKit write — R1).
- Command(s): `<to be written>`.
- Observation cadence: snapshot every 10–15 min for ≥2h, or until the
  battery naturally reaches 80% if discharging from 100%.
- Reset command: `<to be written>`.
- Success criteria (from the original prompt):
  - charge stops or remains near 80% while AC is connected,
  - status clearly reports not-charging or equivalent state,
  - setting persists across short sleep/wake,
  - no abnormal battery temperature or power instability,
  - reset path works.
- Failure criteria:
  - charge continues above 85% while AC is connected,
  - API reports success but no behavioral change,
  - setting disappears immediately,
  - machine shows abnormal power behavior,
  - reset path is unclear.

## Phase 5 templates

Produced regardless of outcome. One of the two templates below is used
when Phase 4 (or its abort) occurs.

### Phase 5a — success report template

- Executive summary.
- Environment match with Phase 1 baseline (explicit diff).
- Mechanism used.
- Commands run (full list).
- Observations at each snapshot (with capacity/state).
- Reset verification.
- Recommended next target (75% or 70%, not below 60% initially).
- Recommendation on `main` / `research` / abandon.
- Updates to `README.md` or existing spec if applicable.

### Phase 5b — negative-result report template

- Executive summary with abort condition:
  `A(2∧3-empty)` / `A(H1-unmet)` / `A(H2-unmet)`.
- Phase 2 evidence summary.
- Phase 3 evidence summary.
- Why H1 or H2 was not satisfied (if applicable).
- Artifact links (charter §7.1 layout).
- Follow-up: add a one-line reference in `README.md` or the existing
  read-only diag CLI spec noting "2026-04-24 follow-up confirmed
  negative-result".
- Recommendation: keep `main` read-only, no write-path code.
