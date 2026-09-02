import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../providers/activity_providers.dart';

/// Shows on-device app-usage tracking status and the combined activity
/// feed (this device's app sessions + the Chrome extension's browser
/// sessions), synced via Firestore.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supportedAsync = ref.watch(activityTrackingSupportedProvider);
    final permissionAsync = ref.watch(hasUsageTrackingPermissionProvider);
    final isTracking = ref.watch(activityTrackingControllerProvider);
    final tracker = ref.watch(appUsageTrackerProvider);
    final recentAsync = ref.watch(recentActivityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity')),
      body: supportedAsync.when(
        data: (supported) {
          if (!supported) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'App-usage tracking isn\'t available on this platform yet. '
                  'Browser activity from the Chrome extension will still show up below.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              permissionAsync.when(
                data: (hasPermission) => hasPermission
                    ? SwitchListTile(
                        title: const Text('Track app usage on this device'),
                        subtitle: Text(
                          isTracking
                              ? 'Running — logging foreground app sessions.'
                              : 'Off — turn on to start logging.',
                        ),
                        value: isTracking,
                        onChanged: (value) async {
                          final controller = ref.read(
                            activityTrackingControllerProvider.notifier,
                          );
                          if (value) {
                            await controller.start();
                          } else {
                            await controller.stop();
                          }
                        },
                      )
                    : _PermissionBanner(
                        onGrant: () async {
                          await tracker.requestPermission();
                          ref.invalidate(hasUsageTrackingPermissionProvider);
                        },
                      ),
                loading: () => const LinearProgressIndicator(minHeight: 2),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const Divider(height: 1),
              Expanded(
                child: recentAsync.when(
                  data: (events) {
                    if (events.isEmpty) {
                      return const Center(child: Text('No activity logged yet.'));
                    }
                    return ListView.builder(
                      itemCount: events.length,
                      itemBuilder: (context, index) => _ActivityTile(event: events[index]),
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Could not load activity: $e')),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

class _PermissionBanner extends StatelessWidget {
  const _PermissionBanner({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return MaterialBanner(
      content: const Text(
        'To track app usage on this device, grant Usage Access in system settings.',
      ),
      actions: [TextButton(onPressed: onGrant, child: const Text('Grant'))],
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.event});

  final ActivityEvent event;

  IconData get _icon => switch (event.type) {
    'app' => Icons.smartphone,
    'video' => Icons.play_circle_outline,
    _ => Icons.public,
  };

  String get _subtitle {
    final parts = <String>[];
    if (event.domain != null) parts.add(event.domain!);
    if (event.packageName != null) parts.add(event.packageName!);
    parts.add(_formatDuration(event.duration));
    if (event.startedAt != null) parts.add(_formatTime(event.startedAt!));
    return parts.join(' · ');
  }

  static String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
  }

  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(_icon),
      title: Text(event.title.isEmpty ? '(untitled)' : event.title),
      subtitle: Text(_subtitle),
      dense: true,
    );
  }
}
