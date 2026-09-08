/// A loan being tracked (e.g. a home loan) — the terms needed to derive an
/// amortization schedule. [emiOverride] lets you enter a known EMI directly
/// instead of relying on the computed formula (banks round differently).
class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.principal,
    required this.tenureMonths,
    required this.startDate,
    this.annualInterestRate,
    this.emiOverride,
    this.notes = '',
    this.createdAt,
  });

  final String id;
  final String name;

  /// Original loan amount (e.g. sanctioned home loan amount).
  final double principal;

  /// Annual interest rate as a percentage (e.g. 8.5 for 8.5%). Null if
  /// unknown — [emiOverride] must be set in that case, since EMI can't be
  /// computed without a rate.
  final double? annualInterestRate;

  final int tenureMonths;
  final DateTime startDate;

  /// A known/actual EMI amount, used instead of the computed one when set.
  final double? emiOverride;

  final String notes;
  final DateTime? createdAt;

  Loan copyWith({
    String? name,
    double? principal,
    double? annualInterestRate,
    bool clearAnnualInterestRate = false,
    int? tenureMonths,
    DateTime? startDate,
    double? emiOverride,
    bool clearEmiOverride = false,
    String? notes,
  }) {
    return Loan(
      id: id,
      name: name ?? this.name,
      principal: principal ?? this.principal,
      annualInterestRate: clearAnnualInterestRate
          ? null
          : (annualInterestRate ?? this.annualInterestRate),
      tenureMonths: tenureMonths ?? this.tenureMonths,
      startDate: startDate ?? this.startDate,
      emiOverride: clearEmiOverride ? null : (emiOverride ?? this.emiOverride),
      notes: notes ?? this.notes,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'principal': principal,
    'annualInterestRate': annualInterestRate,
    'tenureMonths': tenureMonths,
    'startDate': startDate.toIso8601String(),
    'emiOverride': emiOverride,
    'notes': notes,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory Loan.fromJson(String id, Map<String, dynamic> json) {
    return Loan(
      id: id,
      name: json['name'] as String? ?? '',
      principal: (json['principal'] as num?)?.toDouble() ?? 0,
      annualInterestRate: (json['annualInterestRate'] as num?)?.toDouble(),
      tenureMonths: (json['tenureMonths'] as num?)?.toInt() ?? 0,
      startDate:
          DateTime.tryParse(json['startDate'] as String? ?? '') ??
          DateTime.now(),
      emiOverride: (json['emiOverride'] as num?)?.toDouble(),
      notes: json['notes'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}
