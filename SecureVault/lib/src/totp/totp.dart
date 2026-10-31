import 'dart:math';

import 'package:crypto/crypto.dart';

/// RFC 6238 TOTP (SHA-1, 6 digits, 30 seconds), compatible with Google
/// Authenticator defaults. Secret provisioning/encryption is handled by the
/// crypto service; this class accepts raw seed bytes only in memory.
class Totp {
  Totp() : _random = Random.secure();

  final Random _random;
  static const int periodSeconds = 30;
  static const int digits = 6;

  List<int> generateSecret({int length = 20}) {
    if (length < 16) throw ArgumentError('TOTP secret must be at least 128 bits.');
    return List<int>.generate(length, (_) => _random.nextInt(256), growable: false);
  }

  String codeAt(List<int> secret, DateTime time) {
    final counter = time.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ periodSeconds;
    return _codeForCounter(secret, counter);
  }

  /// Allows current time step and exactly one adjacent step either side.
  bool verify(String code, List<int> secret, DateTime now) {
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
    final current = now.toUtc().millisecondsSinceEpoch ~/ 1000 ~/ periodSeconds;
    var matches = 0;
    for (var drift = -1; drift <= 1; drift++) {
      if (_constantTimeStringEquals(code, _codeForCounter(secret, current + drift))) {
        matches = 1;
      }
    }
    return matches == 1;
  }

  String _codeForCounter(List<int> secret, int counter) {
    final bytes = List<int>.generate(8, (i) => (counter >> ((7 - i) * 8)) & 0xff);
    final digest = Hmac(sha1, secret).convert(bytes).bytes;
    final offset = digest.last & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    return (binary % 1000000).toString().padLeft(digits, '0');
  }

  bool _constantTimeStringEquals(String a, String b) {
    var diff = a.length ^ b.length;
    final maxLength = max(a.length, b.length);
    for (var i = 0; i < maxLength; i++) {
      diff |= (i < a.length ? a.codeUnitAt(i) : 0) ^
          (i < b.length ? b.codeUnitAt(i) : 0);
    }
    return diff == 0;
  }

  String encodeBase32(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 31]);
      }
    }
    if (bits > 0) out.write(alphabet[(buffer << (5 - bits)) & 31]);
    return out.toString();
  }

  List<int> decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final normalized = input.toUpperCase().replaceAll('=', '').replaceAll(' ', '');
    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final char in normalized.codeUnits) {
      final value = alphabet.indexOf(String.fromCharCode(char));
      if (value < 0) throw FormatException('Invalid Base32 character.');
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return out;
  }

  /// URI for QR rendering in a later UI stage. Caller must keep seed transient.
  Uri provisioningUri({
    required List<int> secret,
    required String accountName,
    required String issuer,
  }) {
    final label = '$issuer:$accountName';
    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      path: '/${Uri.encodeComponent(label)}',
      queryParameters: {
        'secret': encodeBase32(secret),
        'issuer': issuer,
        'algorithm': 'SHA1',
        'digits': '$digits',
        'period': '$periodSeconds',
      },
    );
  }
}
