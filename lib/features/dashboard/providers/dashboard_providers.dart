import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../routines/providers/routine_providers.dart';

/// One aggregated slice of today's usage breakdown — one app/site (or the
/// "Other" bucket small ones get folded into).
class UsageSlice {
  const UsageSlice({
    required this.label,
    required this.duration,
    required this.source,
  });

  final String label;
  final Duration duration;

  /// 'chrome' | 'android' | 'desktop' | 'mixed' (an "Other" bucket spanning
  /// more than one source).
  final String source;
}

bool _isToday(DateTime? time) {
  if (time == null) return false;
  final now = DateTime.now();
  return time.year == now.year &&
      time.month == now.month &&
      time.day == now.day;
}

/// Today's activity events only, pulled from the same feed the Activity
/// screen uses but with a higher limit — a busy day can log hundreds of
/// short browser/app sessions, more than that screen's default page size.
/// Kept well under the Activity screen's headroom (not e.g. 2000): on
/// Linux this polls Firestore's REST API every 30s (see
/// `RestActivityRepositoryService`), and each poll's read cost scales
/// directly with this limit — too high a number here burns through
/// Firestore's free-tier daily read quota in hours, not days.
final todayActivityProvider = StreamProvider<List<ActivityEvent>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref
      .watch(activityRepositoryProvider)
      .watchRecentActivity(user.uid, limit: 500)
      .map((events) => events.where((e) => _isToday(e.startedAt)).toList());
});

String _sliceKey(ActivityEvent e) => e.domain ?? e.packageName ?? e.title;

/// Today's usage, grouped by app/site and sorted by time spent (desc), with
/// anything past the top 7 folded into a trailing "Other" slice — keeps the
/// donut/legend readable regardless of how many distinct sites/apps were
/// touched today.
final todayUsageBreakdownProvider = Provider<List<UsageSlice>>((ref) {
  final events = ref.watch(todayActivityProvider).valueOrNull ?? const [];
  if (events.isEmpty) return const [];

  final totals = <String, int>{};
  final sources = <String, Set<String>>{};
  for (final e in events) {
    final key = _sliceKey(e);
    totals[key] = (totals[key] ?? 0) + (e.durationMs ?? 0);
    (sources[key] ??= {}).add(e.source);
  }

  final sorted = totals.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  const topCount = 7;
  final top = sorted.take(topCount);
  final rest = sorted.skip(topCount);

  final slices = [
    for (final entry in top)
      UsageSlice(
        label: entry.key,
        duration: Duration(milliseconds: entry.value),
        source: sources[entry.key]!.length == 1
            ? sources[entry.key]!.first
            : 'mixed',
      ),
  ];

  if (rest.isNotEmpty) {
    final otherMs = rest.fold<int>(0, (sum, e) => sum + e.value);
    slices.add(
      UsageSlice(
        label: 'Other (${rest.length} more)',
        duration: Duration(milliseconds: otherMs),
        source: 'mixed',
      ),
    );
  }

  return slices;
});

final todayTotalTrackedProvider = Provider<Duration>((ref) {
  final slices = ref.watch(todayUsageBreakdownProvider);
  return slices.fold(Duration.zero, (sum, s) => sum + s.duration);
});

/// Today's routine-completion count, computed locally from the existing
/// task stream — same shape as Murthy's own stat, kept here too so the
/// dashboard doesn't depend on the Murthy feature.
final dashboardRoutineStatsProvider = Provider<(int completed, int total)>((
  ref,
) {
  final todays = ref.watch(todaysTasksProvider);
  final completed = todays.where((t) => t.isCompletedForToday).length;
  return (completed, todays.length);
});
