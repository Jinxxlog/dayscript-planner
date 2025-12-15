import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'holiday_service.dart';

/// 캘린더 데이터 로딩/파싱 헬퍼 (ICS + 사용자 휴일 병합)
class CalendarDataService {
  Future<Map<String, String>> loadIcsHolidays(
      {String assetPath = 'assets/basic.ics'}) async {
    try {
      final ics = await rootBundle.loadString(assetPath);
      return parseIcs(ics);
    } catch (e) {
      debugPrint("❌ ICS 로드 실패: $e");
      return {};
    }
  }

  Map<String, String> parseIcs(String icsContent) {
    final Map<String, String> holidays = {};
    final lines = icsContent.split(RegExp(r'\r?\n'));
    String? summary;
    DateTime? date;

    for (final line in lines) {
      if (line.startsWith("SUMMARY:")) {
        summary = line.replaceFirst("SUMMARY:", "").trim();
      } else if (line.startsWith("DTSTART")) {
        final match = RegExp(r':(\d{8})').firstMatch(line);
        if (match != null) {
          final raw = match.group(1)!;
          final year = int.parse(raw.substring(0, 4));
          final month = int.parse(raw.substring(4, 6));
          final day = int.parse(raw.substring(6, 8));
          date = DateTime(year, month, day);
        }
      } else if (line.startsWith("END:VEVENT")) {
        if (summary != null && date != null) {
          final key = _formatDateKey(date);
          holidays[key] = summary;
          summary = null;
          date = null;
        }
      }
    }

    debugPrint("📘 ICS 파싱 완료 (${holidays.length}건)");
    return holidays;
  }

  Map<String, String> mergeHolidays(
      Map<String, String> ics, List<CustomHoliday> custom) {
    final merged = Map<String, String>.from(ics);
    for (final h in custom) {
      merged[_formatDateKey(h.date)] = h.title;
    }
    return merged;
  }

  String _formatDateKey(DateTime date) =>
      "${date.year.toString().padLeft(4, '0')}-"
      "${date.month.toString().padLeft(2, '0')}-"
      "${date.day.toString().padLeft(2, '0')}";
}
