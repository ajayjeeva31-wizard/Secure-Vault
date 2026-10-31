import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as sha;

import 'models.dart';

/// PBKDF2/AES-GCM helpers used by the vault and TOTP enrollment.
class CryptoService {
  CryptoService() : _random = Random.secure();

  static const int minimumIterations = 310000;
  static const int maximumIterations = 2000000;
  static const int saltLength = 16;
  static const int keyLength = 32;
  static const int nonceLength = 12;
  static final List<int> _verifierContext =
      'SecureVault master-password verifier v1'.codeUnits;

  final Random _random;
  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: minimumIterations,
    bits: 256,
  );
  final AesGcm _aes = AesGcm.with256bits();

  List<int> _randomBytes(int count) =>
      List<int>.generate(count, (_) => _random.nextInt(256), growable: false);

  Future<SecretKey> deriveKey(String masterPassword, List<int> salt) {
    if (masterPassword.isEmpty) throw ArgumentError('Password must not be empty.');
    if (salt.length != saltLength) throw ArgumentError('Salt must be 16 bytes.');
    return _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(masterPassword)),
      nonce: salt,
    );
  }

  /// Create a persistable password verifier and return the key only to caller.
  /// The verifier is HMAC(key, fixed context), so the derived AES key itself
  /// is never saved. Keep the returned SecretKey only in memory while unlocked.
  Future<(PasswordVerifierRecord, SecretKey)> createPasswordVerifier(
    String masterPassword,
  ) async {
    if (masterPassword.runes.length < 12) {
      throw ArgumentError('Master password must be at least 12 characters.');
    }
    final salt = _randomBytes(saltLength);
    final key = await deriveKey(masterPassword, salt);
    final mac = await Hmac.sha256().calculateMac(
      _verifierContext,
      secretKey: key,
    );
    return (
      PasswordVerifierRecord(
        salt: base64Encode(salt),
        iterations: minimumIterations,
        verifier: base64Encode(mac.bytes),
      ),
      key,
    );
  }

  /// Verify a candidate against a persisted record, returning its session key
  /// on success. Unknown/weak KDF parameters are rejected rather than trusted.
  Future<SecretKey?> verifyMasterPassword(
    String candidate,
    PasswordVerifierRecord record,
  ) async {
    if (record.iterations < minimumIterations ||
        record.iterations > maximumIterations) {
      throw FormatException('Stored PBKDF2 iteration count is outside policy.');
    }
    final salt = base64Decode(record.salt);
    if (salt.length != saltLength) throw FormatException('Invalid salt length.');
    final key = await Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: record.iterations,
      bits: 256,
    ).deriveKey(secretKey: SecretKey(utf8.encode(candidate)), nonce: salt);
    final actual = (await Hmac.sha256().calculateMac(
      _verifierContext,
      secretKey: key,
    )).bytes;
    final expected = base64Decode(record.verifier);
    return _constantTimeEquals(actual, expected) ? key : null;
  }

  /// Encrypt arbitrary bytes using AES-256-GCM and a fresh random nonce.
  /// Supply authenticated context (AAD) to bind ciphertext to its purpose.
  Future<EncryptedEnvelope> encrypt(
    List<int> plaintext,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    final box = await _aes.encrypt(
      plaintext,
      secretKey: key,
      nonce: _randomBytes(nonceLength),
      aad: aad,
    );
    return EncryptedEnvelope(
      nonce: base64Encode(box.nonce),
      ciphertext: base64Encode(box.cipherText),
      mac: base64Encode(box.mac.bytes),
    );
  }

  Future<List<int>> decrypt(
    EncryptedEnvelope envelope,
    SecretKey key, {
    List<int> aad = const [],
  }) async {
    final nonce = base64Decode(envelope.nonce);
    if (nonce.length != nonceLength) throw FormatException('Invalid AES-GCM nonce.');
    final box = SecretBox(
      base64Decode(envelope.ciphertext),
      nonce: nonce,
      mac: Mac(base64Decode(envelope.mac)),
    );
    return _aes.decrypt(box, secretKey: key, aad: aad);
  }

  /// Encrypt the TOTP seed at rest with a distinct, purpose-bound AAD value.
  Future<EncryptedEnvelope> encryptTotpSecret(
    List<int> secret,
    SecretKey key,
  ) => encrypt(secret, key, aad: utf8.encode('securevault:totp-secret:v1'));

  Future<List<int>> decryptTotpSecret(
    EncryptedEnvelope envelope,
    SecretKey key,
  ) => decrypt(envelope, key, aad: utf8.encode('securevault:totp-secret:v1'));

  /// Create a random code hash record. Store the record, consume it once after
  /// a successful verification, and delete it atomically in the persistence
  /// layer. Do not store plaintext recovery codes after their one-time display.
  RecoveryCodeHash hashRecoveryCode(String code) {
    final salt = _randomBytes(saltLength);
    final normalized = utf8.encode(code.replaceAll('-', '').toUpperCase());
    final digest = sha.sha256.convert([...salt, ...normalized]).bytes;
    return RecoveryCodeHash(salt: base64Encode(salt), digest: base64Encode(digest));
  }

  /// Generate a display-once 160-bit recovery code in readable groups.
  String generateRecoveryCode() {
    final hex = _randomBytes(20)
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    return RegExp(r'.{1,4}').allMatches(hex).map((m) => m[0]!).join('-');
  }

  bool verifyRecoveryCode(String code, RecoveryCodeHash record) {
    final salt = base64Decode(record.salt);
    if (salt.length != saltLength) return false;
    final normalized = utf8.encode(code.replaceAll('-', '').toUpperCase());
    final actual = sha.sha256.convert([...salt, ...normalized]).bytes;
    return _constantTimeEquals(actual, base64Decode(record.digest));
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}
