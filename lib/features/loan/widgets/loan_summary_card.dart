import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../logic/loan_calculator.dart';
import '../providers/loan_providers.dart';

String _money(double v) => '₹${v.toStringAsFixed(0)}';

/// Dashboard card: remaining balance / pending months / pending amount for
/// every loan being tracked, tapping through to the full Loans screen.
class LoanSummaryCard extends ConsumerWidget {
  const LoanSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaries = ref.watch(allLoanSummariesProvider);
    final theme = Theme.of(context);

    if (summaries.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.account_balance_outlined),
          title: const Text('No loans tracked yet'),
          subtitle: const Text('Add a loan to see remaining balance here.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/loan'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Loans', style: theme.textTheme.titleMedium),
                TextButton(
                  onPressed: () => context.push('/loan'),
                  child: const Text('Manage'),
                ),
              ],
            ),
            for (final summary in summaries) ...[
              const Divider(height: 20),
              _LoanRow(summary: summary),
            ],
          ],
        ),
      ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({required this.summary});

  final LoanSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loan = summary.loan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loan.name,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (summary.isPaidOff)
              Chip(
                label: const Text('Paid off'),
                visualDensity: VisualDensity.compact,
                backgroundColor: theme.colorScheme.primaryContainer,
              ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: loan.tenureMonths == 0
              ? 0
              : summary.monthsPaid / loan.tenureMonths,
          minHeight: 6,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _MiniStat(label: 'Remaining', value: _money(summary.outstandingPrincipal)),
            _MiniStat(
              label: 'Pending months',
              value: '${summary.monthsPending} / ${loan.tenureMonths}',
            ),
            _MiniStat(label: 'Pending amount', value: _money(summary.pendingAmount)),
            if (loan.insurancePremium != null)
              _MiniStat(
                label: 'Insurance',
                value: _money(loan.insurancePremium!),
              ),
          ],
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.5,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
