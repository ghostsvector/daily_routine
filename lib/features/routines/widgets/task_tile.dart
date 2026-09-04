import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';

/// A single row in the timeline: time on the left, a dot-and-line rail,
/// then the task's category tag, title, notes and duration.
class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggleCompleted,
    required this.onTap,
    required this.onStartFocusSession,
    this.isLast = false,
  });

  final RoutineTask task;
  final ValueChanged<bool> onToggleCompleted;
  final VoidCallback onTap;
  final VoidCallback onStartFocusSession;

  /// Hides the connecting line below the dot for the final row so the
  /// timeline doesn't trail off past the last task.
  final bool isLast;

  static const _categoryLabels = {
    TaskCategory.health: 'HEALTH',
    TaskCategory.work: 'WORK',
    TaskCategory.study: 'STUDY',
    TaskCategory.personal: 'PERSONAL',
    TaskCategory.chores: 'CHORES',
    TaskCategory.mindfulness: 'BREAK',
    TaskCategory.other: 'OTHER',
  };

  Color _colorFor(TaskCategory category, ColorScheme scheme) {
    switch (category) {
      case TaskCategory.health:
        return Colors.teal;
      case TaskCategory.work:
        return Colors.amber.shade800;
      case TaskCategory.study:
        return scheme.primary;
      case TaskCategory.personal:
        return Colors.deepPurple;
      case TaskCategory.chores:
        return Colors.brown;
      case TaskCategory.mindfulness:
        return Colors.blueGrey;
      case TaskCategory.other:
        return scheme.outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colorFor(task.category, theme.colorScheme);
    final completed = task.isCompletedForToday;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 54,
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    formatMinuteOfDay(task.startMinuteOfDay),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 18),
                    Container(
                      width: task.isAlarm ? 12 : 10,
                      height: task.isAlarm ? 12 : 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: task.isAlarm
                            ? Border.all(color: color.withValues(alpha: 0.35), width: 3)
                            : null,
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(width: 2, color: theme.dividerColor),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform.translate(
                        offset: const Offset(-8, 4),
                        child: Checkbox(
                          value: completed,
                          onChanged: (value) => onToggleCompleted(value ?? false),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    _categoryLabels[task.category] ?? 'OTHER',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${task.durationMinutes}m',
                                  style: theme.textTheme.labelSmall,
                                ),
                                if (task.blockedAppPackageIds.isNotEmpty)
                                  IconButton(
                                    tooltip: 'Start focus session',
                                    icon: const Icon(Icons.shield_outlined, size: 18),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: onStartFocusSession,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              task.title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                decoration:
                                    completed ? TextDecoration.lineThrough : null,
                                color: completed ? theme.disabledColor : null,
                              ),
                            ),
                            if (task.notes.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  task.notes,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.hintColor,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
