import 'dart:convert';

import 'package:secure_vault/secure_vault_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('CryptoService', () {
    final crypto = CryptoService();
    const password = 'correct horse battery staple';

    test('uses the required PBKDF2 work factor and verifies master password', () async {
      final (record, key) = await crypto.createPasswordVerifier(password);
      expect(record.iterations, greaterThanOrEqualTo(310000));
      expect(await crypto.verifyMasterPassword(password, record), isNotNull);
      expect(await crypto.verifyMasterPassword('incorrect password', record), isNull);
      expect(key, isNotNull);
    });

    test('PBKDF2 output matches a SHA-256 reference vector', () async {
      final key = await crypto.deriveKey('password', List<int>.generate(16, (i) => i));
      expect(
        (await key.extractBytes()).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join(),
        'e0f65a4bf6716253d2d10a7a4b18f35cd4baf31ff031a187cd0091674905482d',
      );
    });

    test('rejects master passwords shorter than 12 characters', () {
      expect(crypto.createPasswordVerifier('short'), throwsArgumentError);
    });

    test('rejects verifier records with weakened PBKDF2 settings', () async {
      final (record, _) = await crypto.createPasswordVerifier(password);
      expect(
        crypto.verifyMasterPassword(
          password,
          PasswordVerifierRecord(
            salt: record.salt,
            iterations: CryptoService.minimumIterations - 1,
            verifier: record.verifier,
          ),
        ),
        throwsFormatException,
      );
    });

    test('AES-256-GCM round trips and produces fresh nonces', () async {
      final (_, key) = await crypto.createPasswordVerifier(password);
      final clear = utf8.encode('vault record');
      final first = await crypto.encrypt(clear, key);
      final second = await crypto.encrypt(clear, key);
      expect(first.nonce, isNot(second.nonce));
      expect(await crypto.decrypt(first, key), clear);
      expect(await crypto.decrypt(second, key), clear);
      final changedCiphertext = base64Decode(first.ciphertext);
      changedCiphertext[0] ^= 1;
      final altered = EncryptedEnvelope(
        nonce: first.nonce,
        ciphertext: base64Encode(changedCiphertext),
        mac: first.mac,
      );
      expect(crypto.decrypt(altered, key), throwsA(anything));
    });

    test('encrypts TOTP seed with authenticated purpose binding', () async {
      final (_, key) = await crypto.createPasswordVerifier(password);
      final seed = List<int>.generate(20, (i) => i);
      final envelope = await crypto.encryptTotpSecret(seed, key);
      expect(await crypto.decryptTotpSecret(envelope, key), seed);
      expect(crypto.decrypt(envelope, key), throwsA(anything));
    });

    test('recovery codes are salted, case-insensitive, and verifiable', () {
      final code = crypto.generateRecoveryCode();
      expect(code.replaceAll('-', ''), hasLength(40));
      final first = crypto.hashRecoveryCode(code);
      final second = crypto.hashRecoveryCode(code);
      expect(first.salt, isNot(second.salt));
      expect(first.digest, isNot(second.digest));
      expect(crypto.verifyRecoveryCode(code.toLowerCase(), first), isTrue);
      expect(crypto.verifyRecoveryCode('wrong-code', first), isFalse);
    });
  });
}
