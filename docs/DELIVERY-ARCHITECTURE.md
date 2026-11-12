# Delivery ledger v1

## Storage and transactions

`Core/DeliveryModels.swift` owns money, signed assignments, settlement revisions, evidence roles, bank checks, reports, acknowledgements and cash handovers. UI does not compute financial state from formatted strings. VND uses Int64, bounded to 10^12 per monetary field; JSON numeric/boolean ambiguity is rejected by the Bill importer.

The first delivery build stores a versioned Codable ledger snapshot in SQLite (`user_version=1`), with WAL and synchronous FULL. All business entities have stable UUIDs and are preserved inside the same committed snapshot. Updates use `BEGIN IMMEDIATE`, retain the preceding snapshot, enforce append-only histories and commit the whole ledger atomically. Invalid or unreadable data never becomes an empty reset. This is a transactional snapshot design, not a normalized per-entity SQL schema; normalization is a future migration if ledger size makes whole-snapshot encoding measurable.

Evidence lives in Application Support outside image compression/cache directories. Its filenames use generated UUIDs; records store role, byte length and SHA-256. Provider data is copied under the grant, validated as a supported still image, rehashed after copy, then the ledger commits. A failed commit removes the newly copied file. A process crash before commit can leave an unreferenced file, but never an imported record pointing at an incompletely committed new copy. Files referenced by a ledger are not deleted by cleanup tools. QR replacement/restore can retain unused files for recovery; no automatic evidence garbage collection in v1.

PhotosPicker Transferables are retained until nested copies finish. Folder leases survive the Bill preview/import session. No hardcoded external container access, App Group, VPN or pairing entitlement is used.

## Business invariants

- Import package ID and normalized physical slip code deduplicate; a name is not an identity. Exact image hashes prompt review, with an explicit separate-slip override.
- Signing requires an internal invoice. Exactly one assignment per order; its signed date and fee are immutable. Void events reverse, rather than erase, commission. Redelivery does not create another assignment automatically.
- Settlement values are absolute totals, not increments. Previous settlement events remain unchanged. Outcome, payment mode, commission, bank verification and reporting are independent.
- Company bank verification references a specific settlement. Changing the settlement requires a new check, even if the bank amount looks the same; reports become stale when order revision changes.
- Preparing a report verifies actual image files; the snapshot contains ordered evidence IDs and content. Sharing has no business side effect. Only an explicit acknowledgement references the current prepared snapshot.
- Cash held is collected cash minus unreversed handovers. Commission is never deducted. A correction cannot reduce collected cash below handed-over cash. Handover reversals preserve the original event and explanation.
- CSV exports all active signed assignments in the selected signed month. It escapes quotes/newlines and prefixes spreadsheet formula triggers, including after leading whitespace.

## Bill compatibility

The importer was grounded in the source bundle for Bill / Ảnh đơn hàng 3.2.0, not guessed from screenshots. It reads only:

- `sen-bill-v1`: `id`, `filename`, `imageKey`, `name`, `total`, `createdAt`, `createdMonth`; validates SHA-256(`sen-bill-v1:` + imageKey), filename marker and ID.
- `sen-orders-v3`: a root dictionary with metadata keys starting `_`; records keyed by their hex IDs, stored as JSON strings or dictionaries. It preserves cash, bank, delivered timestamp, notes and review flags; keeps original record JSON as an immutable source snapshot.

Legacy delivery time is not a signed-assignment time. Old reported/paid states are not bank confirmation or a new sent acknowledgement. One malformed legacy record stops that source to avoid silent partial financial migration. Missing images are surfaced individually. Fixture tests cover the verified schema; the owner's real private `orders.json` has not been supplied for native import acceptance.

## Backup format and restore

`.sweepbackup`: 8 ASCII bytes `SWEEP001`, an 8-byte big-endian manifest length, 32 raw SHA-256 bytes of the manifest, UTF-8 JSON manifest, then original image bytes in the manifest ledger's evidence order. Manifest version 1, ledger schema 1. Dates use Foundation Codable Date seconds since the 2001 reference date. Manifest is limited to 32 MiB; images to 80 MiB / 120 megapixels each. Streaming image payloads avoid a giant base64 JSON allocation.

Prepare validates the manifest hash, version, unique IDs/codes/filenames, money invariants, event references and evidence metadata; reads exactly each declared payload, verifies SHA-256 and image readability, and rejects trailing/truncated data. Paths must be basenames with generated UUID prefixes. The temporary staged set owns its cleanup.

Only after confirmation does restore first write a complete recovery archive of the current ledger, install checked immutable image files, and replace the SQLite snapshot transactionally. Existing filenames are reused only if hash and size match. Failure leaves the active DB intact; copied unreferenced files may remain. Recovery archives are exportable from Settings. The archive is integrity-checked, not an authenticated/encrypted transport format; users choose where to save customer data.

## Validation boundary

SwiftPM exercises business rules, SQLite and ImageIO on macOS. XCUITest uses an isolated DEBUG-only temporary database and a synthetic invoice. Release builds contain no fixture hook. Native tests cover navigation and selected flows, not real Zalo delivery, camera grants, iCloud file-provider behavior, company bank receipt or payroll acceptance. Those require device testing documented in TESTING.md.
