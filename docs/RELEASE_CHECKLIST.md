# Release checklist

The source is implemented, but the current delivery is not a signed or
store-ready binary. Complete every item for the intended Android/iOS targets.

## Build and test

- [x] Generate Android/iOS Flutter runner projects. The generated Android
  application ID is temporary; set the publisher-owned reverse-domain ID.
- [x] Run `flutter pub get`, `flutter analyze`, and unit tests with Flutter
  3.47.9 / Dart 3.13.7. The Android build was attempted but Gradle download
  failed because Java rejected the environment TLS certificate chain.
- [ ] Re-run validation on the declared minimum Flutter/Dart version after
  selecting the supported minimum for the published release.
- [ ] Build Android release with Java 17; inspect the final APK/AAB and sign it
  with a production upload key.
- [ ] Build and archive iOS on macOS/Xcode; configure signing, provisioning,
  and the App Store bundle identifier.
- [ ] Test first-run setup, QR scan, clock drift, lockouts, recovery code
  single-use, password changes, app restarts, encrypted backups, corrupt
  storage, and 1-minute background lock on real devices.
- [ ] Verify Android screenshot prevention and iOS background/screenshot
  behavior on the target OS versions; document platform differences honestly.
- [ ] Test restore after reinstall and on a second device with the old backup
  password. Confirm wrong-password/tampered backups never replace entries.

## Security and privacy

- [ ] Commission an independent mobile application and cryptography review.
- [ ] Review all resolved package versions and transitive licenses; include
  required third-party notices in the app and distribution materials.
- [ ] Review Android backup/restore behavior so platform cloud backup does not
  silently copy secure-storage metadata or encrypted record files contrary to
  the product's local-only promise.
- [ ] Add app-store privacy disclosures and a privacy policy that matches the
  shipping build. This source sends no app data to a server.
- [ ] Decide how users can request support without being asked to reveal
  passwords, recovery codes, vault entries, or backups.
- [ ] Configure app icon, screenshots, store description, support URL, privacy
  URL, age rating, pricing, and geographic availability.
- [ ] Add crash reporting only if it cannot capture credentials or vault data;
  verify privacy disclosures before enabling it.
- [ ] Complete accessibility, localization, and usability review.

## Product decisions still needed from the publisher

- [ ] Final company/developer name, support email, and legal/privacy URLs.
- [ ] Product name/trademark clearance and store listing copy.
- [ ] Signing keys and account access for the chosen stores.
- [ ] Supported OS/device matrix and paid/free business model.
- [ ] Whether a separate external backup-password workflow is acceptable to
  customers; current backups require the export-time master password.
