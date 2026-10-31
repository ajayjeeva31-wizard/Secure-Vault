import 'dart:convert';

/// Persistable password verifier parameters. It deliberately contains no key.
class PasswordVerifierRecord {
  const PasswordVerifierRecord({
    required this.salt,
    required this.iterations,
    required this.verifier,
  });

  final String salt; // base64, 16 random bytes
  final int iterations;
  final String verifier; // base64 HMAC output, never the derived key

  Map<String, Object> toJson() => {
        'salt': salt,
        'iterations': iterations,
        'verifier': verifier,
      };

  factory PasswordVerifierRecord.fromJson(Map<String, dynamic> json) =>
      PasswordVerifierRecord(
        salt: json['salt'] as String,
        iterations: json['iterations'] as int,
        verifier: json['verifier'] as String,
      );
}

/// AES-GCM envelope. Each encryption gets its own random 96-bit nonce.
class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String nonce; // base64
  final String ciphertext; // base64
  final String mac; // base64, GCM authentication tag

  Map<String, Object> toJson() => {
        'nonce': nonce,
        'ciphertext': ciphertext,
        'mac': mac,
      };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) =>
      EncryptedEnvelope(
        nonce: json['nonce'] as String,
        ciphertext: json['ciphertext'] as String,
        mac: json['mac'] as String,
      );
}

/// Salted one-way verifier for a single-use recovery code.
class RecoveryCodeHash {
  const RecoveryCodeHash({required this.salt, required this.digest});

  final String salt; // base64, independently random for each code
  final String digest; // base64 SHA-256(salt || normalized code)

  Map<String, Object> toJson() => {'salt': salt, 'digest': digest};

  factory RecoveryCodeHash.fromJson(Map<String, dynamic> json) =>
      RecoveryCodeHash(
        salt: json['salt'] as String,
        digest: json['digest'] as String,
      );
}

String encodeJson(Map<String, Object> json) => jsonEncode(json);
