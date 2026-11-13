# Sweep 0.4.0 (7)

Changes requested during the delivery trial:

- Receive legacy `public.image` items as UIImage, URL or encoded bytes, in addition to file/data/object representations. Keep original supported JPEG/PNG/HEIC files; convert other ImageIO-readable formats, including the first frame of animated images, to a bounded PNG. Reject unreadable, oversized or invalid payloads.
- Choose from Photos in the app and directly in the Share Extension. Photo attachment controls now contain only **Chọn ảnh** and **Chụp ảnh**, with a stacked layout for accessibility text sizes.
- Choose and remove individual photos from each outgoing report. A transfer initially selects the invoice and transfer proof. Removing a photo from this selection preserves the original order evidence. The default transfer caption contains only the customer name and actual recorded transfer amount. Cash and deferred orders use appropriate captions.
- Open driving directions in Google Maps; use Google's web directions if the app is unavailable.
- Remove redundant explanations. Treat the labelled phone field beneath the salesperson as the customer's phone. Stop OCR header extraction at the item table and suppress old table-header contamination in delivery notes while preserving stored history.
- Scope commission count, fees, cash collected, cash handed over, transfer checks and handover history to the selected month in Vietnam time. An empty month shows zero. Select the new month on rollover without deleting history or forgiving cash still held from a previous month. Monthly cash is labelled **Chênh lệch thu − nộp** because remittance can include cash collected earlier.

Validation passed in [feature workflow 43525588962](https://github.com/Sentechtipsvn/Sweep/actions/runs/43525588962), source commit `b1ad9da4c92c160d6dca7d32b8f12029222f60c3`:

- 54 core tests: legacy image-provider data, JPEG/TIFF/BMP/GIF intake, animated first-frame import, selectable report snapshots, concise captions, OCR table boundaries, Google Maps destinations, Vietnam month boundaries and monthly financial totals.
- Release device build and embedded Share Extension build succeeded. Packager verified the code signatures and App Group declarations for both bundles.
- All 6 iPhone 16 / iOS 18.5 simulator tests passed: Bill OCR/import/persistence; Photos/camera controls at large text; empty-month figures and navigation; QR for an already-recorded transfer; selecting/removing/restoring report photos and short captions; legacy `public.image` UIImage intake through review, import and relaunch.
- Reviewed exported screenshots of intake, report photo selection and an empty monthly reconciliation. Verified the downloaded artifact digest, IPA CRC, version/build, bundle IDs, Google Maps scheme and signed entitlement blobs.

IPA SHA-256: `25b01fcd19cc66d84792e9a72d779a14a9526523eb2058477154f75cc92754ef`.

The IPA retains the embedded Share Extension and matching ad-hoc App Group entitlement metadata for AltStore to re-sign. Installation still needs AltStore provisioning. Real Zalo delivery and a physical camera must be checked on the phone; simulator fixtures do not reproduce the sender app or its installed signing environment.
