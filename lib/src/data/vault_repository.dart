import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../crypto/models.dart';
/// Keeps only verifier/configuration in Keychain/Keystore. Every vault record
/// stays encrypted in the app-support file; metadata never includes titles or
/// usernames. Generation switching makes password changes recoverable if the
/// process stops midway through writing new encrypted data.
class VaultRepository {
  VaultRepository({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  static const _activeKey = 'securevault.active_generation';
  static const _attemptKey = 'securevault.auth_state';
  static const _logKey = 'securevault.security_log';

  Future<String?> get activeGeneration => _secure.read(key: _activeKey);

  Future<PasswordVerifierRecord?> readVerifier(String generation) async {
    final raw = await _secure.read(key: 'securevault.verifier.$generation');
    return raw == null
        ? null
        : PasswordVerifierRecord.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<EncryptedEnvelope?> readTotp(String generation) async {
    final raw = await _secure.read(key: 'securevault.totp.$generation');
    return raw == null
        ? null
        : EncryptedEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<List<RecoveryCodeHash>> readRecoveryHashes(String generation) async {
    final raw = await _secure.read(key: 'securevault.recovery.$generation');
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .map((item) => RecoveryCodeHash.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> writeRecoveryHashes(
    String generation,
    List<RecoveryCodeHash> hashes,
  ) => _secure.write(
        key: 'securevault.recovery.$generation',
        value: jsonEncode(hashes.map((item) => item.toJson()).toList()),
      );

  /// Write all generation data and encrypted records before switching active.
  Future<void> installGeneration({
    required String generation,
    required PasswordVerifierRecord verifier,
    required EncryptedEnvelope totp,
    required List<RecoveryCodeHash> recoveryHashes,
    required List<({String id, EncryptedEnvelope envelope})> records,
  }) async {
    await _writeRecords(generation, records);
    await _secure.write(
      key: 'securevault.verifier.$generation',
      value: jsonEncode(verifier.toJson()),
    );
    await _secure.write(
      key: 'securevault.totp.$generation',
      value: jsonEncode(totp.toJson()),
    );
    await _secure.write(
      key: 'securevault.recovery.$generation',
      value: jsonEncode(recoveryHashes.map((item) => item.toJson()).toList()),
    );
    // The single pointer write is the commit point for setup/password change.
    await _secure.write(key: _activeKey, value: generation);
  }

  Future<List<({String id, EncryptedEnvelope envelope})>> readRecords(
    String generation,
  ) async {
    final file = await _vaultFile(generation);
    final previous = File('${file.path}.bak');
    if (!await file.exists() && await previous.exists()) {
      await previous.rename(file.path);
    } else if (await file.exists() && await previous.exists()) {
      await previous.delete();
    }
    if (!await file.exists()) return [];
    final decoded = jsonDecode(await file.readAsString()) as List<dynamic>;
    return decoded.map((item) {
      final map = item as Map<String, dynamic>;
      return (
        id: map['id'] as String,
        envelope: EncryptedEnvelope.fromJson(map['encrypted'] as Map<String, dynamic>),
      );
    }).toList();
  }

  Future<void> saveRecords(
    String generation,
    List<({String id, EncryptedEnvelope envelope})> records,
  ) => _writeRecords(generation, records);

  Future<void> deleteGeneration(String generation) async {
    await _secure.delete(key: 'securevault.verifier.$generation');
    await _secure.delete(key: 'securevault.totp.$generation');
    await _secure.delete(key: 'securevault.recovery.$generation');
    final file = await _vaultFile(generation);
    if (await file.exists()) await file.delete();
  }

  Future<List<Map<String, dynamic>>> readSecurityLog() async {
    final raw = await _secure.read(key: _logKey);
    if (raw == null) return [];
    return (jsonDecode(raw) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .toList()
        .reversed
        .toList();
  }

  Future<void> appendSecurityEvent(String event) async {
    final raw = await _secure.read(key: _logKey);
    final items = raw == null
        ? <Map<String, String>>[]
        : (jsonDecode(raw) as List<dynamic>)
            .map((item) => Map<String, String>.from(item as Map))
            .toList();
    items.add({'event': event, 'time': DateTime.now().toUtc().toIso8601String()});
    if (items.length > 100) items.removeRange(0, items.length - 100);
    await _secure.write(key: _logKey, value: jsonEncode(items));
  }

  Future<({int failures, int lockouts, DateTime? lockedUntil})>
      readAuthState() async {
    final raw = await _secure.read(key: _attemptKey);
    if (raw == null) return (failures: 0, lockouts: 0, lockedUntil: null);
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return (
      failures: data['failures'] as int? ?? 0,
      lockouts: data['lockouts'] as int? ?? 0,
      lockedUntil: data['lockedUntil'] == null
          ? null
          : DateTime.parse(data['lockedUntil'] as String),
    );
  }

  Future<void> writeAuthState({
    required int failures,
    required int lockouts,
    required DateTime? lockedUntil,
  }) => _secure.write(
        key: _attemptKey,
        value: jsonEncode({
          'failures': failures,
          'lockouts': lockouts,
          'lockedUntil': lockedUntil?.toUtc().toIso8601String(),
        }),
      );

  Future<void> _writeRecords(
    String generation,
    List<({String id, EncryptedEnvelope envelope})> records,
  ) async {
    final file = await _vaultFile(generation);
    final temp = File('${file.path}.tmp');
    final previous = File('${file.path}.bak');
    final contents = jsonEncode(records
        .map((row) => {'id': row.id, 'encrypted': row.envelope.toJson()})
        .toList());
    await temp.writeAsString(contents, flush: true);
    if (await previous.exists()) await previous.delete();
    if (await file.exists()) await file.rename(previous.path);
    try {
      await temp.rename(file.path);
      if (await previous.exists()) await previous.delete();
    } catch (_) {
      if (!await file.exists() && await previous.exists()) {
        await previous.rename(file.path);
      }
      rethrow;
    }
  }

  Future<File> _vaultFile(String generation) async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}vault_$generation.json');
  }
}
