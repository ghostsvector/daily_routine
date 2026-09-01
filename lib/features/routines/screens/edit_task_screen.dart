import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../blocking/providers/blocker_providers.dart';
import '../providers/routine_providers.dart';

/// Creates a new task when [taskId] is null, otherwise edits the existing
/// task with that id.
class EditTaskScreen extends ConsumerStatefulWidget {
  const EditTaskScreen({super.key, this.taskId});

  final String? taskId;

  @override
  ConsumerState<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends ConsumerState<EditTaskScreen> {
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  TimeOfDay _startTime = TimeOfDay.now();
  int _durationMinutes = 30;
  TaskCategory _category = TaskCategory.other;
  RepeatRule _repeatRule = RepeatRule.daily;
  final Set<int> _customDays = {};
  bool _reminderEnabled = true;
  final Set<String> _selectedBlockedApps = {};
  bool _initialized = false;

  RoutineTask? get _existingTask {
    if (widget.taskId == null) return null;
    final tasks = ref.read(tasksStreamProvider).valueOrNull ?? const [];
    for (final t in tasks) {
      if (t.id == widget.taskId) return t;
    }
    return null;
  }

  void _hydrateFromExisting(RoutineTask task) {
    _titleController.text = task.title;
    _notesController.text = task.notes;
    _startTime = TimeOfDay(
      hour: task.startMinuteOfDay ~/ 60,
      minute: task.startMinuteOfDay % 60,
    );
    _durationMinutes = task.durationMinutes;
    _category = task.category;
    _repeatRule = task.repeatRule;
    _customDays
      ..clear()
      ..addAll(task.customDays);
    _reminderEnabled = task.reminderEnabled;
    _selectedBlockedApps
      ..clear()
      ..addAll(task.blockedAppPackageIds);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) return;
    final user = ref.read(currentUserProvider);
    final repo = ref.read(routineRepositoryProvider);
    final existing = _existingTask;
    final task = RoutineTask(
      id: existing?.id ?? const Uuid().v4(),
      title: _titleController.text.trim(),
      startMinuteOfDay: _startTime.hour * 60 + _startTime.minute,
      durationMinutes: _durationMinutes,
      category: _category,
      repeatRule: _repeatRule,
      customDays: _customDays.toList()..sort(),
      reminderEnabled: _reminderEnabled,
      blockedAppPackageIds: _selectedBlockedApps.toList(),
      isCompletedToday: existing?.isCompletedToday ?? false,
      notes: _notesController.text.trim(),
      createdAt: existing?.createdAt,
    );
    await repo.upsertTask(user.uid, task);
    await ref.read(notificationServiceProvider).scheduleTaskReminder(task);
    if (mounted) context.pop();
  }

  Future<void> _delete() async {
    final existing = _existingTask;
    if (existing == null) return;
    final user = ref.read(currentUserProvider);
    await ref.read(routineRepositoryProvider).deleteTask(user.uid, existing.id);
    await ref.read(notificationServiceProvider).cancelReminder(existing.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      final existing = _existingTask;
      if (existing != null) _hydrateFromExisting(existing);
      _initialized = true;
    }
    final blockableApps = ref.watch(blockableTargetsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.taskId == null ? 'New task' : 'Edit task'),
        actions: [
          if (widget.taskId != null)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: 'Title'),
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Start time'),
            subtitle: Text(_startTime.format(context)),
            trailing: const Icon(Icons.access_time),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: _startTime);
              if (picked != null) setState(() => _startTime = picked);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Duration'),
            subtitle: Text('$_durationMinutes minutes'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                min: 5,
                max: 240,
                divisions: 47,
                value: _durationMinutes.toDouble(),
                label: '$_durationMinutes min',
                onChanged: (v) => setState(() => _durationMinutes = v.round()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<TaskCategory>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: TaskCategory.values
                .map((c) => DropdownMenuItem(value: c, child: Text(c.name)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<RepeatRule>(
            initialValue: _repeatRule,
            decoration: const InputDecoration(labelText: 'Repeats'),
            items: RepeatRule.values
                .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                .toList(),
            onChanged: (v) => setState(() => _repeatRule = v ?? _repeatRule),
          ),
          if (_repeatRule == RepeatRule.custom) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: List.generate(7, (i) {
                final iso = i + 1;
                const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                return FilterChip(
                  label: Text(labels[i]),
                  selected: _customDays.contains(iso),
                  onSelected: (sel) => setState(
                    () => sel ? _customDays.add(iso) : _customDays.remove(iso),
                  ),
                );
              }),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Reminder notification'),
            value: _reminderEnabled,
            onChanged: (v) => setState(() => _reminderEnabled = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          Text('Block during this task', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Selected apps/processes will be blocked while a focus session for this task is running.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (blockableApps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No blockable apps detected on this device yet.'),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: blockableApps.map((app) {
                final selected = _selectedBlockedApps.contains(app.packageId);
                return FilterChip(
                  label: Text(app.displayName),
                  selected: selected,
                  onSelected: (sel) => setState(
                    () => sel
                        ? _selectedBlockedApps.add(app.packageId)
                        : _selectedBlockedApps.remove(app.packageId),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 32),
          FilledButton(onPressed: _save, child: const Text('Save task')),
        ],
      ),
    );
  }
}
