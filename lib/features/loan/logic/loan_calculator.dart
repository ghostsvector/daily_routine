import 'dart:math' as math;

import '../models/loan.dart';
import '../models/loan_payment.dart';

/// One row of a loan's amortization schedule.
class LoanScheduleEntry {
  const LoanScheduleEntry({
    required this.monthIndex,
    required this.dueDate,
    required this.emi,
    required this.interestComponent,
    required this.principalComponent,
    required this.balanceAfter,
  });

  /// 1-based month number.
  final int monthIndex;
  final DateTime dueDate;
  final double emi;
  final double interestComponent;
  final double principalComponent;
  final double balanceAfter;
}

/// Derived, at-a-glance state of a loan given payments made so far.
class LoanSummary {
  const LoanSummary({
    required this.loan,
    required this.emi,
    required this.totalPayable,
    required this.totalPaid,
    required this.outstandingPrincipal,
    required this.pendingAmount,
    required this.monthsPaid,
    required this.monthsPending,
    required this.isPaidOff,
  });

  final Loan loan;

  /// The EMI used for every calculation below — [Loan.emiOverride] if set,
  /// else computed from principal/rate/tenure.
  final double emi;

  /// EMI × tenure — everything payable over the life of the loan
  /// (principal + interest), assuming a fixed EMI.
  final double totalPayable;

  /// Sum of all logged [LoanPayment]s.
  final double totalPaid;

  /// Remaining principal balance, read off the amortization schedule at the
  /// month index implied by [totalPaid].
  final double outstandingPrincipal;

  /// Money not yet paid: [totalPayable] − [totalPaid] (principal + interest
  /// still due, not just the remaining principal).
  final double pendingAmount;

  /// Whole EMI-months' worth of [totalPaid], capped at the loan's tenure.
  final int monthsPaid;

  final int monthsPending;
  final bool isPaidOff;
}

/// Standard reducing-balance EMI formula. Falls back to a straight-line
/// split (principal / tenure) when the rate is zero or unknown.
double computeEmi(Loan loan) {
  if (loan.emiOverride != null) return loan.emiOverride!;
  final rate = loan.annualInterestRate;
  if (rate == null || rate == 0 || loan.tenureMonths <= 0) {
    return loan.tenureMonths <= 0 ? 0 : loan.principal / loan.tenureMonths;
  }
  final monthlyRate = rate / 12 / 100;
  final factor = math.pow(1 + monthlyRate, loan.tenureMonths);
  return loan.principal * monthlyRate * factor / (factor - 1);
}

/// Full month-by-month amortization schedule for [loan], using [computeEmi]
/// for the fixed monthly payment.
List<LoanScheduleEntry> buildAmortizationSchedule(Loan loan) {
  if (loan.tenureMonths <= 0) return const [];
  final emi = computeEmi(loan);
  final monthlyRate = (loan.annualInterestRate ?? 0) / 12 / 100;

  var balance = loan.principal;
  final schedule = <LoanScheduleEntry>[];
  for (var month = 1; month <= loan.tenureMonths; month++) {
    final interest = balance * monthlyRate;
    var principalComponent = emi - interest;
    // Last installment: clear whatever balance remains rather than letting
    // rounding drift leave a residual.
    if (month == loan.tenureMonths || principalComponent > balance) {
      principalComponent = balance;
    }
    balance = (balance - principalComponent).clamp(0, loan.principal);
    schedule.add(
      LoanScheduleEntry(
        monthIndex: month,
        dueDate: DateTime(
          loan.startDate.year,
          loan.startDate.month + month - 1,
          loan.startDate.day,
        ),
        emi: month == loan.tenureMonths
            ? principalComponent + interest
            : emi,
        interestComponent: interest,
        principalComponent: principalComponent,
        balanceAfter: balance,
      ),
    );
  }
  return schedule;
}

/// Rolls up [loan] + its logged [payments] into the numbers a dashboard
/// cares about: remaining balance, pending months, pending amount.
///
/// When [Loan.outstandingBalanceOverride]/[Loan.remainingMonthsOverride] are
/// set (a bank statement's own reported figures), those are used directly
/// instead of the amortization estimate — important for floating-rate loans,
/// where rate changes over the loan's life make a fixed-schedule estimate
/// drift from what the bank actually reports.
LoanSummary computeLoanSummary(Loan loan, List<LoanPayment> payments) {
  final emi = computeEmi(loan);
  final totalPayable = emi * loan.tenureMonths;
  final totalPaid = payments.fold<double>(0, (sum, p) => sum + p.amount);

  final hasBankReportedFigures =
      loan.outstandingBalanceOverride != null ||
      loan.remainingMonthsOverride != null;

  int monthsPending;
  double outstandingPrincipal;
  double pendingAmount;
  int monthsPaid;

  if (hasBankReportedFigures) {
    monthsPending = (loan.remainingMonthsOverride ?? loan.tenureMonths).clamp(
      0,
      loan.tenureMonths,
    );
    monthsPaid = loan.tenureMonths - monthsPending;
    outstandingPrincipal = loan.outstandingBalanceOverride ?? loan.principal;
    // Best estimate of what's still payable (principal + remaining
    // interest) from here — EMI × remaining months, not the original
    // schedule's total, since that would ignore payments/rate changes
    // already reflected in the bank-reported balance.
    pendingAmount = (emi * monthsPending).clamp(0, double.infinity);
  } else {
    final schedule = buildAmortizationSchedule(loan);
    monthsPaid = emi <= 0
        ? 0
        : (totalPaid / emi).floor().clamp(0, loan.tenureMonths);
    monthsPending = loan.tenureMonths - monthsPaid;
    outstandingPrincipal = schedule.isEmpty
        ? loan.principal
        : (monthsPaid == 0
              ? loan.principal
              : schedule[monthsPaid - 1].balanceAfter);
    pendingAmount = (totalPayable - totalPaid).clamp(0, totalPayable);
  }

  return LoanSummary(
    loan: loan,
    emi: emi,
    totalPayable: totalPayable,
    totalPaid: totalPaid,
    outstandingPrincipal: outstandingPrincipal.toDouble(),
    pendingAmount: pendingAmount.toDouble(),
    monthsPaid: monthsPaid,
    monthsPending: monthsPending,
    isPaidOff: monthsPending <= 0 || outstandingPrincipal <= 0.01,
  );
}
