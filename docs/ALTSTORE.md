# Shared AltStore catalogue

Sweep 0.4.0 (7) is published alongside StikDebug VN 3.2.9 (9) in the existing repository catalogue:

https://raw.githubusercontent.com/Sentechtipsvn/Stikdebug-VN/main/altstore/altstore.json

The legacy raw URL under dammeiosvn resolves to the same two-app catalogue. The old StikDebug release attachment at releases/latest/download/altstore.json is a StikDebug release snapshot; use the canonical raw URL above for the shared catalogue.

The Sweep listing uses the exact IPA previously delivered and tested, hosted at an immutable commit:

https://raw.githubusercontent.com/Sentechtipsvn/Sweep/a8f31f71fd5b12040a321c5f1c748f75c2b4109c/Releases/0.4.0/Sweep-0.4.0-AltStore.ipa

- App ID: com.sentechtipsvn.sweep; iOS 17.0 minimum; version 0.4.0; build 7.
- Bytes: 1296709.
- SHA-256: 25b01fcd19cc66d84792e9a72d779a14a9526523eb2058477154f75cc92754ef.
- appPermissions lists the App Group entitlement and the exact three camera/Photos privacy descriptions in the IPA.
- Source publication commit: Sentechtipsvn/Stikdebug-VN@4306e18895e0e77c3ad47fd2c8daa4bd03e914c6.
- Validation: downloaded the public IPA and matched its SHA-256; checked versions/build/minimum OS/size/privacy against Info.plist; verified source/app icons and fetched both canonical and legacy raw feeds with both app entries. Existing StikDebug app data is unchanged.

Keep the Share Extension when AltStore signs and installs the app. Distribution did not rebuild or change the tested application code.
