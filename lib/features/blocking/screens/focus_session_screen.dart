import 'dart:async';

import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

/// Runs an active blocking session for the duration of [task], killing/
/// redirecting away from any of [RoutineTask.blockedAppPackageIds] until the
/// timer ends or the user stops early.
class FocusSessionScreen extends ConsumerStatefulWidget {
  const FocusSessionScreen({super.key, required this.task});

  final RoutineTask task;

  @override
  ConsumerState<FocusSessionScreen> createState() => _FocusSessionScreenState();
}

class _FocusSessionScreenState extends ConsumerState<FocusSessionScreen> {
  late Duration _remaining = Duration(minutes: widget.task.durationMinutes);
  Timer? _timer;
  bool _isBlocking = false;
  final List<String> _blockedEvents = [];
  StreamSubscription<String>? _blockedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final blocker = ref.read(appBlockerProvider);
    await blocker.startBlocking(widget.task.blockedAppPackageIds);
    _blockedSub = blocker.onAppBlocked.listen((packageId) {
      setState(() => _blockedEvents.insert(0, packageId));
    });
    setState(() => _isBlocking = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_remaining.inSeconds <= 1) {
        _finish();
      } else {
        setState(() => _remaining -= const Duration(seconds: 1));
      }
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    await _blockedSub?.cancel();
    await ref.read(appBlockerProvider).stopBlocking();
    if (mounted) {
      setState(() {
        _isBlocking = false;
        _remaining = Duration.zero;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _blockedSub?.cancel();
    ref.read(appBlockerProvider).stopBlocking();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final minutes = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');

    return PopScope(
      canPop: !_isBlocking,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.task.title)),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$minutes:$seconds',
                style: Theme.of(context).textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                _isBlocking
                    ? '${widget.task.blockedAppPackageIds.length} apps blocked'
                    : 'Session ended',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              if (_isBlocking)
                OutlinedButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('End session early'),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              if (_blockedEvents.isNotEmpty) ...[
                const SizedBox(height: 32),
                Text('Blocked attempts', style: Theme.of(context).textTheme.titleSmall),
                ..._blockedEvents.take(5).map((id) => Text(id)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
