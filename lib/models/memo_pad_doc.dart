class MemoPadDoc {
  final String id;
  final String text;
  final DateTime updatedAt;
  final bool deleted;

  MemoPadDoc({
    this.id = 'main',
    required this.text,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory MemoPadDoc.fromJson(Map<String, dynamic> json) {
    return MemoPadDoc(
      id: json['id']?.toString() ?? 'main',
      text: json['text']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deleted: json['deleted'] == true,
    );
  }
}

