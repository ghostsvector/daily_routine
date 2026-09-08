import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_providers.dart';
import '../data/loan_repository.dart';
import '../logic/loan_calculator.dart';
import '../models/loan.dart';
import '../models/loan_payment.dart';

final loanRepositoryProvider = Provider<LoanRepository>(
  (ref) => LoanRepository(),
);

/// `autoDispose`: on Linux this polls Firestore's REST API on a timer (see
/// `LoanRepository`'s REST backend) — without autoDispose it would keep
/// polling for as long as the app process runs, not just while a loan
/// screen/dashboard card is on screen.
final loansProvider = StreamProvider.autoDispose<List<Loan>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user.isEmpty) return const Stream.empty();
  return ref.watch(loanRepositoryProvider).watchLoans(user.uid);
});

final loanPaymentsProvider = StreamProvider.autoDispose
    .family<List<LoanPayment>, String>((ref, loanId) {
      final user = ref.watch(currentUserProvider);
      if (user.isEmpty) return const Stream.empty();
      return ref
          .watch(loanRepositoryProvider)
          .watchPayments(user.uid, loanId);
    });

final loanSummaryProvider = Provider.autoDispose.family<LoanSummary?, String>((
  ref,
  loanId,
) {
  final loans = ref.watch(loansProvider).valueOrNull ?? const [];
  Loan? loan;
  for (final l in loans) {
    if (l.id == loanId) {
      loan = l;
      break;
    }
  }
  if (loan == null) return null;
  final payments = ref.watch(loanPaymentsProvider(loanId)).valueOrNull ?? const [];
  return computeLoanSummary(loan, payments);
});

/// Summaries for every loan the user has, keyed by loan id — the input the
/// dashboard card needs. Watches each loan's payment stream so it stays live
/// as payments are logged.
final allLoanSummariesProvider = Provider.autoDispose<List<LoanSummary>>((
  ref,
) {
  final loans = ref.watch(loansProvider).valueOrNull ?? const [];
  return [
    for (final loan in loans)
      if (ref.watch(loanSummaryProvider(loan.id)) case final summary?) summary,
  ];
});
