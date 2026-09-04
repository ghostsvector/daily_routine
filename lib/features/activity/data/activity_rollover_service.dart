import 'dart:developer' as developer;

import 'package:daily_routine_sdk/daily_routine_sdk.dart';

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
/// of documents, regardless of how long the app has been logging.
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
Future<void> runActivityRollover(ActivityRepositoryService repo, String uid) async {
  final today = _dateKey(DateTime.now());

  final lastRolloverResult = await repo.getLastRolloverDate(uid);
  final lastRollover = lastRolloverResult.fold((v) => v, (e) => null);
  if (lastRollover == today) {
    developer.log('Already rolled over today ($today) — skipping', name: _logName);
    return;
  }

  final eventsResult = await repo.fetchAllEvents(uid);
  final events = eventsResult.fold((v) => v, (e) {
    developer.log('fetchAllEvents failed, skipping this run', name: _logName, error: e);
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

  developer.log(
    'Rolling over ${byDay.length} past day(s), ${events.length} raw event(s) total',
    name: _logName,
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

    final summary = ActivitySummary(
      date: date,
      totalDurationMs: dayEvents.fold(0, (sum, e) => sum + (e.durationMs ?? 0)),
      entries: summaryEntries,
      eventCount: dayEvents.length,
      computedAt: DateTime.now(),
    );

    final saveResult = await repo.saveDailySummary(uid, summary);
    if (saveResult.isFailure) {
      developer.log('Failed to save summary for $date — leaving its raw events in place', name: _logName);
      continue;
    }

    await repo.deleteEvents(uid, dayEvents.map((e) => e.id).toList());
    developer.log('Rolled over $date: ${dayEvents.length} event(s) summarized and deleted', name: _logName);
  }

  await repo.setLastRolloverDate(uid, today);
}
