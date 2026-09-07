import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../providers/auth_providers.dart';
import '../providers/two_factor_providers.dart';

/// Shown once per app session, after Firebase Auth succeeds, when 2FA is
/// enabled — the router redirects here and blocks every other route until
/// [twoFactorSessionVerifiedProvider] flips true (see router.dart).
class TwoFactorChallengeScreen extends ConsumerStatefulWidget {
  const TwoFactorChallengeScreen({super.key});

  @override
  ConsumerState<TwoFactorChallengeScreen> createState() => _TwoFactorChallengeScreenState();
}

class _TwoFactorChallengeScreenState extends ConsumerState<TwoFactorChallengeScreen> {
  final _codeController = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final uid = ref.read(currentUserProvider).uid;
    final ok = await ref.read(twoFactorServiceProvider).verify(uid, _codeController.text);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      setState(() => _error = 'Incorrect code — try again.');
      return;
    }
    ref.read(twoFactorSessionVerifiedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify it\'s you'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out instead',
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Enter the 6-digit code from your authenticator app.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 24, letterSpacing: 8),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
