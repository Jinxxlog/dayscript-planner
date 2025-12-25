class UiPrefs {
  final String fontFamily;
  final String themePresetId;
  final double textScale;
  final DateTime updatedAt;
  final bool deleted;

  UiPrefs({
    required this.fontFamily,
    required this.themePresetId,
    required this.textScale,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = (updatedAt ?? DateTime.now()).toUtc();

  static UiPrefs defaults({DateTime? now}) => UiPrefs(
        fontFamily: '',
        themePresetId: 'default',
        textScale: 1.0,
        updatedAt: (now ?? DateTime.now()).toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'fontFamily': fontFamily,
        'themePresetId': themePresetId,
        'textScale': textScale,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory UiPrefs.fromJson(Map<String, dynamic> json) {
    return UiPrefs(
      fontFamily: json['fontFamily']?.toString() ?? '',
      themePresetId: json['themePresetId']?.toString() ?? 'default',
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1.0,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deleted: json['deleted'] == true,
    );
  }
}
