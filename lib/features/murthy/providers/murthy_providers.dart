import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../../routines/providers/routine_providers.dart';
import '../data/murthy_repository.dart';
import '../models/daily_progress_entry.dart';
import '../models/daily_protocol.dart';

String todayKey() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return '${now.year}-$month-$day';
}

final murthyRepositoryProvider = Provider<MurthyRepository>(
  (ref) => MurthyRepository(),
);

final dailyProtocolsProvider = StreamProvider<List<DailyProtocol>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref.watch(murthyRepositoryProvider).watchProtocols(user.uid);
});

final todayProgressProvider = StreamProvider<DailyProgressEntry>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref
      .watch(murthyRepositoryProvider)
      .watchProgress(user.uid, todayKey());
});

/// Today's routine-completion count, computed locally from the existing
/// task stream — this never touches the network on its own.
final todayRoutineStatsProvider = Provider<(int completed, int total)>((ref) {
  final todays = ref.watch(todaysTasksProvider);
  final completed = todays.where((t) => t.isCompletedToday).length;
  return (completed, todays.length);
});
