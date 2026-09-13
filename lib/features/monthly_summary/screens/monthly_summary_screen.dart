import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dashboard/providers/dashboard_providers.dart';
import '../../dashboard/widgets/usage_donut_chart.dart';
import '../providers/monthly_summary_providers.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

/// Everything rolled up for a chosen calendar month — routine-task
/// completion rate and total tracked activity, both built from the daily
/// [ActivitySummary] docs `ActivityRolloverService` already writes (works
/// on desktop and mobile alike; this screen is just a different window onto
/// the same per-day rollups the dashboard already relies on for "today").
class MonthlySummaryScreen extends ConsumerWidget {
  const MonthlySummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedSummaryMonthProvider);
    final summariesAsync = ref.watch(monthlySummariesProvider(month));
    final totals = ref.watch(monthlyTotalsProvider(month));

    final now = DateTime.now();
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    return Scaffold(
      appBar: AppBar(title: const Text('Monthly Summary')),
      body: Column(
        children: [
          _MonthSelector(month: month, canGoForward: !isCurrentMonth),
          Expanded(
            child: summariesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) =>
                  Center(child: Text('Couldn\'t load summary: $error')),
              data: (summaries) {
                if (summaries.isEmpty) {
                  return const _EmptyState();
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _TaskCompletionCard(totals: totals),
                    const SizedBox(height: 16),
                    if (totals.slices.isEmpty)
                      const _NoActivityCard()
                    else
                      _ActivityCard(totals: totals),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSelector extends ConsumerWidget {
  const _MonthSelector({required this.month, required this.canGoForward});

  final DateTime month;
  final bool canGoForward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
            onPressed: () => ref.read(selectedSummaryMonthProvider.notifier).state =
                DateTime(month.year, month.month - 1),
          ),
          Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
            onPressed: canGoForward
                ? () => ref.read(selectedSummaryMonthProvider.notifier).state =
                      DateTime(month.year, month.month + 1)
                : null,
          ),
        ],
      ),
    );
  }
}

class _TaskCompletionCard extends StatelessWidget {
  const _TaskCompletionCard({required this.totals});

  final MonthlyTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (totals.completionRate * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Routine tasks', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${totals.daysWithData} day${totals.daysWithData == 1 ? '' : 's'} of data this month',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${totals.tasksCompleted} / ${totals.tasksScheduled}',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text('tasks completed', style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(
                  '$pct%',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: totals.completionRate,
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.totals});

  final MonthlyTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity tracked', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Total: ${_formatDuration(totals.totalDuration)} across the month',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Center(
              child: SizedBox(
                width: 200,
                child: UsageDonutChart(
                  slices: totals.slices,
                  centerLabel: _formatDuration(totals.totalDuration),
                ),
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < totals.slices.length; i++)
              _LegendRow(index: i, slice: totals.slices[i], total: totals.totalDuration),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.index, required this.slice, required this.total});

  final int index;
  final UsageSlice slice;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final isOther = slice.label.startsWith('Other');
    final pct = total.inMilliseconds == 0
        ? 0
        : (slice.duration.inMilliseconds / total.inMilliseconds * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colorForSlice(index, isOther),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(slice.label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Text('$pct%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: Text(
              _formatDuration(slice.duration),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoActivityCard extends StatelessWidget {
  const _NoActivityCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text('No activity tracked this month yet.'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('No data for this month yet.', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Summaries build up day by day as the app rolls over past days\' '
              'activity and task completion — check back once a full day has passed.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
