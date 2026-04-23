# diag JSON schema (version 1)

`embercap diag --format=json` emits a document with these top-level keys:

| key | type | notes |
| --- | --- | --- |
| `schemaVersion` | int | currently `1`; bump on incompatible changes |
| `generatedAt` | string | ISO 8601 timestamp (UTC) |
| `tool` | object | `{ name, version, commitSHA? }` |
| `machine` | object | `MachineInfo` — model, cpu, arch, kernel, sw_vers, sip |
| `battery` | object | `BatterySnapshot` — see `BatteryStatus.swift` |
| `probe` | object | `ProbeReport` — see `ProbeSMC.swift` |

`probe.verdict` is one of: `legacy-abi-unavailable`, `blocked-by-policy`,
`partial-success`, `inconclusive`. See spec §5.2.

`probe.keyResults` is an array of `{ key, infoKr, readKr? }` per probed key,
where `infoKr` and `readKr` are raw `kern_return_t` integers.
