import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/crypto_service.dart';
import '../crypto/models.dart';
import '../data/vault_entry.dart';
import '../data/vault_repository.dart';
import '../totp/totp.dart';

enum VaultState { loading, uninitialized, settingUp, recoveryPending, locked, unlocked }

class VaultController extends ChangeNotifier {
  VaultController({VaultRepository? repository, CryptoService? crypto, Totp? totp})
      : _repository = repository ?? VaultRepository(),
        _crypto = crypto ?? CryptoService(),
        _totp = totp ?? Totp();

  final VaultRepository _repository;
  final CryptoService _crypto;
  final Totp _totp;
  final Random _random = Random.secure();

  VaultState state = VaultState.loading;
  List<VaultEntry> entries = [];
  SecretKey? _sessionKey;
  List<int>? _totpSecret;
  String? _generation;
  PasswordVerifierRecord? _pendingVerifier;
  SecretKey? _pendingKey;
  List<int>? _pendingTotp;
  bool _totpConfirmed = false;
  List<String> _pendingRecoveryCodes = [];
  List<RecoveryCodeHash> _recoveryHashes = [];
  int failedAttempts = 0;
  int lockouts = 0;
  DateTime? lockedUntil;
  List<Map<String, dynamic>> securityLog = [];

  bool get configured => state != VaultState.uninitialized;
  String? get setupUri => _pendingTotp == null
      ? null
      : _totp
          .provisioningUri(
            secret: _pendingTotp!,
            accountName: 'SecureVault user',
            issuer: 'SecureVault',
          )
          .toString();
  List<String> get recoveryCodes => List.unmodifiable(_pendingRecoveryCodes);
  bool get isLockedOut => lockedUntil != null && lockedUntil!.isAfter(DateTime.now());

  Future<void> initialize() async {
    _generation = await _repository.activeGeneration;
    state = _generation == null ? VaultState.uninitialized : VaultState.locked;
    await _loadAuthState();
    notifyListeners();
  }

  Future<void> beginSetup(String masterPassword) async {
    if (state != VaultState.uninitialized) throw StateError('Vault is already configured.');
    final (verifier, key) = await _crypto.createPasswordVerifier(masterPassword);
    _pendingVerifier = verifier;
    _pendingKey = key;
    _pendingTotp = _totp.generateSecret();
    _totpConfirmed = false;
    state = VaultState.settingUp;
    notifyListeners();
  }

  bool confirmSetupCode(String code) {
    final secret = _pendingTotp;
    if (secret == null || !_totp.verify(code, secret, DateTime.now())) return false;
    _totpConfirmed = true;
    _pendingRecoveryCodes = List<String>.generate(8, (_) => _crypto.generateRecoveryCode());
    _recoveryHashes = _pendingRecoveryCodes.map(_crypto.hashRecoveryCode).toList();
    state = VaultState.recoveryPending;
    notifyListeners();
    return true;
  }

  Future<void> acknowledgeRecoveryCodes() async {
    if (state != VaultState.recoveryPending || !_totpConfirmed) {
      throw StateError('TOTP setup must be confirmed first.');
    }
    final generation = _newId();
    final key = _pendingKey!;
    final encryptedTotp = await _crypto.encryptTotpSecret(_pendingTotp!, key);
    await _repository.installGeneration(
      generation: generation,
      verifier: _pendingVerifier!,
      totp: encryptedTotp,
      recoveryHashes: _recoveryHashes,
      records: [],
    );
    _generation = generation;
    _sessionKey = key;
    _totpSecret = _pendingTotp;
    _pendingVerifier = null;
    _pendingKey = null;
    _pendingTotp = null;
    _pendingRecoveryCodes = [];
    _recoveryHashes = [];
    state = VaultState.unlocked;
    await _recordEvent('Account setup completed');
    notifyListeners();
  }

  Future<bool> unlock(String password, String code) async {
    if (_generation == null || isLockedOut) return false;
    final verifier = await _repository.readVerifier(_generation!);
    if (verifier == null) return false;
    final key = await _crypto.verifyMasterPassword(password, verifier);
    if (key == null) return _failedLogin();

    final encryptedTotp = await _repository.readTotp(_generation!);
    if (encryptedTotp == null) return _failedLogin();
    final secret = await _crypto.decryptTotpSecret(encryptedTotp, key);
    final totpOkay = _totp.verify(code, secret, DateTime.now());
    var recoveryUsed = false;
    if (!totpOkay) {
      final hashes = await _repository.readRecoveryHashes(_generation!);
      final match = hashes.indexWhere((hash) => _crypto.verifyRecoveryCode(code, hash));
      if (match < 0) return _failedLogin();
      hashes.removeAt(match);
      await _repository.writeRecoveryHashes(_generation!, hashes);
      recoveryUsed = true;
    }

    final rows = await _repository.readRecords(_generation!);
    final opened = <VaultEntry>[];
    for (final row in rows) {
      final clear = await _crypto.decrypt(row.envelope, key, aad: _recordAad(row.id));
      opened.add(VaultEntry.fromJson(jsonDecode(utf8.decode(clear)) as Map<String, dynamic>));
    }
    entries = opened;
    _sessionKey = key;
    _totpSecret = secret;
    failedAttempts = 0;
    lockouts = 0;
    lockedUntil = null;
    await _repository.writeAuthState(failures: 0, lockouts: 0, lockedUntil: null);
    await _recordEvent(
      recoveryUsed ? 'Successful login with recovery code' : 'Successful login with TOTP',
    );
    state = VaultState.unlocked;
    notifyListeners();
    return true;
  }

  Future<bool> _failedLogin() async {
    failedAttempts++;
    if (failedAttempts >= 5) {
      lockouts++;
      failedAttempts = 0;
      final minutes = min(24 * 60, 5 * (1 << min(12, lockouts - 1)));
      lockedUntil = DateTime.now().add(Duration(minutes: minutes));
    }
    await _repository.writeAuthState(
      failures: failedAttempts,
      lockouts: lockouts,
      lockedUntil: lockedUntil,
    );
    await _recordEvent('Failed login attempt');
    notifyListeners();
    return false;
  }

  Future<void> _loadAuthState() async {
    final saved = await _repository.readAuthState();
    failedAttempts = saved.failures;
    lockouts = saved.lockouts;
    lockedUntil = saved.lockedUntil;
    if (lockedUntil != null && !lockedUntil!.isAfter(DateTime.now())) {
      lockedUntil = null;
      await _repository.writeAuthState(
        failures: failedAttempts,
        lockouts: lockouts,
        lockedUntil: null,
      );
    }
  }

  Future<void> addOrUpdate(VaultEntry entry) async {
    _requireUnlocked();
    final previous = entries;
    final index = entries.indexWhere((item) => item.id == entry.id);
    if (index < 0) {
      entries = [...entries, entry];
    } else {
      final updated = [...entries];
      updated[index] = entry;
      entries = updated;
    }
    try {
      await _persistEntries();
    } catch (_) {
      entries = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    _requireUnlocked();
    final previous = entries;
    entries = entries.where((entry) => entry.id != id).toList();
    try {
      await _persistEntries();
    } catch (_) {
      entries = previous;
      rethrow;
    }
    notifyListeners();
  }

  Future<void> toggleFavorite(VaultEntry entry) => addOrUpdate(
        VaultEntry(
          id: entry.id,
          title: entry.title,
          site: entry.site,
          username: entry.username,
          password: entry.password,
          notes: entry.notes,
          category: entry.category,
          favorite: !entry.favorite,
          updatedAt: DateTime.now().toUtc(),
        ),
      );

  Future<void> _persistEntries() async {
    final key = _sessionKey!;
    final rows = <({String id, EncryptedEnvelope envelope})>[];
    for (final entry in entries) {
      final envelope = await _crypto.encrypt(
        utf8.encode(jsonEncode(entry.toJson())),
        key,
        aad: _recordAad(entry.id),
      );
      rows.add((id: entry.id, envelope: envelope));
    }
    await _repository.saveRecords(_generation!, rows);
  }

  Future<void> changeMasterPassword(String newPassword) async {
    _requireUnlocked();
    final (newVerifier, newKey) = await _crypto.createPasswordVerifier(newPassword);
    final newGeneration = _newId();
    final encryptedTotp = await _crypto.encryptTotpSecret(_totpSecret!, newKey);
    final rows = <({String id, EncryptedEnvelope envelope})>[];
    for (final entry in entries) {
      rows.add((
        id: entry.id,
        envelope: await _crypto.encrypt(
          utf8.encode(jsonEncode(entry.toJson())),
          newKey,
          aad: _recordAad(entry.id),
        ),
      ));
    }
    final oldGeneration = _generation!;
    await _repository.installGeneration(
      generation: newGeneration,
      verifier: newVerifier,
      totp: encryptedTotp,
      recoveryHashes: await _repository.readRecoveryHashes(oldGeneration),
      records: rows,
    );
    _generation = newGeneration;
    _sessionKey = newKey;
    try {
      await _repository.deleteGeneration(oldGeneration);
    } catch (_) {
      // The new generation is already committed; orphan cleanup is best-effort.
    }
    await _recordEvent('Master password changed');
    notifyListeners();
  }

  Future<List<String>> regenerateRecoveryCodes() async {
    _requireUnlocked();
    final codes = List<String>.generate(8, (_) => _crypto.generateRecoveryCode());
    final hashes = codes.map(_crypto.hashRecoveryCode).toList();
    await _repository.writeRecoveryHashes(_generation!, hashes);
    await _recordEvent('Recovery codes regenerated');
    notifyListeners();
    return codes;
  }

  Future<List<int>> createEncryptedBackup() async {
    _requireUnlocked();
    final verifier = await _repository.readVerifier(_generation!);
    if (verifier == null) throw StateError('Password verifier is missing.');
    final payload = utf8.encode(jsonEncode({
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
    }));
    final envelope = await _crypto.encrypt(
      payload,
      _sessionKey!,
      aad: utf8.encode('securevault:backup:v1'),
    );
    return utf8.encode(jsonEncode({
      'format': 'securevault-backup',
      'version': 1,
      'credential': verifier.toJson(),
      'envelope': envelope.toJson(),
    }));
  }

  Future<void> restoreEncryptedBackup(List<int> backup, String backupPassword) async {
    _requireUnlocked();
    final header = jsonDecode(utf8.decode(backup)) as Map<String, dynamic>;
    if (header['format'] != 'securevault-backup' || header['version'] != 1) {
      throw const FormatException('Unsupported SecureVault backup.');
    }
    final verifier = PasswordVerifierRecord.fromJson(
      header['credential'] as Map<String, dynamic>,
    );
    final backupKey = await _crypto.verifyMasterPassword(backupPassword, verifier);
    if (backupKey == null) throw const FormatException('Incorrect backup password.');
    final envelope = EncryptedEnvelope.fromJson(header['envelope'] as Map<String, dynamic>);
    final clear = await _crypto.decrypt(
      envelope,
      backupKey,
      aad: utf8.encode('securevault:backup:v1'),
    );
    final payload = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final restored = (payload['entries'] as List<dynamic>)
        .map((item) => VaultEntry.fromJson(item as Map<String, dynamic>))
        .toList();
    final previous = entries;
    entries = restored;
    try {
      await _persistEntries();
    } catch (_) {
      entries = previous;
      rethrow;
    }
    await _recordEvent('Encrypted backup restored');
    notifyListeners();
  }

  Future<void> refreshSecurityLog() async {
    await _reloadLog();
    notifyListeners();
  }

  Future<void> _reloadLog() async {
    securityLog = await _repository.readSecurityLog();
  }

  Future<void> _recordEvent(String event) async {
    try {
      await _repository.appendSecurityEvent(event);
      await _reloadLog();
    } catch (_) {
      // Audit logging must not undo a committed password, login, or recovery change.
    }
  }

  Future<void> lock() async {
    if (state != VaultState.unlocked) return;
    entries = [];
    _totpSecret = null;
    _sessionKey = null;
    state = VaultState.locked;
    notifyListeners();
    await _recordEvent('Vault locked');
  }

  String generatePassword({int length = 20, bool symbols = true}) {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    const digits = '23456789';
    const punctuation = r'!@#$%^&*()-_=+[]{}?';
    final alphabet = letters + digits + (symbols ? punctuation : '');
    final limit = 256 - (256 % alphabet.length);
    if (length < 12 || length > 64) throw ArgumentError('Password length must be 12–64.');
    String choose(String pool) {
      var value = _random.nextInt(256);
      while (value >= limit) {
        value = _random.nextInt(256);
      }
      return pool[value % pool.length];
    }
    final values = <String>[choose(letters), choose(digits)];
    if (symbols) values.add(choose(punctuation));
    while (values.length < length) {
      values.add(choose(alphabet));
    }
    for (var index = values.length - 1; index > 0; index--) {
      final other = _random.nextInt(index + 1);
      final value = values[index];
      values[index] = values[other];
      values[other] = value;
    }
    return values.join();
  }

  String newEntryId() => _newId();

  String _newId() => List<int>.generate(16, (_) => _random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  List<int> _recordAad(String id) => utf8.encode('securevault:entry:v1:$id');

  void _requireUnlocked() {
    if (state != VaultState.unlocked || _sessionKey == null) {
      throw StateError('Unlock the vault before accessing entries.');
    }
  }
}
