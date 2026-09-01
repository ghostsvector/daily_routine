import 'package:daily_routine_sdk/daily_routine_sdk.dart';

/// The user's own GATE-prep / job-search / freelancing / TryHackMe daily
/// timetable (04:00–22:00). Fixed, deterministic ids so loading this twice
/// upserts the same 10 tasks instead of duplicating them.
///
/// The 04:00 GATE block is the one task marked [RoutineTask.isAlarm] — it's
/// the one you can't afford to sleep through.
List<RoutineTask> buildGateDailySchedule() => const [
  RoutineTask(
    id: 'schedule-gate-core',
    title: 'GATE core theory + PYQs/practice',
    startMinuteOfDay: 240, // 4:00 AM
    durationMinutes: 240, // -> 8:00 AM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    isAlarm: true,
    notes: 'Heaviest cognitive load first, before the day wears you down.',
  ),
  RoutineTask(
    id: 'schedule-job-applications',
    title: 'Job applications',
    startMinuteOfDay: 525, // 8:45 AM
    durationMinutes: 90, // -> 10:15 AM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
    notes: 'Search & apply, tailored resume/cover letter.',
  ),
  RoutineTask(
    id: 'schedule-tryhackme-rooms',
    title: 'TryHackMe rooms & labs',
    startMinuteOfDay: 630, // 10:30 AM
    durationMinutes: 90, // -> 12:00 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-freelancing-client',
    title: 'Freelancing — client work',
    startMinuteOfDay: 780, // 1:00 PM
    durationMinutes: 90, // -> 2:30 PM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
    notes: 'Client work first, then proposals.',
  ),
  RoutineTask(
    id: 'schedule-gate-mock',
    title: 'GATE mock test / weak-topic drilling',
    startMinuteOfDay: 890, // 2:50 PM
    durationMinutes: 100, // -> 4:30 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: 'Do a full timed GATE mock once a week instead of the regular drilling.',
  ),
  RoutineTask(
    id: 'schedule-tryhackme-ctf',
    title: 'TryHackMe CTF practice',
    startMinuteOfDay: 1020, // 5:00 PM
    durationMinutes: 75, // -> 6:15 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: 'Swap for freelancing if a deadline is closer.',
  ),
  RoutineTask(
    id: 'schedule-freelancing-wrapup',
    title: 'Freelancing wrap-up',
    startMinuteOfDay: 1155, // 7:15 PM
    durationMinutes: 75, // -> 8:30 PM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-job-followups',
    title: 'Job follow-ups / networking',
    startMinuteOfDay: 1230, // 8:30 PM
    durationMinutes: 60, // -> 9:30 PM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-gate-revision',
    title: 'Light GATE revision',
    startMinuteOfDay: 1290, // 9:30 PM
    durationMinutes: 20, // -> 9:50 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-journal',
    title: 'Journal + plan tomorrow',
    startMinuteOfDay: 1310, // 9:50 PM
    durationMinutes: 10, // -> 10:00 PM
    category: TaskCategory.personal,
    repeatRule: RepeatRule.daily,
  ),
];
