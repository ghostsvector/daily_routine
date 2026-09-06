import 'package:daily_routine_sdk/daily_routine_sdk.dart';
import 'package:flutter/foundation.dart' show debugPrint;

const _logName = 'ActivityRolloverService';

String _dateKey(DateTime dt) {
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  return '${dt.year}-$month-$day';
}

String _sliceKey(ActivityEvent e) => e.domain ?? e.packageName ?? e.title;

/// Folds every past day's raw activity events into one small
/// [ActivitySummary] per day, then deletes those raw events — so the
/// `activity` collection never accumulates more than about a day's worth
/// of documents, regardless of how long the app has been logging. Also
/// folds in that day's routine-task completion count, since
/// [RoutineTask.isCompletedToday]/[RoutineTask.completedDate] only ever
/// reflect the most recent day a task was toggled — once the calendar
/// moves past a day, "how many tasks did I finish that day" has nowhere
/// else to live unless it's captured here, at rollover time, while
/// `completedDate` still says that day.
///
/// Runs at most once per calendar day, tracked via a single shared marker
/// doc (`getLastRolloverDate`/`setLastRolloverDate`) so multiple devices
/// signed into the same account don't each redundantly re-scan the whole
/// collection — whichever device happens to run this first each day does
/// it for all of them. Today's own events are never touched; only days
/// strictly before today get summarized and pruned.
///
/// This exists because the raw log growing without bound is what caused
/// this app to blow through Firestore's free-tier read quota — every poll
/// of the (REST-backed, Linux) activity feed cost more the larger the
/// collection got. Capping the collection's size caps that cost
/// permanently, independent of any poll-interval/limit tuning.
///
/// Every step here prints via [debugPrint] rather than `dart:developer`'s
/// `log()` — the latter is silently dropped in a release build with no
/// debugger attached (i.e. exactly the installed .deb/.apk a real user
/// runs), so it would never actually reach anyone trying to watch this run
/// from a terminal.
Future<void> runActivityRollover(
  ActivityRepositoryService activityRepo,
  RoutineRepositoryService routineRepo,
  String uid,
) async {
  final today = _dateKey(DateTime.now());

  final lastRolloverResult = await activityRepo.getLastRolloverDate(uid);
  final lastRollover = lastRolloverResult.fold((v) => v, (e) {
    debugPrint('[$_logName] getLastRolloverDate failed: $e');
    return null;
  });
  if (lastRollover == today) {
    debugPrint('[$_logName] Already rolled over today ($today) — skipping');
    return;
  }

  final eventsResult = await activityRepo.fetchAllEvents(uid);
  final events = eventsResult.fold((v) => v, (e) {
    debugPrint('[$_logName] fetchAllEvents failed, skipping this run: $e');
    return null;
  });
  if (events == null) return;

  final byDay = <String, List<ActivityEvent>>{};
  for (final event in events) {
    final startedAt = event.startedAt;
    if (startedAt == null) continue;
    final day = _dateKey(startedAt);
    if (day == today) continue;
    (byDay[day] ??= []).add(event);
  }

  // One-shot read of the current task list — used only to count, for each
  // past day being rolled over, how many tasks had completedDate == that
  // day. This doesn't need to be watched/live; it's read once per rollover
  // run (at most once a day).
  final tasks = await routineRepo.watchTasks(uid).first;

  debugPrint(
    '[$_logName] Rolling over ${byDay.length} past day(s), ${events.length} raw event(s) total',
  );

  for (final entry in byDay.entries) {
    final date = entry.key;
    final dayEvents = entry.value;

    final totals = <String, int>{};
    final sources = <String, Set<String>>{};
    for (final event in dayEvents) {
      final key = _sliceKey(event);
      totals[key] = (totals[key] ?? 0) + (event.durationMs ?? 0);
      (sources[key] ??= {}).add(event.source);
    }

    final summaryEntries = totals.entries
        .map(
          (e) => ActivitySummaryEntry(
            label: e.key,
            durationMs: e.value,
            source: sources[e.key]!.length == 1 ? sources[e.key]!.first : 'mixed',
          ),
        )
        .toList()
      ..sort((a, b) => b.durationMs.compareTo(a.durationMs));

    // Known gap, not fixed here: if the app goes multiple days without
    // running rollover and the *same* task gets completed on more than one
    // of those backlogged days, only the most recent day's completion
    // survives — completedDate gets overwritten each time a task is
    // checked off, so an earlier day's mark is lost once a later day's
    // overwrites it before rollover ever sees the earlier one. Fixing this
    // properly would need a real per-completion history log, not just the
    // single completedDate field RoutineTask has. Low-impact in practice
    // since rollover runs every time the app is opened, not just once a
    // day on a schedule — this only bites if the app is closed across
    // multiple calendar days in a row.
    final dayWeekday = DateTime.parse(date).weekday;
    final tasksScheduled = tasks.where((t) => t.occursOnWeekday(dayWeekday)).length;
    final tasksCompleted = tasks.where((t) => t.completedDate == date).length;

    final summary = ActivitySummary(
      date: date,
      totalDurationMs: dayEvents.fold(0, (sum, e) => sum + (e.durationMs ?? 0)),
      entries: summaryEntries,
      eventCount: dayEvents.length,
      tasksCompleted: tasksCompleted,
      tasksScheduled: tasksScheduled,
      computedAt: DateTime.now(),
    );

    final saveResult = await activityRepo.saveDailySummary(uid, summary);
    if (saveResult.isFailure) {
      saveResult.fold((_) {}, (error) {
        debugPrint(
          '[$_logName] Failed to save summary for $date — leaving its raw events in '
          'place. Cause: $error (if this says permission-denied, the Firestore rules '
          "for activitySummaries/meta haven't been deployed yet — see README)",
        );
      });
      continue;
    }

    await activityRepo.deleteEvents(uid, dayEvents.map((e) => e.id).toList());
    debugPrint(
      '[$_logName] Rolled over $date: ${dayEvents.length} event(s), '
      '$tasksCompleted/$tasksScheduled task(s) completed',
    );
  }

  await activityRepo.setLastRolloverDate(uid, today);
}
