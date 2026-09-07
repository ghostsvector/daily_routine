import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../providers/auth_providers.dart';
import '../providers/two_factor_providers.dart';

class TwoFactorSetupScreen extends ConsumerStatefulWidget {
  const TwoFactorSetupScreen({super.key});

  @override
  ConsumerState<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends ConsumerState<TwoFactorSetupScreen> {
  final _codeController = TextEditingController();
  final _importKeyController = TextEditingController();
  String? _provisioningUri;
  String? _syncKey;
  String? _error;
  bool _busy = false;
  bool _showSyncKey = false;

  @override
  void dispose() {
    _codeController.dispose();
    _importKeyController.dispose();
    super.dispose();
  }

  Future<void> _startEnrollment() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final user = ref.read(currentUserProvider);
    final uri = await ref
        .read(twoFactorServiceProvider)
        .beginEnrollment(uid: user.uid, accountEmail: user.email ?? user.uid);
    if (!mounted) return;
    setState(() {
      _provisioningUri = uri;
      _busy = false;
    });
  }

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = ref.read(currentUserProvider).uid;
    final ok = await ref.read(twoFactorServiceProvider).confirmEnrollment(uid, _codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'That code didn\'t match — double-check your authenticator app.');
      return;
    }
    ref.invalidate(twoFactorEnabledProvider);
    ref.invalidate(twoFactorHasRemoteEnrollmentProvider);
    _codeController.clear();
    setState(() => _provisioningUri = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Two-factor authentication enabled.')));
  }

  Future<void> _disable() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = ref.read(currentUserProvider).uid;
    final ok = await ref.read(twoFactorServiceProvider).disable(uid, _codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'Enter a current code from your authenticator app to disable.');
      return;
    }
    ref.invalidate(twoFactorEnabledProvider);
    ref.invalidate(twoFactorHasRemoteEnrollmentProvider);
    _codeController.clear();
    setState(() => _syncKey = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Two-factor authentication disabled.')));
  }

  Future<void> _revealSyncKey() async {
    final uid = ref.read(currentUserProvider).uid;
    final service = ref.read(twoFactorServiceProvider);
    // Backfills the sync record for a device enrolled before cross-device
    // sync existed (a no-op if it's already synced) so the key is always
    // there to reveal once 2FA is on.
    await service.ensureSynced(uid);
    final key = await service.exportSyncKey(uid);
    if (!mounted) return;
    setState(() {
      _syncKey = key;
      _showSyncKey = true;
    });
  }

  Future<void> _pairThisDevice() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = ref.read(currentUserProvider).uid;
    final ok = await ref
        .read(twoFactorServiceProvider)
        .importFromSyncKey(uid, _importKeyController.text.trim());
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'That sync key didn\'t work — check it was copied exactly.');
      return;
    }
    ref.invalidate(twoFactorEnabledProvider);
    _importKeyController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('This device is now paired for 2FA.')));
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync = ref.watch(twoFactorEnabledProvider);
    final hasRemoteAsync = ref.watch(twoFactorHasRemoteEnrollmentProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: enabledAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (enabled) {
          if (enabled) return _buildEnabled(context);
          return hasRemoteAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error: $err')),
            data: (hasRemote) =>
                hasRemote ? _buildPairDevice(context) : _buildSetup(context),
          );
        },
      ),
    );
  }

  Widget _buildEnabled(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ListTile(
          leading: Icon(Icons.verified_user, color: Colors.green),
          title: Text('Two-factor authentication is ON'),
          subtitle: Text('Signing in on any device requires a code from your authenticator app.'),
        ),
        const Divider(height: 32),
        const Text(
          'Setting up on another device? Reveal this account\'s sync key and '
          'paste it there — it lets that device verify the same codes without '
          'creating a separate, conflicting 2FA setup.',
        ),
        const SizedBox(height: 12),
        if (!_showSyncKey)
          OutlinedButton(
            onPressed: _revealSyncKey,
            child: const Text('Reveal sync key for another device'),
          )
        else if (_syncKey == null)
          const Text('No sync key yet — this shouldn\'t happen; try disabling and re-enabling.')
        else
          _CopyableText(text: _syncKey!, label: 'sync key'),
        const Divider(height: 32),
        const Text('Enter a current code to disable 2FA everywhere:'),
        const SizedBox(height: 8),
        _codeField(),
        const SizedBox(height: 16),
        FilledButton.tonal(onPressed: _busy ? null : _disable, child: const Text('Disable 2FA')),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _buildPairDevice(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Two-factor authentication is already enabled for this account on '
          'another device. Paste that device\'s sync key here (Settings > '
          'Two-factor authentication > "Reveal sync key" there) to enable it '
          'on this device too — using the same authenticator entry, not a new one.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _importKeyController,
          decoration: const InputDecoration(labelText: 'Sync key', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy ? null : _pairThisDevice,
          child: const Text('Pair this device'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  Widget _buildSetup(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_provisioningUri == null) ...[
          const Text(
            'Add a second factor: after your password, you\'ll also need '
            'a 6-digit code from an authenticator app (Google Authenticator, '
            'Authy, etc.) to sign in.',
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _startEnrollment, child: const Text('Set up 2FA')),
        ] else ...[
          const Text(
            'Scan this with your authenticator app, or choose "Enter a setup '
            'key" and paste the secret below, then enter the 6-digit code it '
            'shows you.',
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: QrImageView(data: _provisioningUri!, version: QrVersions.auto, size: 220),
            ),
          ),
          const SizedBox(height: 16),
          _CopyableText(text: _setupKeyFromUri(_provisioningUri!), label: 'setup key'),
          const SizedBox(height: 16),
          _codeField(),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _confirm, child: const Text('Confirm & enable')),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ],
    );
  }

  String _setupKeyFromUri(String uri) => Uri.parse(uri).queryParameters['secret'] ?? '';

  Widget _codeField() {
    return TextField(
      controller: _codeController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
    );
  }
}

class _CopyableText extends StatelessWidget {
  const _CopyableText({required this.text, required this.label});

  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace'))),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy $label',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: text));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('${label[0].toUpperCase()}${label.substring(1)} copied.')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
