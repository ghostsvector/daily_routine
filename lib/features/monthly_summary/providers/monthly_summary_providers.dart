import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/providers/auth_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';

/// The month currently shown on the Monthly Summary screen — defaults to
/// the current month, changed via the screen's prev/next controls.
final selectedSummaryMonthProvider = StateProvider<DateTime>(
  (ref) => DateTime(DateTime.now().year, DateTime.now().month),
);

String _dateKey(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$month-$day';
}

/// Every past day's [ActivitySummary] within [month], one Firestore read per
/// day (there's no bulk range query on the SDK's repository) — cheap in
/// practice since this only runs when the screen opens, not continuously.
/// Today never has a summary yet (rollover only summarizes days strictly
/// before today — see `ActivityRolloverService`), so today's data never
/// shows up here even for the current month; that's expected, not a bug.
final monthlySummariesProvider = FutureProvider.autoDispose
    .family<List<ActivitySummary>, DateTime>((ref, month) async {
      final user = ref.watch(currentUserProvider);
      if (user.isEmpty) return const [];
      final repo = ref.watch(activityRepositoryProvider);

      final firstOfMonth = DateTime(month.year, month.month);
      final firstOfNextMonth = DateTime(month.year, month.month + 1);
      final today = DateTime.now();
      final lastDay = firstOfNextMonth.isBefore(today) ? firstOfNextMonth : today;

      final days = <DateTime>[];
      for (var d = firstOfMonth; d.isBefore(lastDay); d = d.add(const Duration(days: 1))) {
        days.add(d);
      }

      final results = await Future.wait(
        days.map((d) => repo.getDailySummary(user.uid, _dateKey(d))),
      );

      return results
          .map((r) => r.fold((v) => v, (_) => null))
          .whereType<ActivitySummary>()
          .toList()
        ..sort((a, b) => a.date.compareTo(b.date));
    });

/// Rolled-up totals for a month's worth of [ActivitySummary]s: routine-task
/// completion and total activity time, both summed across every day that
/// has a summary.
class MonthlyTotals {
  const MonthlyTotals({
    required this.tasksCompleted,
    required this.tasksScheduled,
    required this.totalDuration,
    required this.daysWithData,
    required this.slices,
  });

  final int tasksCompleted;
  final int tasksScheduled;
  final Duration totalDuration;
  final int daysWithData;
  final List<UsageSlice> slices;

  double get completionRate => tasksScheduled == 0 ? 0 : tasksCompleted / tasksScheduled;
}

final monthlyTotalsProvider = Provider.autoDispose.family<MonthlyTotals, DateTime>((
  ref,
  month,
) {
  final summaries = ref.watch(monthlySummariesProvider(month)).valueOrNull ?? const [];

  var tasksCompleted = 0;
  var tasksScheduled = 0;
  var totalMs = 0;
  final byLabel = <String, int>{};
  final sourcesByLabel = <String, Set<String>>{};

  for (final s in summaries) {
    tasksCompleted += s.tasksCompleted ?? 0;
    tasksScheduled += s.tasksScheduled ?? 0;
    totalMs += s.totalDurationMs;
    for (final e in s.entries) {
      byLabel[e.label] = (byLabel[e.label] ?? 0) + e.durationMs;
      (sourcesByLabel[e.label] ??= {}).add(e.source);
    }
  }

  final sorted = byLabel.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  const topCount = 7;
  final top = sorted.take(topCount);
  final rest = sorted.skip(topCount);

  final slices = [
    for (final entry in top)
      UsageSlice(
        label: entry.key,
        duration: Duration(milliseconds: entry.value),
        source: sourcesByLabel[entry.key]!.length == 1
            ? sourcesByLabel[entry.key]!.first
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

  return MonthlyTotals(
    tasksCompleted: tasksCompleted,
    tasksScheduled: tasksScheduled,
    totalDuration: Duration(milliseconds: totalMs),
    daysWithData: summaries.length,
    slices: slices,
  );
});
