import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/blocker_providers.dart';

/// Lets the user browse apps/processes on this device and manage their
/// synced blocklist selection (used later by any task's focus session).
class BlockedAppsScreen extends ConsumerWidget {
  const BlockedAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsAsync = ref.watch(blockableTargetsProvider);
    final savedAsync = ref.watch(savedBlockedAppsProvider);
    final permissionAsync = ref.watch(hasBlockPermissionProvider);
    final user = ref.watch(currentUserProvider);
    final blocker = ref.watch(appBlockerProvider);
    final repo = ref.watch(blockedAppsRepositoryProvider);

    final savedIds = (savedAsync.valueOrNull ?? const <BlockedApp>[])
        .map((a) => a.packageId)
        .toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('Blocked apps')),
      body: Column(
        children: [
          permissionAsync.when(
            data: (hasPermission) => hasPermission
                ? const SizedBox.shrink()
                : _PermissionBanner(
                    onGrant: () async {
                      await blocker.requestPermission();
                      ref.invalidate(hasBlockPermissionProvider);
                    },
                  ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          Expanded(
            child: targetsAsync.when(
              data: (targets) {
                if (targets.isEmpty) {
                  return const Center(child: Text('No blockable apps found on this device.'));
                }
                return ListView.builder(
                  itemCount: targets.length,
                  itemBuilder: (context, index) {
                    final app = targets[index];
                    final isSelected = savedIds.contains(app.packageId);
                    return CheckboxListTile(
                      title: Text(app.displayName),
                      subtitle: Text(app.packageId, style: Theme.of(context).textTheme.bodySmall),
                      value: isSelected,
                      onChanged: (checked) async {
                        if (checked == true) {
                          await repo.setBlockedApps(user.uid, [app]);
                        } else {
                          await repo.removeBlockedApp(user.uid, app.packageId);
                        }
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load apps: $e')),
            ),
          ),
        ],
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
        'To block apps on this device, grant Usage Access in system settings.',
      ),
      actions: [
        TextButton(onPressed: onGrant, child: const Text('Grant')),
      ],
    );
  }
}
