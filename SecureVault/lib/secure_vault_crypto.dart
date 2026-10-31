/// Cryptographic building blocks used by SecureVault.
///
/// This package contains no persistence or UI. Integrating stages must store
/// only the serialized credential record, encrypted TOTP envelope, and
/// recovery-code hashes; the master password and derived key must remain
/// transient and must never be logged.
export 'src/crypto/crypto_service.dart';
export 'src/crypto/models.dart';
export 'src/totp/totp.dart';
