import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggleCompleted,
    required this.onTap,
    required this.onStartFocusSession,
  });

  final RoutineTask task;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onTap;
  final VoidCallback onStartFocusSession;

  IconData _iconFor(TaskCategory category) {
    switch (category) {
      case TaskCategory.health:
        return Icons.favorite_outline;
      case TaskCategory.work:
        return Icons.work_outline;
      case TaskCategory.study:
        return Icons.menu_book_outlined;
      case TaskCategory.personal:
        return Icons.person_outline;
      case TaskCategory.chores:
        return Icons.checklist_outlined;
      case TaskCategory.mindfulness:
        return Icons.self_improvement_outlined;
      case TaskCategory.other:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        onTap: onTap,
        leading: Checkbox(
          value: task.isCompletedToday,
          onChanged: (value) => onToggleCompleted(value ?? false),
        ),
        title: Text(
          task.title,
          style: task.isCompletedToday
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : null,
        ),
        subtitle: Text(
          '${formatMinuteOfDay(task.startMinuteOfDay)} · ${task.durationMinutes} min',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_iconFor(task.category), size: 18),
            if (task.blockedAppPackageIds.isNotEmpty) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Start focus session',
                icon: const Icon(Icons.shield_outlined),
                onPressed: onStartFocusSession,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
