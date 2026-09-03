/// One day's log: which protocols you kept, plus a free-form summary note.
/// Keyed by date (`yyyy-MM-dd`) and stored encrypted — see
/// `MurthyCryptoService`.
class DailyProgressEntry {
  const DailyProgressEntry({
    required this.date,
    this.summary = '',
    this.keptProtocolIds = const <String>[],
    this.updatedAt,
  });

  final String date;
  final String summary;
  final List<String> keptProtocolIds;
  final DateTime? updatedAt;

  DailyProgressEntry copyWith({
    String? summary,
    List<String>? keptProtocolIds,
  }) {
    return DailyProgressEntry(
      date: date,
      summary: summary ?? this.summary,
      keptProtocolIds: keptProtocolIds ?? this.keptProtocolIds,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date,
    'summary': summary,
    'keptProtocolIds': keptProtocolIds,
    'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory DailyProgressEntry.fromJson(Map<String, dynamic> json) {
    return DailyProgressEntry(
      date: json['date'] as String,
      summary: json['summary'] as String? ?? '',
      keptProtocolIds: (json['keptProtocolIds'] as List<dynamic>? ?? const [])
          .cast<String>(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String)
          : null,
    );
  }
}
