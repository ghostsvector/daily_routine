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
  String? _provisioningUri;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
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
        .beginEnrollment(accountEmail: user.email ?? user.uid);
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
    final ok = await ref.read(twoFactorServiceProvider).confirmEnrollment(_codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'That code didn\'t match — double-check your authenticator app.');
      return;
    }
    ref.invalidate(twoFactorEnabledProvider);
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
    final ok = await ref.read(twoFactorServiceProvider).disable(_codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'Enter a current code from your authenticator app to disable.');
      return;
    }
    ref.invalidate(twoFactorEnabledProvider);
    _codeController.clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Two-factor authentication disabled.')));
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync = ref.watch(twoFactorEnabledProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: enabledAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (enabled) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (enabled && _provisioningUri == null) ...[
              const ListTile(
                leading: Icon(Icons.verified_user, color: Colors.green),
                title: Text('Two-factor authentication is ON'),
                subtitle: Text(
                  'Signing in requires a code from your authenticator app.',
                ),
              ),
              const SizedBox(height: 16),
              const Text('Enter a current code to disable it:'),
              const SizedBox(height: 8),
              _codeField(),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: _busy ? null : _disable,
                child: const Text('Disable 2FA'),
              ),
            ] else if (_provisioningUri == null) ...[
              const Text(
                'Add a second factor: after your password, you\'ll also need '
                'a 6-digit code from an authenticator app (Google Authenticator, '
                'Authy, etc.) to sign in.',
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _startEnrollment,
                child: const Text('Set up 2FA'),
              ),
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
                  child: QrImageView(
                    data: _provisioningUri!,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _CopyableSecret(uri: _provisioningUri!),
              const SizedBox(height: 16),
              _codeField(),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _confirm,
                child: const Text('Confirm & enable'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _codeField() {
    return TextField(
      controller: _codeController,
      keyboardType: TextInputType.number,
      maxLength: 6,
      decoration: const InputDecoration(labelText: '6-digit code', border: OutlineInputBorder()),
    );
  }
}

class _CopyableSecret extends StatelessWidget {
  const _CopyableSecret({required this.uri});

  final String uri;

  String get _secret => Uri.parse(uri).queryParameters['secret'] ?? '';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(_secret, style: const TextStyle(fontFamily: 'monospace')),
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copy setup key',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _secret));
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Setup key copied.')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
