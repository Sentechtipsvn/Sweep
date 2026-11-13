# Sweep 0.4.0 (7)

Changes requested during the delivery trial:

- Receive legacy `public.image` items as UIImage, URL or encoded bytes, in addition to file/data/object representations. Keep original supported JPEG/PNG/HEIC files; convert other ImageIO-readable formats, including the first frame of animated images, to a bounded PNG. Reject unreadable, oversized or invalid payloads.
- Choose from Photos in the app and directly in the Share Extension. Photo attachment controls now contain only **Chọn ảnh** and **Chụp ảnh**, with a stacked layout for accessibility text sizes.
- Choose and remove individual photos from each outgoing report. A transfer initially selects the invoice and transfer proof. Removing a photo from this selection preserves the original order evidence. The default transfer caption contains only the customer name and actual recorded transfer amount. Cash and deferred orders use appropriate captions.
- Open driving directions in Google Maps; use Google's web directions if the app is unavailable.
- Remove redundant explanations. Treat the labelled phone field beneath the salesperson as the customer's phone. Stop OCR header extraction at the item table and suppress old table-header contamination in delivery notes while preserving stored history.
- Scope commission count, fees, cash collected, cash handed over, transfer checks and handover history to the selected month in Vietnam time. An empty month shows zero. Select the new month on rollover without deleting history or forgiving cash still held from a previous month. Monthly cash is labelled **Chênh lệch thu − nộp** because remittance can include cash collected earlier.

Validation is tracked in the feature workflow. Coverage includes the legacy image-provider path, JPEG/TIFF/BMP/GIF intake, selectable report snapshots, concise captions, OCR table boundaries, Google Maps destinations, Vietnam month boundaries and monthly financial totals. Simulator checks cover intake, Bill compatibility, QR, report selection, monthly views and large text controls.

The IPA retains the embedded Share Extension and matching ad-hoc App Group entitlement metadata for AltStore to re-sign. Installation still needs AltStore provisioning. Real Zalo delivery and a physical camera must be checked on the phone; simulator fixtures do not reproduce the sender app or its installed signing environment.
