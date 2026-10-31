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
- Android API 24+ and iOS 15+ for the generated platform targets and selected
  secure-storage and file-picker packages. iOS builds require macOS and Xcode.
- Java 17 for Android builds.

The delivery includes generated Android and iOS runner projects. Their current
Android application ID is `com.securevault.secure_vault`; change it to the
publisher's owned reverse-domain ID before creating a store listing or signing
a release. iOS builds require macOS and Xcode.

## Install and validate

The project was checked with Flutter 3.47.9 / Dart 3.13.7. For this workspace,
the verified Flutter SDK is at `work/toolchains/flutter` relative to the
workspace root. From `outputs/SecureVault`, add it to the current PowerShell
session and verify the version:

```powershell
$flutterBin = (Resolve-Path '..\..\work\toolchains\flutter\bin').Path
$env:Path = "$flutterBin;$env:Path"
flutter --version
```

In VS Code, open this project folder and choose that SDK folder when prompted
by the Flutter extension. For a copy outside this workspace, install Flutter
from the official Flutter installation guide and point VS Code to that SDK.
Then run from the project directory:

```powershell
flutter pub get
flutter analyze
flutter test test/crypto_service_test.dart
flutter test test/totp_test.dart
flutter test test/vault_controller_test.dart
flutter run
```

The tests cover PBKDF2 policy and a reference vector, password verification,
AES-GCM round-trips/tamper detection/fresh nonces, encrypted TOTP data, RFC
6238 vectors and drift, Base32 enrollment, salted recovery-code hashing, and
password generation. Run each file explicitly so all suites execute with
Flutter's test runner.

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

This is a feature-complete source project, not a certified password manager or
a released store binary. See [the threat model](docs/THREAT_MODEL.md) and
[release checklist](docs/RELEASE_CHECKLIST.md) before distributing it. Unit
tests and static analysis pass. An Android build was attempted on Windows but
could not download Gradle because the Java runtime rejected the environment's
TLS certificate chain; certificate validation was kept enabled. iOS builds
cannot run on Windows. Before charging users, finish platform builds and device
tests, review dependency licenses, commission an independent security review,
provide real privacy/support policies, and configure production signing.

Biometric-only unlock is intentionally omitted: meeting that convenience flow
would require persisting or hardware-wrapping a key that the supplied design
explicitly says must never be stored. The strict in-memory-key rule is kept.
