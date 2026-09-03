/// A recurring rule/checklist item you hold yourself to every day (e.g.
/// "no phone before 8am", "review tomorrow's schedule before bed").
/// Content lives only as ciphertext in Firestore — see `MurthyCryptoService`.
class DailyProtocol {
  const DailyProtocol({
    required this.id,
    required this.title,
    this.description = '',
    this.isActive = true,
    this.createdAt,
  });

  final String id;
  final String title;
  final String description;
  final bool isActive;
  final DateTime? createdAt;

  DailyProtocol copyWith({
    String? title,
    String? description,
    bool? isActive,
  }) {
    return DailyProtocol(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'isActive': isActive,
    'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory DailyProtocol.fromJson(String id, Map<String, dynamic> json) {
    return DailyProtocol(
      id: id,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
    );
  }
}
