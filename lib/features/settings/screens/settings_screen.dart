import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../routines/data/gate_daily_schedule.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isLoadingSchedule = false;

  Future<void> _loadDailySchedule() async {
    setState(() => _isLoadingSchedule = true);
    final user = ref.read(currentUserProvider);
    final repo = ref.read(routineRepositoryProvider);
    final notifications = ref.read(notificationServiceProvider);
    for (final task in buildGateDailySchedule()) {
      await repo.upsertTask(user.uid, task);
      await notifications.scheduleTaskReminder(task);
    }
    if (!mounted) return;
    setState(() => _isLoadingSchedule = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daily schedule loaded — 17 tasks added.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person)),
            title: Text(user.displayName ?? user.email ?? 'Signed in'),
            subtitle: Text(user.email ?? ''),
          ),
          const Divider(),
          ListTile(
            leading: _isLoadingSchedule
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.calendar_month_outlined),
            title: const Text('Load my daily schedule'),
            subtitle: const Text(
              'GATE prep, job search, TryHackMe, freelancing & breaks — 04:00–22:00. '
              'Safe to run again; it updates the same 17 tasks.',
            ),
            onTap: _isLoadingSchedule ? null : _loadDailySchedule,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bar_chart_outlined),
            title: const Text('Activity'),
            subtitle: const Text('App usage on this device & browser activity.'),
            onTap: () => context.push('/activity'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('Murthy'),
            subtitle: const Text('Daily progress, summary & protocols — encrypted on this device.'),
            onTap: () => context.push('/murthy'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
    );
  }
}
