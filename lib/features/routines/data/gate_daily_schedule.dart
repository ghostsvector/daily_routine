import 'package:daily_routine_sdk/daily_routine_sdk.dart';

/// The user's own GATE-prep / job-search / freelancing / TryHackMe daily
/// timetable (04:00–22:00), breaks included. Fixed, deterministic ids so
/// loading this twice upserts the same 17 tasks instead of duplicating them.
///
/// The 04:00 GATE block is the one task marked [RoutineTask.isAlarm] — it's
/// the one you can't afford to sleep through. Freelancing is trimmed to one
/// short client check-in since that workload is minimal right now; widen it
/// back out once more client work lands.
List<RoutineTask> buildGateDailySchedule() => const [
  RoutineTask(
    id: 'schedule-gate-core',
    title: 'GATE core theory',
    startMinuteOfDay: 240, // 4:00 AM
    durationMinutes: 120, // -> 6:00 AM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    isAlarm: true,
    notes: 'Deepest study window of the day — new concepts, fresh mind.',
  ),
  RoutineTask(
    id: 'schedule-break-stretch',
    title: 'Stretch & hydrate',
    startMinuteOfDay: 360, // 6:00 AM
    durationMinutes: 20, // -> 6:20 AM
    category: TaskCategory.mindfulness,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-gate-practice',
    title: 'Practice problems / PYQs',
    startMinuteOfDay: 380, // 6:20 AM
    durationMinutes: 100, // -> 8:00 AM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: 'Apply what you just studied while it\'s still fresh.',
  ),
  RoutineTask(
    id: 'schedule-break-breakfast',
    title: 'Breakfast',
    startMinuteOfDay: 480, // 8:00 AM
    durationMinutes: 45, // -> 8:45 AM
    category: TaskCategory.health,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-job-search',
    title: 'Search & apply',
    startMinuteOfDay: 525, // 8:45 AM
    durationMinutes: 90, // -> 10:15 AM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
    notes: 'LinkedIn, Naukri, company sites — tailor resume and cover letter per role.',
  ),
  RoutineTask(
    id: 'schedule-break-walk-short',
    title: 'Short walk',
    startMinuteOfDay: 615, // 10:15 AM
    durationMinutes: 15, // -> 10:30 AM
    category: TaskCategory.health,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-tryhackme-rooms',
    title: 'Rooms & labs',
    startMinuteOfDay: 630, // 10:30 AM
    durationMinutes: 120, // -> 12:30 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: 'Work through rooms in sequence; keep a written note of techniques used.',
  ),
  RoutineTask(
    id: 'schedule-break-lunch',
    title: 'Lunch',
    startMinuteOfDay: 750, // 12:30 PM
    durationMinutes: 60, // -> 1:30 PM
    category: TaskCategory.health,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-gate-mock',
    title: 'Mock test / weak topics',
    startMinuteOfDay: 810, // 1:30 PM
    durationMinutes: 120, // -> 3:30 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: "Timed practice, or drill whatever the morning session exposed as weak. "
        'Swap for a full timed GATE mock once a week.',
  ),
  RoutineTask(
    id: 'schedule-break-reset',
    title: 'Reset',
    startMinuteOfDay: 930, // 3:30 PM
    durationMinutes: 20, // -> 3:50 PM
    category: TaskCategory.mindfulness,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-freelancing-checkin',
    title: 'Freelancing — client check-in',
    startMinuteOfDay: 950, // 3:50 PM
    durationMinutes: 35, // -> 4:25 PM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
    notes: "Quick pass only: reply to messages, flag open work, one proposal if "
        "there's time. Kept short — this is the minimal track right now.",
  ),
  RoutineTask(
    id: 'schedule-break-walk-exercise',
    title: 'Walk / light exercise',
    startMinuteOfDay: 985, // 4:25 PM
    durationMinutes: 30, // -> 4:55 PM
    category: TaskCategory.health,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-tryhackme-ctf',
    title: 'CTF practice',
    startMinuteOfDay: 1015, // 4:55 PM
    durationMinutes: 120, // -> 6:55 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: 'Deeper practice block — picked up the time trimmed from freelancing.',
  ),
  RoutineTask(
    id: 'schedule-break-dinner',
    title: 'Dinner',
    startMinuteOfDay: 1135, // 6:55 PM
    durationMinutes: 60, // -> 7:55 PM
    category: TaskCategory.health,
    repeatRule: RepeatRule.daily,
  ),
  RoutineTask(
    id: 'schedule-job-followups',
    title: 'Follow-ups & outreach',
    startMinuteOfDay: 1195, // 7:55 PM
    durationMinutes: 65, // -> 9:00 PM
    category: TaskCategory.work,
    repeatRule: RepeatRule.daily,
    notes: 'Reply to recruiters, LinkedIn networking, referral asks.',
  ),
  RoutineTask(
    id: 'schedule-gate-revision',
    title: 'Revision',
    startMinuteOfDay: 1260, // 9:00 PM
    durationMinutes: 50, // -> 9:50 PM
    category: TaskCategory.study,
    repeatRule: RepeatRule.daily,
    notes: "Formula review, flashcards, or a pass over today's mistakes — nothing new.",
  ),
  RoutineTask(
    id: 'schedule-journal',
    title: 'Journal & plan tomorrow',
    startMinuteOfDay: 1310, // 9:50 PM
    durationMinutes: 10, // -> 10:00 PM
    category: TaskCategory.personal,
    repeatRule: RepeatRule.daily,
  ),
];
