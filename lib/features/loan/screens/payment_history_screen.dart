import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/loan.dart';
import '../models/loan_payment.dart';
import '../providers/loan_providers.dart';

String _money(double v) => '₹${v.toStringAsFixed(0)}';
String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Full payment ledger for one loan — every logged payment, newest first,
/// grouped by year with a per-year subtotal and a running "paid so far"
/// total. The loan screen's card only shows a handful inline; this is the
/// complete audit trail behind it.
class PaymentHistoryScreen extends ConsumerWidget {
  const PaymentHistoryScreen({super.key, required this.loanId});

  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider).valueOrNull ?? const [];
    Loan? loan;
    for (final l in loans) {
      if (l.id == loanId) {
        loan = l;
        break;
      }
    }
    final paymentsAsync = ref.watch(loanPaymentsProvider(loanId));

    return Scaffold(
      appBar: AppBar(
        title: Text(loan == null ? 'Payments' : '${loan.name} · Payments'),
      ),
      body: paymentsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Couldn\'t load payments: $error')),
        data: (payments) {
          if (payments.isEmpty) {
            return const Center(child: Text('No payments logged yet.'));
          }

          final sorted = payments.toList()
            ..sort((a, b) => b.paidDate.compareTo(a.paidDate));
          final totalPaid = payments.fold<double>(0, (s, p) => s + p.amount);

          // Group into year -> list of payments (already newest-first).
          final byYear = <int, List<LoanPayment>>{};
          for (final p in sorted) {
            (byYear[p.paidDate.year] ??= []).add(p);
          }
          final years = byYear.keys.toList()..sort((a, b) => b.compareTo(a));

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _SummaryHeader(count: payments.length, total: totalPaid)),
              for (final year in years) ...[
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _YearHeaderDelegate(
                    year: year,
                    subtotal: byYear[year]!.fold<double>(0, (s, p) => s + p.amount),
                    count: byYear[year]!.length,
                  ),
                ),
                SliverList.builder(
                  itemCount: byYear[year]!.length,
                  itemBuilder: (context, i) => _PaymentRow(
                    payment: byYear[year]![i],
                    loanId: loanId,
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.count, required this.total});

  final int count;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL PAID',
                      style: theme.textTheme.labelSmall?.copyWith(
                        letterSpacing: 0.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(_money(total), style: theme.textTheme.headlineSmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'PAYMENTS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text('$count', style: theme.textTheme.headlineSmall),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearHeaderDelegate extends SliverPersistentHeaderDelegate {
  _YearHeaderDelegate({required this.year, required this.subtotal, required this.count});

  final int year;
  final double subtotal;
  final int count;

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            '$year',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 8),
          Text(
            '· $count payment${count == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
          const Spacer(),
          Text(
            _money(subtotal),
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _YearHeaderDelegate oldDelegate) =>
      oldDelegate.year != year || oldDelegate.subtotal != subtotal || oldDelegate.count != count;
}

class _PaymentRow extends ConsumerWidget {
  const _PaymentRow({required this.payment, required this.loanId});

  final LoanPayment payment;
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final d = payment.paidDate;
    return Dismissible(
      key: ValueKey(payment.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Delete this payment?'),
          content: Text('${_money(payment.amount)} on ${_date(d)}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) async {
        final user = ref.read(currentUserProvider);
        if (user.isEmpty) return;
        await ref.read(loanRepositoryProvider).deletePayment(user.uid, loanId, payment.id);
      },
      child: ListTile(
        dense: true,
        leading: SizedBox(
          width: 44,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _monthNames[d.month - 1],
                style: theme.textTheme.labelSmall,
              ),
              Text(
                '${d.day}',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        title: Text(payment.note.isEmpty ? 'Payment' : payment.note),
        trailing: Text(
          _money(payment.amount),
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
