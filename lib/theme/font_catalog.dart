class FontCatalog {
  static const String system = '';

  // Font family IDs as registered in `pubspec.yaml`.
  static const String paperlogy = 'paperlogy';
  static const String parkDahyun = 'parkDahyun';
  static const String hambaknun = 'hambaknun';
  static const String jua = 'jua';
  static const String dohyeon = 'dohyeon';
  static const String suit = 'suit';
  static const String nalgae = 'nalgae';
  static const String dunggeunmiso = 'dunggeunmiso';
  static const String kkukkukk = 'kkukkukk';
  static const String dunggeunmo = 'dunggeunmo';

  // id -> label
  static const Map<String, String> options = <String, String>{
    system: '\uC2DC\uC2A4\uD15C',
    paperlogy: '\uD398\uC774\uD37C\uB85C\uC9C0',
    parkDahyun: '\uBC15\uB2E4\uD604\uCCB4',
    hambaknun: '\uD568\uBC15\uB208',
    jua: '\uC8FC\uC544',
    dohyeon: '\uB3C4\uD604',
    suit: '\uC218\uD2B8',
    nalgae: '\uB0A0\uAC1C',
    dunggeunmiso: '\uB465\uADFC\uBBF8\uC18C',
    kkukkukk: '\uAFB9\uAFB9\uCCB4',
    dunggeunmo: '\uB465\uADFC\uBAA8',
  };

  // legacy saved values (older builds stored display name as the fontFamily).
  static const Map<String, String> _legacyAliases = <String, String>{
    '\uD398\uC774\uD37C\uB85C\uC9C0': paperlogy,
    '\uBC15\uB2E4\uD604\uCCB4': parkDahyun,
    '\uD568\uBC15\uB208': hambaknun,
    '\uC8FC\uC544': jua,
    '\uB3C4\uD604': dohyeon,
    '\uC218\uD2B8': suit,
    '\uB0A0\uAC1C': nalgae,
    '\uB465\uADFC\uBBF8\uC18C': dunggeunmiso,
    '\uAFB9\uAFB9\uCCB4': kkukkukk,
    '\uB465\uADFC\uBAA8': dunggeunmo,
  };

  static String normalize(String? fontFamily) {
    final f = (fontFamily ?? '').trim();
    final migrated = _legacyAliases[f] ?? f;
    return options.containsKey(migrated) ? migrated : system;
  }
}

