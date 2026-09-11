/// A loan being tracked (e.g. a home loan) — the terms needed to derive an
/// amortization schedule. [emiOverride] lets you enter a known EMI directly
/// instead of relying on the computed formula (banks round differently).
///
/// [outstandingBalanceOverride]/[remainingMonthsOverride] let you enter the
/// bank's own reported figures directly instead of relying on our
/// amortization estimate — important for floating-rate loans (rate changes
/// over time drift our fixed-rate schedule away from what the bank actually
/// reports), or whenever you just have a recent statement handy.
///
/// [insurancePremium]/[insuranceProvider]/[insuranceNote] track loan-linked
/// insurance (e.g. property/building insurance financed into a home loan) —
/// informational only, not part of the balance/EMI math.
class Loan {
  const Loan({
    required this.id,
    required this.name,
    required this.principal,
    required this.tenureMonths,
    required this.startDate,
    this.annualInterestRate,
    this.emiOverride,
    this.outstandingBalanceOverride,
    this.remainingMonthsOverride,
    this.insurancePremium,
    this.insuranceProvider,
    this.insuranceNote = '',
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

  /// The bank's own reported outstanding principal balance as of a recent
  /// statement — when set, [LoanSummary] uses this directly instead of the
  /// computed amortization estimate.
  final double? outstandingBalanceOverride;

  /// The bank's own reported remaining tenure (months) as of a recent
  /// statement — paired with [outstandingBalanceOverride].
  final int? remainingMonthsOverride;

  /// Insurance premium amount linked to this loan (e.g. property/building
  /// insurance), if any.
  final double? insurancePremium;

  /// Who the insurance is with (e.g. "SBI General Insurance"), if known.
  final String? insuranceProvider;

  final String insuranceNote;

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
    double? outstandingBalanceOverride,
    bool clearOutstandingBalanceOverride = false,
    int? remainingMonthsOverride,
    bool clearRemainingMonthsOverride = false,
    double? insurancePremium,
    bool clearInsurancePremium = false,
    String? insuranceProvider,
    bool clearInsuranceProvider = false,
    String? insuranceNote,
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
      outstandingBalanceOverride: clearOutstandingBalanceOverride
          ? null
          : (outstandingBalanceOverride ?? this.outstandingBalanceOverride),
      remainingMonthsOverride: clearRemainingMonthsOverride
          ? null
          : (remainingMonthsOverride ?? this.remainingMonthsOverride),
      insurancePremium: clearInsurancePremium
          ? null
          : (insurancePremium ?? this.insurancePremium),
      insuranceProvider: clearInsuranceProvider
          ? null
          : (insuranceProvider ?? this.insuranceProvider),
      insuranceNote: insuranceNote ?? this.insuranceNote,
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
    'outstandingBalanceOverride': outstandingBalanceOverride,
    'remainingMonthsOverride': remainingMonthsOverride,
    'insurancePremium': insurancePremium,
    'insuranceProvider': insuranceProvider,
    'insuranceNote': insuranceNote,
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
      outstandingBalanceOverride:
          (json['outstandingBalanceOverride'] as num?)?.toDouble(),
      remainingMonthsOverride:
          (json['remainingMonthsOverride'] as num?)?.toInt(),
      insurancePremium: (json['insurancePremium'] as num?)?.toDouble(),
      insuranceProvider: json['insuranceProvider'] as String?,
      insuranceNote: json['insuranceNote'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}
