import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/dashboard_providers.dart';
import '../widgets/usage_donut_chart.dart';

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (hours == 0) return '${minutes}m';
  if (minutes == 0) return '${hours}h';
  return '${hours}h ${minutes}m';
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(todayActivityProvider);
    final slices = ref.watch(todayUsageBreakdownProvider);
    final total = ref.watch(todayTotalTrackedProvider);
    final (completed, totalTasks) = ref.watch(dashboardRoutineStatsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: activityAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Couldn\'t load activity: $error')),
        data: (_) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatRow(
              completed: completed,
              totalTasks: totalTasks,
              tracked: total,
            ),
            const SizedBox(height: 16),
            if (slices.isEmpty)
              const _EmptyState()
            else ...[
              _UsageCard(slices: slices, total: total),
              const SizedBox(height: 16),
              _RankedList(slices: slices, total: total),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.completed,
    required this.totalTasks,
    required this.tracked,
  });

  final int completed;
  final int totalTasks;
  final Duration tracked;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Tasks today',
            value: '$completed/$totalTasks',
            sub: totalTasks == 0 ? 'nothing scheduled' : 'completed',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Tracked today',
            value: _formatDuration(tracked),
            sub: 'app + browser activity',
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(sub, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.slices, required this.total});

  final List<UsageSlice> slices;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where the time went',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Share of today\'s ${_formatDuration(total)} tracked, by app / site',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: UsageDonutChart(
                slices: slices,
                centerLabel: _formatDuration(total),
              ),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < slices.length; i++)
              _LegendRow(index: i, slice: slices[i], total: total),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.index,
    required this.slice,
    required this.total,
  });

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
            child: Text(
              slice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$pct%', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
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

class _RankedList extends StatelessWidget {
  const _RankedList({required this.slices, required this.total});

  final List<UsageSlice> slices;
  final Duration total;

  @override
  Widget build(BuildContext context) {
    final maxMs = slices
        .map((s) => s.duration.inMilliseconds)
        .reduce((a, b) => a > b ? a : b);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ranked by time spent',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < slices.length; i++) ...[
              _RankRow(index: i, slice: slices[i], maxMs: maxMs),
              if (i != slices.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.index,
    required this.slice,
    required this.maxMs,
  });

  final int index;
  final UsageSlice slice;
  final int maxMs;

  @override
  Widget build(BuildContext context) {
    final isOther = slice.label.startsWith('Other');
    final fraction = maxMs == 0 ? 0.0 : slice.duration.inMilliseconds / maxMs;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                slice.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              _formatDuration(slice.duration),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 5,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(colorForSlice(index, isOther)),
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.bar_chart_outlined, size: 40),
            const SizedBox(height: 12),
            const Text(
              'No activity tracked yet today.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Enable tracking from the Activity screen to see today\'s breakdown here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
