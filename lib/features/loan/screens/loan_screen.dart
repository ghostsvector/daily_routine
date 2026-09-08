import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/providers/auth_providers.dart';
import '../models/loan.dart';
import '../models/loan_payment.dart';
import '../providers/loan_providers.dart';

String _money(double v) => '₹${v.toStringAsFixed(0)}';

/// Loans — create a loan (principal/rate/tenure, or a known EMI directly),
/// log payments against it, and see remaining balance / pending months /
/// pending amount at a glance. The same summary also feeds the dashboard
/// card — see `allLoanSummariesProvider`.
class LoanScreen extends ConsumerWidget {
  const LoanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loansProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Loans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create loan',
            onPressed: () => _showEditLoanDialog(context, ref),
          ),
        ],
      ),
      body: loansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Couldn\'t load loans: $error')),
        data: (loans) {
          if (loans.isEmpty) {
            return _EmptyState(
              onCreate: () => _showEditLoanDialog(context, ref),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: loans.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _LoanCard(loan: loans[i]),
            ),
          );
        },
      ),
    );
  }

  static void _showEditLoanDialog(
    BuildContext context,
    WidgetRef ref, {
    Loan? existing,
  }) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final principalController = TextEditingController(
      text: existing != null ? existing.principal.toStringAsFixed(0) : '',
    );
    final rateController = TextEditingController(
      text: existing?.annualInterestRate?.toString() ?? '',
    );
    final tenureController = TextEditingController(
      text: existing != null ? existing.tenureMonths.toString() : '',
    );
    final emiController = TextEditingController(
      text: existing?.emiOverride?.toStringAsFixed(0) ?? '',
    );
    var startDate = existing?.startDate ?? DateTime.now();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(existing == null ? 'Create loan' : 'Edit loan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Home Loan - Dad',
                  ),
                  autofocus: true,
                ),
                TextField(
                  controller: principalController,
                  decoration: const InputDecoration(
                    labelText: 'Principal (loan amount)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                TextField(
                  controller: rateController,
                  decoration: const InputDecoration(
                    labelText: 'Annual interest rate % (optional)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                TextField(
                  controller: tenureController,
                  decoration: const InputDecoration(
                    labelText: 'Tenure (months)',
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: emiController,
                  decoration: const InputDecoration(
                    labelText: 'Known EMI (optional — overrides computed EMI)',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Start date'),
                  subtitle: Text(
                    '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}',
                  ),
                  trailing: const Icon(Icons.calendar_today, size: 18),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: startDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => startDate = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final user = ref.read(currentUserProvider);
                final principal = double.tryParse(principalController.text.trim());
                final tenure = int.tryParse(tenureController.text.trim());
                if (user.isEmpty ||
                    nameController.text.trim().isEmpty ||
                    principal == null ||
                    tenure == null ||
                    tenure <= 0) {
                  return;
                }
                final rate = double.tryParse(rateController.text.trim());
                final emiOverride = double.tryParse(emiController.text.trim());
                final loan = Loan(
                  id: existing?.id ?? const Uuid().v4(),
                  name: nameController.text.trim(),
                  principal: principal,
                  annualInterestRate: rate,
                  tenureMonths: tenure,
                  startDate: startDate,
                  emiOverride: emiOverride,
                  createdAt: existing?.createdAt,
                );
                await ref.read(loanRepositoryProvider).upsertLoan(user.uid, loan);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanCard extends ConsumerWidget {
  const _LoanCard({required this.loan});

  final Loan loan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(loanSummaryProvider(loan.id));
    final paymentsAsync = ref.watch(loanPaymentsProvider(loan.id));
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(loan.name, style: theme.textTheme.titleMedium),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    final user = ref.read(currentUserProvider);
                    if (user.isEmpty) return;
                    if (value == 'edit') {
                      LoanScreen._showEditLoanDialog(
                        context,
                        ref,
                        existing: loan,
                      );
                    } else if (value == 'delete') {
                      await ref
                          .read(loanRepositoryProvider)
                          .deleteLoan(user.uid, loan.id);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            if (summary != null) ...[
              const SizedBox(height: 8),
              if (summary.isPaidOff)
                Chip(
                  label: const Text('Paid off'),
                  backgroundColor: theme.colorScheme.primaryContainer,
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _Stat(label: 'EMI', value: _money(summary.emi)),
                  _Stat(
                    label: 'Remaining balance',
                    value: _money(summary.outstandingPrincipal),
                  ),
                  _Stat(
                    label: 'Pending months',
                    value: '${summary.monthsPending} / ${loan.tenureMonths}',
                  ),
                  _Stat(
                    label: 'Pending amount',
                    value: _money(summary.pendingAmount),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: loan.tenureMonths == 0
                    ? 0
                    : summary.monthsPaid / loan.tenureMonths,
                minHeight: 6,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Payments', style: theme.textTheme.labelLarge),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Log payment'),
                  onPressed: () => _showAddPaymentDialog(context, ref, loan.id),
                ),
              ],
            ),
            paymentsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (error, stack) => Text('Couldn\'t load payments: $error'),
              data: (payments) {
                if (payments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No payments logged yet.'),
                  );
                }
                final recent = payments.reversed.take(5).toList();
                return Column(
                  children: recent
                      .map(
                        (p) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(_money(p.amount)),
                          subtitle: Text(
                            '${p.paidDate.year}-${p.paidDate.month.toString().padLeft(2, '0')}-${p.paidDate.day.toString().padLeft(2, '0')}'
                            '${p.note.isNotEmpty ? ' · ${p.note}' : ''}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              final user = ref.read(currentUserProvider);
                              if (user.isEmpty) return;
                              await ref
                                  .read(loanRepositoryProvider)
                                  .deletePayment(user.uid, loan.id, p.id);
                            },
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static void _showAddPaymentDialog(
    BuildContext context,
    WidgetRef ref,
    String loanId,
  ) {
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var paidDate = DateTime.now();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: const Text('Log payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: const InputDecoration(labelText: 'Amount'),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Date'),
                subtitle: Text(
                  '${paidDate.year}-${paidDate.month.toString().padLeft(2, '0')}-${paidDate.day.toString().padLeft(2, '0')}',
                ),
                trailing: const Icon(Icons.calendar_today, size: 18),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: paidDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => paidDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final user = ref.read(currentUserProvider);
                final amount = double.tryParse(amountController.text.trim());
                if (user.isEmpty || amount == null || amount <= 0) return;
                final payment = LoanPayment(
                  id: const Uuid().v4(),
                  loanId: loanId,
                  amount: amount,
                  paidDate: paidDate,
                  note: noteController.text.trim(),
                );
                await ref.read(loanRepositoryProvider).addPayment(user.uid, payment);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

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
        Text(value, style: theme.textTheme.titleMedium),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('No loans yet.', textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Add your home loan\'s principal, rate & tenure (or a known EMI) '
              'to track remaining balance and pending months.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create loan'),
              onPressed: onCreate,
            ),
          ],
        ),
      ),
    );
  }
}
