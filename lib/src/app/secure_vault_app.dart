import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:share_plus/share_plus.dart';

import '../data/vault_entry.dart';
import 'vault_controller.dart';

class SecureVaultApp extends StatefulWidget {
  const SecureVaultApp({super.key});

  @override
  State<SecureVaultApp> createState() => _SecureVaultAppState();
}

class _SecureVaultAppState extends State<SecureVaultApp> with WidgetsBindingObserver {
  late final VaultController controller;
  Timer? _backgroundLock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    controller = VaultController();
    unawaited(controller.initialize());
  }

  @override
  void dispose() {
    _backgroundLock?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _backgroundLock?.cancel();
      _backgroundLock = Timer(const Duration(minutes: 1), () async {
        await controller.lock();
        await ScreenProtector.preventScreenshotOff();
      });
    } else if (state == AppLifecycleState.resumed) {
      _backgroundLock?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => MaterialApp(
          title: 'SecureVault',
          debugShowCheckedModeBanner: false,
          theme: _theme,
          home: switch (controller.state) {
            VaultState.loading => const _LoadingScreen(),
            VaultState.uninitialized || VaultState.settingUp => _SetupScreen(controller),
            VaultState.recoveryPending => _RecoveryCodesScreen(controller),
            VaultState.locked => _LoginScreen(controller),
            VaultState.unlocked => _VaultScreen(
                controller,
                onLock: () async {
                  await controller.lock();
                  await ScreenProtector.preventScreenshotOff();
                },
              ),
          },
        ),
      );
}

const _ink = Color(0xFF0B1220);
const _panel = Color(0xFF111C2D);
const _mint = Color(0xFF63E6BE);
const _muted = Color(0xFF9AABC2);

final _theme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _ink,
  colorScheme: ColorScheme.fromSeed(
    seedColor: _mint,
    brightness: Brightness.dark,
    primary: _mint,
    surface: _panel,
  ),
  appBarTheme: const AppBarTheme(backgroundColor: _ink, foregroundColor: Colors.white),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _panel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: const BorderSide(color: _mint)),
    labelStyle: const TextStyle(color: _muted),
  ),
  cardTheme: CardThemeData(color: _panel, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: _mint, foregroundColor: _ink, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), textStyle: const TextStyle(fontWeight: FontWeight.w700)),
  ),
  textTheme: const TextTheme(
    headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.7),
    titleLarge: TextStyle(fontWeight: FontWeight.w700),
    bodyMedium: TextStyle(color: _muted, height: 1.4),
  ),
);

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 38 : 48,
            height: compact ? 38 : 48,
            decoration: BoxDecoration(color: _mint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.shield_rounded, color: _mint),
          ),
          const SizedBox(width: 12),
          Text('SecureVault', style: TextStyle(fontSize: compact ? 20 : 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        ],
      );
}

class _SetupScreen extends StatefulWidget {
  const _SetupScreen(this.controller);
  final VaultController controller;
  @override
  State<_SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<_SetupScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_password.text.runes.length < 12) {
      setState(() => _error = 'Use at least 12 characters for your master password.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await widget.controller.beginSetup(_password.text);
    } catch (error) {
      setState(() => _error = 'Could not start setup: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _confirmTotp() {
    if (!widget.controller.confirmSetupCode(_code.text.trim())) {
      setState(() => _error = 'That code is invalid or expired. Try the current code in your authenticator.');
    } else {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enrolling = widget.controller.state == VaultState.settingUp;
    final uri = widget.controller.setupUri;
    final secret = uri == null ? '' : Uri.parse(uri).queryParameters['secret'] ?? '';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
              children: [
                const _Brand(),
                const SizedBox(height: 44),
                Text(enrolling ? 'Add your authenticator' : 'Your passwords, protected', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                Text(enrolling ? 'Scan the QR code with Google Authenticator, then enter its six-digit code.' : 'Create a strong master password. It is used only in memory to unlock your encrypted vault.', style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 30),
                if (!enrolling) ...[
                  TextField(
                    controller: _password,
                    obscureText: !_showPassword,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'Master password',
                      helperText: 'At least 12 characters · ${_password.text.runes.length} entered',
                      suffixIcon: IconButton(icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPassword = !_showPassword)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_password.text.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: _passwordStrength(_password.text), minHeight: 6, color: _passwordStrength(_password.text) < 0.4 ? const Color(0xFFFFA66D) : _mint, backgroundColor: Colors.white12)),
                    const SizedBox(height: 5),
                    Text(_strengthLabel(_passwordStrength(_password.text)), style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(onPressed: _busy ? null : _start, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Create secure vault')),
                ] else ...[
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: QrImageView(data: uri!, size: 220, backgroundColor: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('Can’t scan? Enter this setup key manually:', textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  SelectableText(secret, textAlign: TextAlign.center, style: const TextStyle(color: _mint, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 24),
                  TextField(controller: _code, keyboardType: TextInputType.number, maxLength: 6, textAlign: TextAlign.center, decoration: const InputDecoration(labelText: '6-digit verification code', counterText: ''), onSubmitted: (_) => _confirmTotp()),
                  const SizedBox(height: 14),
                  FilledButton(onPressed: _confirmTotp, child: const Text('Verify authenticator')),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Text(_error!, style: const TextStyle(color: Color(0xFFFF9B9B))),
                ],
                const SizedBox(height: 24),
                const _SecurityNote(text: 'Your vault stays on this device. SecureVault cannot recover your master password.'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryCodesScreen extends StatefulWidget {
  const _RecoveryCodesScreen(this.controller);
  final VaultController controller;
  @override
  State<_RecoveryCodesScreen> createState() => _RecoveryCodesScreenState();
}

class _RecoveryCodesScreenState extends State<_RecoveryCodesScreen> {
  bool _saved = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_protectRecoveryCodes());
  }

  Future<void> _protectRecoveryCodes() async {
    try {
      await ScreenProtector.preventScreenshotOn();
    } catch (_) {
      // Screenshot prevention is platform-dependent and remains best-effort.
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false, title: const _Brand(compact: true)),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text('Save your recovery codes', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 10),
                const Text('Each code works once if you lose access to your authenticator. SecureVault stores only salted hashes, so these codes cannot be shown again.'),
                const SizedBox(height: 22),
                Card(child: Padding(padding: const EdgeInsets.all(18), child: SelectableText(widget.controller.recoveryCodes.join('\n'), style: const TextStyle(fontFamily: 'monospace', height: 2, color: _mint, fontSize: 15)))),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: () async { await _copyAndClear(widget.controller.recoveryCodes.join('\n')); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Codes copied. Clipboard clears in 20 seconds.'))); }, icon: const Icon(Icons.copy), label: const Text('Copy codes')),
                CheckboxListTile(value: _saved, onChanged: (value) => setState(() => _saved = value ?? false), contentPadding: EdgeInsets.zero, title: const Text('I saved these codes somewhere safe'), controlAffinity: ListTileControlAffinity.leading),
                FilledButton(onPressed: !_saved || _busy ? null : () async {
                  setState(() => _busy = true);
                  try {
                    await widget.controller.acknowledgeRecoveryCodes();
                    await ScreenProtector.preventScreenshotOn();
                  } catch (_) {
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not finish setup. Your recovery codes are still visible.')));
                  } finally {
                    if (mounted && widget.controller.state == VaultState.recoveryPending) setState(() => _busy = false);
                  }
                }, child: _busy ? const CircularProgressIndicator() : const Text('Open my vault')),
              ],
            ),
          ),
        ),
      );
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen(this.controller);
  final VaultController controller;
  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() { _password.dispose(); _code.dispose(); super.dispose(); }

  Future<void> _unlock() async {
    if (widget.controller.isLockedOut) { setState(() => _error = 'Too many attempts. Try again after ${_remaining()}.'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final ok = await widget.controller.unlock(_password.text, _code.text.trim());
      if (ok) {
        await ScreenProtector.preventScreenshotOn();
      } else {
        final until = widget.controller.lockedUntil;
        setState(() => _error = until != null && until.isAfter(DateTime.now())
            ? 'Too many attempts. The vault is locked for ${_remaining()}.'
            : 'Password or verification code is incorrect.');
      }
    } catch (_) {
      setState(() => _error = 'Could not unlock the vault. Check your password and code.');
    } finally { if (mounted) setState(() => _busy = false); }
  }

  String _remaining() {
    final until = widget.controller.lockedUntil;
    if (until == null) return 'a few minutes';
    final seconds = max(0, until.difference(DateTime.now()).inSeconds);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  const _Brand(),
                  const SizedBox(height: 38),
                  Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Unlock your encrypted vault with both factors.'),
                  const SizedBox(height: 28),
                  TextField(controller: _password, obscureText: !_showPassword, autofillHints: const [AutofillHints.password], decoration: InputDecoration(labelText: 'Master password', suffixIcon: IconButton(icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => _showPassword = !_showPassword)))),
                  const SizedBox(height: 14),
                  TextField(controller: _code, keyboardType: TextInputType.visiblePassword, autocorrect: false, enableSuggestions: false, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Authenticator code or recovery code'), onSubmitted: (_) => _unlock()),
                  const SizedBox(height: 20),
                  FilledButton(onPressed: _busy ? null : _unlock, child: _busy ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Unlock vault')),
                  if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: Color(0xFFFF9B9B)))],
                  const SizedBox(height: 22),
                  const _SecurityNote(text: 'After five failed attempts, access is delayed. The delay increases after repeated lockouts.'),
                ],
              ),
            ),
          ),
        ),
      );
}

class _VaultScreen extends StatefulWidget {
  const _VaultScreen(this.controller, {required this.onLock});
  final VaultController controller;
  final Future<void> Function() onLock;
  @override
  State<_VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<_VaultScreen> {
  final _search = TextEditingController();
  VaultCategory? _category;
  bool _favoritesOnly = false;
  String _sort = 'Recently updated';
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  List<VaultEntry> get _visible {
    var rows = [...widget.controller.entries];
    final query = _search.text.toLowerCase().trim();
    if (query.isNotEmpty) rows = rows.where((e) => '${e.title} ${e.site} ${e.username}'.toLowerCase().contains(query)).toList();
    if (_category != null) rows = rows.where((e) => e.category == _category).toList();
    if (_favoritesOnly) rows = rows.where((e) => e.favorite).toList();
    switch (_sort) {
      case 'Name':
        rows.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case 'Category':
        rows.sort((a, b) => a.category.name.compareTo(b.category.name));
        break;
      default:
        rows.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return rows;
  }

  Future<void> _edit([VaultEntry? entry]) async {
    final saved = await showModalBottomSheet<VaultEntry>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: _panel, builder: (_) => _EntryEditor(widget.controller, entry: entry));
    if (saved != null) {
      try {
        await widget.controller.addOrUpdate(saved);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save the encrypted login.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visible;
    return Scaffold(
      appBar: AppBar(
        title: const _Brand(compact: true),
        actions: [
          IconButton(tooltip: 'Password generator', onPressed: _showGenerator, icon: const Icon(Icons.auto_awesome)),
          IconButton(tooltip: 'Settings', onPressed: _showSettings, icon: const Icon(Icons.tune_rounded)),
          IconButton(tooltip: 'Lock vault', onPressed: widget.onLock, icon: const Icon(Icons.lock_outline)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New login')),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your vault', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 5),
                  Text('${widget.controller.entries.length} secure ${widget.controller.entries.length == 1 ? 'item' : 'items'}', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 20),
                  TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search titles, sites, usernames')),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: DropdownButtonFormField<VaultCategory?>(initialValue: _category, decoration: const InputDecoration(labelText: 'Category'), items: [const DropdownMenuItem(value: null, child: Text('All categories')), ...VaultCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c))))], onChanged: (value) => setState(() => _category = value))),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly), icon: Icon(_favoritesOnly ? Icons.star : Icons.star_border, color: _favoritesOnly ? _mint : null), tooltip: 'Favorites only'),
                    const SizedBox(width: 4),
                    PopupMenuButton<String>(initialValue: _sort, onSelected: (value) => setState(() => _sort = value), itemBuilder: (_) => ['Recently updated', 'Name', 'Category'].map((value) => PopupMenuItem(value: value, child: Text(value))).toList(), icon: const Icon(Icons.sort)),
                  ]),
                ],
              ),
            ),
          ),
          if (rows.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _EmptyVault(onAdd: () => _edit(), hasSearch: _search.text.isNotEmpty || _category != null || _favoritesOnly))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList.separated(
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _EntryCard(
                  entry: rows[index],
                  onOpen: () => _showEntry(rows[index]),
                  onEdit: () => _edit(rows[index]),
                  onFavorite: () => widget.controller.toggleFavorite(rows[index]),
                  onDelete: () => _confirmDelete(rows[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showEntry(VaultEntry entry) async {
    await showModalBottomSheet<void>(context: context, useSafeArea: true, backgroundColor: _panel, builder: (context) => _EntryDetails(entry: entry, onEdit: () { Navigator.pop(context); _edit(entry); }));
  }

  Future<void> _confirmDelete(VaultEntry entry) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete this login?'), content: Text('“${entry.title}” will be removed from your vault.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (yes == true) {
      try {
        await widget.controller.deleteEntry(entry.id);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not delete this login.')));
      }
    }
  }

  Future<void> _showGenerator() async {
    var length = 20.0;
    var symbols = true;
    String generated = widget.controller.generatePassword(length: length.toInt(), symbols: symbols);
    await showModalBottomSheet<void>(context: context, useSafeArea: true, backgroundColor: _panel, isScrollControlled: true, builder: (context) => StatefulBuilder(builder: (context, setSheet) => Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Password generator', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), const Text('Generated on this device using a cryptographically secure random source.'),
        const SizedBox(height: 18), SelectableText(generated, style: const TextStyle(color: _mint, fontSize: 18, fontFamily: 'monospace')),
        Row(children: [const Text('Length'), Expanded(child: Slider(value: length, min: 12, max: 48, divisions: 36, label: '${length.toInt()}', onChanged: (v) => setSheet(() { length = v; generated = widget.controller.generatePassword(length: length.toInt(), symbols: symbols); }))), Text('${length.toInt()}')]),
        SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Include symbols'), value: symbols, onChanged: (v) => setSheet(() { symbols = v; generated = widget.controller.generatePassword(length: length.toInt(), symbols: symbols); })),
        Row(children: [Expanded(child: OutlinedButton.icon(onPressed: () async { await _copyAndClear(generated); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Clipboard clears in 20 seconds.'))); }, icon: const Icon(Icons.copy), label: const Text('Copy'))), const SizedBox(width: 10), Expanded(child: FilledButton.icon(onPressed: () => setSheet(() => generated = widget.controller.generatePassword(length: length.toInt(), symbols: symbols)), icon: const Icon(Icons.refresh), label: const Text('Regenerate')))]),
      ]),
    )));
  }

  Future<void> _showSettings() async {
    await showModalBottomSheet<void>(context: context, useSafeArea: true, backgroundColor: _panel, builder: (context) => Padding(
      padding: const EdgeInsets.all(22),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Security & settings', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.key), title: const Text('Change master password'), onTap: () { Navigator.pop(context); _changePassword(); }),
        ListTile(leading: const Icon(Icons.confirmation_number_outlined), title: const Text('Regenerate recovery codes'), onTap: () { Navigator.pop(context); _regenerateRecoveryCodes(); }),
        ListTile(leading: const Icon(Icons.history), title: const Text('Security log'), onTap: () { Navigator.pop(context); _showSecurityLog(); }),
        ListTile(leading: const Icon(Icons.file_upload_outlined), title: const Text('Export encrypted backup'), onTap: () { Navigator.pop(context); _exportBackup(); }),
        ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Import encrypted backup'), onTap: () { Navigator.pop(context); _importBackup(); }),
        const SizedBox(height: 8),
        const Text('Passwords are encrypted locally. Keep your recovery codes somewhere separate from this device.'),
      ]),
    ));
  }

  Future<void> _changePassword() async {
    final form = GlobalKey<FormState>();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Change master password'),
      content: Form(key: form, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextFormField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'New password'), validator: (v) => (v?.runes.length ?? 0) < 12 ? 'Use at least 12 characters.' : null),
        const SizedBox(height: 12),
        TextFormField(controller: confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password'), validator: (v) => v != next.text ? 'Passwords do not match.' : null),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () { if (form.currentState!.validate()) Navigator.pop(context, true); }, child: const Text('Re-encrypt vault'))],
    ));
    if (accepted == true) {
      try {
        await widget.controller.changeMasterPassword(next.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Master password changed. Vault re-encrypted.')));
      } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password change failed. Your previous password remains active.'))); }
    }
    next.dispose(); confirm.dispose();
  }

  Future<void> _showSecurityLog() async {
    await widget.controller.refreshSecurityLog();
    if (!mounted) return;
    await showDialog<void>(context: context, builder: (context) => AlertDialog(
      title: const Text('Security log'),
      content: SizedBox(width: 420, child: ListView(shrinkWrap: true, children: widget.controller.securityLog.map((event) => ListTile(dense: true, title: Text(event['event'] as String), subtitle: Text((event['time'] as String).replaceFirst('T', ' ').replaceFirst('Z', ' UTC')))).toList())),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    ));
  }

  Future<void> _regenerateRecoveryCodes() async {
    try {
      final codes = await widget.controller.regenerateRecoveryCodes();
      if (!mounted) return;
      await showDialog<void>(context: context, barrierDismissible: false, builder: (context) => AlertDialog(
        title: const Text('New recovery codes'),
        content: SelectableText(codes.join('\n'), style: const TextStyle(fontFamily: 'monospace', height: 1.8, color: _mint)),
        actions: [
          TextButton(onPressed: () async { await _copyAndClear(codes.join('\n')); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied. Clipboard clears in 20 seconds.'))); }, child: const Text('Copy')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('I saved them')),
        ],
      ));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not regenerate recovery codes.')));
    }
  }

  Future<void> _exportBackup() async {
    try {
      final bytes = await widget.controller.createEncryptedBackup();
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}securevault-backup.svault');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/octet-stream')], title: 'SecureVault encrypted backup'));
      if (await file.exists()) await file.delete();
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create the encrypted backup.'))); }
  }

  Future<void> _importBackup() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['svault']);
      if (picked == null) return;
      if ((await picked.length() ?? 0) > 100 * 1024 * 1024) {
        throw const FormatException('Backup is larger than the supported 100 MB limit.');
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      final backupPassword = TextEditingController();
      final passwordAccepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: const Text('Backup password'),
        content: TextField(controller: backupPassword, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Password used when backup was made')),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))],
      ));
      if (passwordAccepted != true) { backupPassword.dispose(); return; }
      final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Replace vault contents?'), content: const Text('Importing this backup replaces the entries currently in this vault.'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace vault'))]));
      if (yes == true) {
        await widget.controller.restoreEncryptedBackup(bytes, backupPassword.text);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup restored.')));
      }
      backupPassword.dispose();
    } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Backup could not be opened. Check that it belongs to this master password.'))); }
  }
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor(this.controller, {this.entry});
  final VaultController controller;
  final VaultEntry? entry;
  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController title;
  late final TextEditingController site;
  late final TextEditingController username;
  late final TextEditingController password;
  late final TextEditingController notes;
  late VaultCategory category;
  late bool favorite;
  bool showPassword = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    title = TextEditingController(text: e?.title);
    site = TextEditingController(text: e?.site);
    username = TextEditingController(text: e?.username);
    password = TextEditingController(text: e?.password);
    notes = TextEditingController(text: e?.notes);
    category = e?.category ?? VaultCategory.other;
    favorite = e?.favorite ?? false;
  }

  @override
  void dispose() { title.dispose(); site.dispose(); username.dispose(); password.dispose(); notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(22, 18, 22, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: Form(key: _form, child: ListView(shrinkWrap: true, children: [
          Text(widget.entry == null ? 'New login' : 'Edit login', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          TextFormField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Title'), validator: (v) => v == null || v.trim().isEmpty ? 'Enter a title.' : null),
          const SizedBox(height: 12), TextFormField(controller: site, decoration: const InputDecoration(labelText: 'Website or app')),
          const SizedBox(height: 12), TextFormField(controller: username, decoration: const InputDecoration(labelText: 'Username or email')),
          const SizedBox(height: 12), TextFormField(controller: password, obscureText: !showPassword, decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(onPressed: () => setState(() => showPassword = !showPassword), icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility)))),
          const SizedBox(height: 12), DropdownButtonFormField<VaultCategory>(initialValue: category, decoration: const InputDecoration(labelText: 'Category'), items: VaultCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(_categoryLabel(c)))).toList(), onChanged: (value) => setState(() => category = value ?? VaultCategory.other)),
          const SizedBox(height: 8), SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Favorite'), value: favorite, onChanged: (value) => setState(() => favorite = value)),
          TextFormField(controller: notes, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Notes')),
          const SizedBox(height: 18), FilledButton(onPressed: () { if (_form.currentState!.validate()) { Navigator.pop(context, VaultEntry(id: widget.entry?.id ?? widget.controller.newEntryId(), title: title.text.trim(), site: site.text.trim(), username: username.text.trim(), password: password.text, notes: notes.text, category: category, favorite: favorite, updatedAt: DateTime.now().toUtc())); } }, child: const Text('Save encrypted login')),
        ])),
      );
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onOpen, required this.onEdit, required this.onFavorite, required this.onDelete});
  final VaultEntry entry;
  final VoidCallback onOpen, onEdit, onFavorite, onDelete;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 7, 8, 7),
          onTap: onOpen,
          leading: Container(width: 44, height: 44, decoration: BoxDecoration(color: _mint.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)), child: Icon(_categoryIcon(entry.category), color: _mint)),
          title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(entry.username.isEmpty ? (entry.site.isEmpty ? _categoryLabel(entry.category) : entry.site) : entry.username, maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(onSelected: (value) { if (value == 'favorite') onFavorite(); if (value == 'edit') onEdit(); if (value == 'delete') onDelete(); }, itemBuilder: (_) => [PopupMenuItem(value: 'favorite', child: Text(entry.favorite ? 'Remove favorite' : 'Add favorite')), const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete'))], icon: Icon(entry.favorite ? Icons.star : Icons.more_horiz, color: entry.favorite ? _mint : null)),
        ),
      );
}

class _EntryDetails extends StatefulWidget {
  const _EntryDetails({required this.entry, required this.onEdit});
  final VaultEntry entry;
  final VoidCallback onEdit;
  @override
  State<_EntryDetails> createState() => _EntryDetailsState();
}

class _EntryDetailsState extends State<_EntryDetails> {
  bool reveal = false;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Expanded(child: Text(widget.entry.title, style: Theme.of(context).textTheme.titleLarge)), IconButton(onPressed: widget.onEdit, icon: const Icon(Icons.edit_outlined))]),
    const SizedBox(height: 12),
    _DetailLine(label: 'Website / app', value: widget.entry.site),
    _DetailLine(label: 'Username', value: widget.entry.username, onCopy: widget.entry.username.isEmpty ? null : () => _copy(widget.entry.username)),
    Row(children: [Expanded(child: _DetailLine(label: 'Password', value: reveal ? widget.entry.password : '••••••••••••', onCopy: reveal ? () => _copy(widget.entry.password) : null)), IconButton(onPressed: () => setState(() => reveal = !reveal), icon: Icon(reveal ? Icons.visibility_off : Icons.visibility))]),
    if (widget.entry.notes.isNotEmpty) _DetailLine(label: 'Notes', value: widget.entry.notes),
    const SizedBox(height: 12),
  ]));

  Future<void> _copy(String value) async {
    await _copyAndClear(value);
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value, this.onCopy});
  final String label, value;
  final VoidCallback? onCopy;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 4), SelectableText(value)])), if (onCopy != null) IconButton(onPressed: onCopy, icon: const Icon(Icons.copy, size: 19))]));
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.onAdd, required this.hasSearch});
  final VoidCallback onAdd;
  final bool hasSearch;
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(30), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(hasSearch ? Icons.search_off : Icons.lock_outline, size: 45, color: _muted), const SizedBox(height: 15), Text(hasSearch ? 'No matching logins' : 'Your vault is ready', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text(hasSearch ? 'Try a different search or category.' : 'Add your first login. Each item is encrypted separately.', textAlign: TextAlign.center), if (!hasSearch) ...[const SizedBox(height: 18), FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add a login'))]])));
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: _mint.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(15)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.verified_user_outlined, color: _mint, size: 19), const SizedBox(width: 10), Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall))]));
}

var _clipboardRevision = 0;

Future<void> _copyAndClear(String value) async {
  final revision = ++_clipboardRevision;
  await Clipboard.setData(ClipboardData(text: value));
  await Future<void>.delayed(const Duration(seconds: 20));
  if (revision != _clipboardRevision) return;
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  if (data?.text == value) await Clipboard.setData(const ClipboardData(text: ''));
}

double _passwordStrength(String value) {
  var score = 0;
  if (value.runes.length >= 12) score++;
  if (value.runes.length >= 16) score++;
  if (RegExp('[a-z]').hasMatch(value) && RegExp('[A-Z]').hasMatch(value)) score++;
  if (RegExp(r'\d').hasMatch(value)) score++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(value)) score++;
  return score / 5;
}

String _strengthLabel(double strength) => switch (strength) {
      < 0.4 => 'Password strength: add length and variety',
      < 0.8 => 'Password strength: good',
      _ => 'Password strength: strong',
    };

String _categoryLabel(VaultCategory category) => switch (category) { VaultCategory.social => 'Social', VaultCategory.banking => 'Banking', VaultCategory.work => 'Work', VaultCategory.other => 'Other' };
IconData _categoryIcon(VaultCategory category) => switch (category) { VaultCategory.social => Icons.forum_outlined, VaultCategory.banking => Icons.account_balance_outlined, VaultCategory.work => Icons.work_outline, VaultCategory.other => Icons.key_outlined };
