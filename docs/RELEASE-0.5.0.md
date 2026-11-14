# Sweep 0.5.0 (8)

Implementation of the approved 14 November design and supplemental instructions.

- Signed intake: Signed accepts a slip; Skip accepts nothing. A signature confirmed in the Share Extension is retained in its atomic inbox manifest and is not requested again in the main app. Existing queued entries without a signature still ask. No private extension-to-app launch API is used.
- Incoming supported ImageIO formats, including primary still frames of animations, are normalized to JPEG at up to 2560 px / 82% quality. Orientation is applied and pixels are drawn into a new sRGB bitmap; source GPS/EXIF/IPTC/XMP is not copied. The source outside Sweep is unchanged. Older stored originals stay intact; outgoing copies are also normalized.
- Three delivery choices: cash, transfer and freight. Cash full requires no photo report; partial cash is committed before opening a QR for the remainder. Closing a QR does not record money. Transfer requires explicit actual-payment confirmation.
- Transfer-now reports require priced invoice + transfer proof. Later reports allow only the signed warehouse slip. Freight requires carrier-signed slip + dispatched goods. All retain one commission per signed assignment. Driver-facing company bank reconciliation is removed.
- Report images can be selected/removed without deleting originals. Draft text/selection persist. Irrelevant address, contact and bank-verification changes do not mark a sent report unsent.
- History replaces Reconciliation. Monthly commission/receipts/remittances are separate from current cash held, which carries across months. Cash uses dated snapshot deltas so a later bank receipt does not move an earlier cash receipt into a different month.
- Four-column tools grid uses seven bundled colored SVG assets; accessibility sizes use two columns. Existing photo tools remain. Locations support manual address, GPS and map-center pin; navigation uses Google Maps. Contacts support aliases from NV bán hàng and supplied HTTPS Zalo profile links. The invoice phone remains the customer's number.
- Documents/Backups and Exports are visible in Files. SQLite and evidence remain in Application Support. Deleting the app still deletes its container.
- Cleanup and Reset require a full external backup, read back with evidence hash validation before deletion. Reset also backs up queued shared slips in a sibling `.pending` folder and only deletes those captured before backup. New concurrent shares remain queued. Reset removes app ledger/evidence/settings/contacts/places and does not delete Photos or Zalo data. A reset is never run automatically on update.
- Ledger schema 1 migrates to schema 2 with a readable v1 pre-upgrade backup, preserving money/commission and flagging unclassified old deliveries for review. New v2 backups cannot be silently opened by the old app; the new app restores both v1 and v2.
- New app icon uses the supplied delivery character, contained in a square without cutting the artwork.

Validation results and distribution commit are appended after CI. Physical Zalo delivery, camera, GPS and installed Google Maps/Zalo still need device verification; simulator checks do not establish these physical integration results.
