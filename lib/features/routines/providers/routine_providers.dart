import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';

final tasksStreamProvider = StreamProvider<List<RoutineTask>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref.watch(routineRepositoryProvider).watchTasks(user.uid);
});

/// Today's tasks, sorted by start time, filtered by [RoutineTask.occursOnWeekday].
final todaysTasksProvider = Provider<List<RoutineTask>>((ref) {
  final tasks = ref.watch(tasksStreamProvider).valueOrNull ?? const [];
  final today = DateTime.now().weekday;
  final todays = tasks.where((t) => t.occursOnWeekday(today)).toList()
    ..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));
  return todays;
});
