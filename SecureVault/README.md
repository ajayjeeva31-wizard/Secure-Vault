# SecureVault

SecureVault is an offline-first Flutter password manager. It has a dark Material
3 interface, a two-step master-password/TOTP unlock, encrypted vault entries,
one-time recovery codes, encrypted backups, a password generator, and local
security controls. There is no account server, telemetry, cloud sync, or
password-reset service.

## Included

- New-vault enrollment with a 12-character minimum master password, strength
  meter, Google Authenticator compatible QR/setup key, and 6-digit setup check.
- PBKDF2-HMAC-SHA256 with a fresh 16-byte salt and 310,000 rounds to derive a
  256-bit key; a keyed verifier is saved, never the master password or key.
- Per-entry AES-256-GCM with fresh random 12-byte nonces and entry-bound
  authenticated data. The encrypted entry file contains opaque IDs and
  ciphertext only.
- TOTP seed encrypted with AES-GCM and stored in platform secure storage.
  RFC 6238 SHA-1, six-digit, 30-second codes accept one neighboring time step.
- Eight independently salted one-time recovery codes, shown once and hashed
  before storage.
- Login lockout after five failed attempts, starting at five minutes and
  increasing with repeated lockouts.
- Add, inspect, edit, delete, favorite, search, category-filter, and sort
  credential entries. Password fields are hidden in the detail view by default.
- On-device password generation (12–64 characters; letters and numbers always
  included, symbols optional), with clipboard clearing after 20 seconds.
- One-minute background auto-lock and best-effort Android/iOS screenshot
  protection while the vault is unlocked.
- Master-password change that re-encrypts every entry and the TOTP secret,
  with generation switching so the old configuration remains active until the
  new encrypted data is written.
- Encrypted `.svault` export/import. Import asks for the password that created
  the backup and replaces entries only after confirmation. Authenticator and
  recovery settings remain those of the receiving vault.
- Recovery-code regeneration and a local log of authentication/security events.

## Requirements and targets

- Flutter 3.38.1+ / Dart 3.10+.
- Android API 24+ and iOS 14+ for the selected secure-storage and file-picker
  packages. iOS builds require macOS and Xcode.
- Java 17 for Android builds.

The delivery contains Dart sources, tests, and package configuration. It does
not contain generated `android/` or `ios/` runner projects because Flutter is
not installed in the authoring environment. Create a fresh Flutter shell with
Android and iOS targets in a sibling directory, then copy this delivery's
`lib/`, `test/`, `pubspec.yaml`, and `analysis_options.yaml` into that shell,
keeping the generated native folders and `.metadata`. For example:

```powershell
flutter create --platforms=android,ios --org com.yourcompany securevault_app
```

Replace `com.yourcompany` with your own reverse-domain organization before
building a release. The current dependencies require Flutter 3.38/Dart 3.10,
Android API 24+, iOS 14+, and Java 17. `share_plus` also documents current
Android Gradle/Kotlin and iOS build requirements; use the generated Flutter
toolchain files and resolve any platform-specific plugin setup before signing.

## Install and validate

From the project directory:

```powershell
flutter pub get
flutter test
flutter analyze
flutter run
```

The test suite covers PBKDF2 policy and password verification, AES-GCM
round-trips and tamper detection, TOTP RFC vectors and drift, Base32 enrollment,
recovery-code hashing, and password generation. Those commands still need to
be run with a configured Flutter SDK and Android/iOS device or simulator.

## Data and recovery

The password verifier, encrypted TOTP envelope, recovery hashes, lockout
counter, and security log are kept in platform secure storage. Encrypted
credential records are kept under the app support directory. The master
password and derived key are held in memory only for an unlocked session. Dart
cannot promise physical zeroization of prior memory contents; the app drops its
references when it locks.

An exported backup contains credential entries only. It is encrypted with the
key derived from the password used when the backup was created. To import onto
a different installation, enroll that installation first, then provide the
old backup password. Changing a password does not rewrite backups already
exported; create a fresh backup after changing it.

## Security and release boundaries

This is a complete feature implementation, not a certified password manager or
a released store binary. See [the threat model](docs/THREAT_MODEL.md) and
[release checklist](docs/RELEASE_CHECKLIST.md) before distributing it. In
particular, run the tests and platform builds, review dependency licenses,
commission an independent security review, provide a real privacy/support
policy, configure signing, and perform device testing before charging users.

Biometric-only unlock is intentionally omitted: meeting that convenience flow
would require persisting or hardware-wrapping a key that the supplied design
explicitly says must never be stored. The strict in-memory-key rule is kept.
