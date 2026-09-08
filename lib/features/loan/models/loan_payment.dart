/// One payment made against a [Loan]. Free-form on purpose — real payments
/// don't always land as a clean, on-schedule EMI (skipped months,
/// part-payments, prepayments), so this is just a dated amount rather than a
/// pointer to a specific schedule row.
class LoanPayment {
  const LoanPayment({
    required this.id,
    required this.loanId,
    required this.amount,
    required this.paidDate,
    this.note = '',
  });

  final String id;
  final String loanId;
  final double amount;
  final DateTime paidDate;
  final String note;

  Map<String, dynamic> toJson() => {
    'loanId': loanId,
    'amount': amount,
    'paidDate': paidDate.toIso8601String(),
    'note': note,
  };

  factory LoanPayment.fromJson(String id, Map<String, dynamic> json) {
    return LoanPayment(
      id: id,
      loanId: json['loanId'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      paidDate:
          DateTime.tryParse(json['paidDate'] as String? ?? '') ??
          DateTime.now(),
      note: json['note'] as String? ?? '',
    );
  }
}
