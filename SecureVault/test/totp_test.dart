import 'package:secure_vault/secure_vault_crypto.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 6238 TOTP', () {
    final totp = Totp();
    final secret = '12345678901234567890'.codeUnits;

    test('matches RFC SHA-1 six-digit vector at Unix time 59', () {
      expect(totp.codeAt(secret, DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true)), '287082');
    });

    test('accepts current step and one step on either side', () {
      final now = DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true);
      expect(totp.verify(totp.codeAt(secret, now), secret, now), isTrue);
      expect(totp.verify(totp.codeAt(secret, now.subtract(const Duration(seconds: 30))), secret, now), isTrue);
      expect(totp.verify(totp.codeAt(secret, now.add(const Duration(seconds: 30))), secret, now), isTrue);
    });

    test('rejects malformed codes and codes beyond the drift window', () {
      final now = DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true);
      expect(totp.verify('12345', secret, now), isFalse);
      expect(totp.verify('abcdef', secret, now), isFalse);
      expect(totp.verify(totp.codeAt(secret, now.add(const Duration(seconds: 60))), secret, now), isFalse);
    });

    test('Base32 round trips and provisioning URI uses otpauth format', () {
      final seed = totp.generateSecret();
      expect(totp.decodeBase32(totp.encodeBase32(seed)), seed);
      final uri = totp.provisioningUri(secret: seed, accountName: 'user@example.com', issuer: 'SecureVault');
      expect(uri.scheme, 'otpauth');
      expect(uri.host, 'totp');
      expect(uri.queryParameters['secret'], totp.encodeBase32(seed));
    });
  });
}
