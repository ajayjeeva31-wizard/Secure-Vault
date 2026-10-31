import 'package:secure_vault/src/app/vault_controller.dart';
import 'package:test/test.dart';

void main() {
  group('local password generator', () {
    final controller = VaultController();

    test('returns requested length with required character classes', () {
      final password = controller.generatePassword(length: 24, symbols: true);
      expect(password, hasLength(24));
      expect(password, matches(RegExp('[A-Z]')));
      expect(password, matches(RegExp('[a-z]')));
      expect(password, matches(RegExp(r'\d')));
      expect(password, matches(RegExp(r'[^A-Za-z0-9]')));
    });

    test('rejects lengths below the policy minimum', () {
      expect(() => controller.generatePassword(length: 8), throwsArgumentError);
    });
  });
}
