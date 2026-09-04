import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../activity/providers/activity_providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/routine_providers.dart';
import '../widgets/task_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(todaysTasksProvider);
    final user = ref.watch(currentUserProvider);
    final repo = ref.watch(routineRepositoryProvider);
    // Fire-and-forget: folds past days' activity into summaries and prunes
    // the raw log. Not read here — just needs to be watched once so it
    // actually runs (see activityRolloverProvider's doc comment).
    ref.watch(activityRolloverProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          IconButton(
            tooltip: 'Dashboard',
            icon: const Icon(Icons.dashboard_outlined),
            onPressed: () => context.push('/dashboard'),
          ),
          IconButton(
            tooltip: 'Blocked apps',
            icon: const Icon(Icons.block),
            onPressed: () => context.push('/blocked-apps'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: tasks.isEmpty
          ? _EmptyState(onAddTask: () => context.push('/task/new'))
          : ListView.builder(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              itemCount: tasks.length,
              itemBuilder: (context, index) {
                final task = tasks[index];
                return TaskTile(
                  task: task,
                  isLast: index == tasks.length - 1,
                  onTap: () => context.push('/task/${task.id}'),
                  onToggleCompleted: (completed) => repo.setTaskCompleted(
                    user.uid,
                    task.id,
                    isCompleted: completed,
                  ),
                  onStartFocusSession: () =>
                      context.push('/focus-session', extra: task),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/task/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add task'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAddTask});

  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wb_sunny_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('Nothing on your routine yet'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onAddTask,
            icon: const Icon(Icons.add),
            label: const Text('Add your first task'),
          ),
        ],
      ),
    );
  }
}
