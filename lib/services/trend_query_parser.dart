import 'dart:math';

/// Result of parsing a natural language trend query.
class TrendQueryParseResult {
  final List<String> indicators; // normalized indicator codes
  final DateTime from;
  final DateTime to;
  final bool compare;
  final String? error;
  final String? hint;
  TrendQueryParseResult.success({required this.indicators, required this.from, required this.to, this.compare = false}) : error = null, hint = null;
  TrendQueryParseResult.failure(this.error, {this.hint}) : indicators = const [], from = DateTime.fromMillisecondsSinceEpoch(0), to = DateTime.fromMillisecondsSinceEpoch(0), compare = false;

  Map<String, dynamic> toJson() => error != null
      ? { 'error': error, if (hint != null) 'hint': hint }
      : {
          'indicators': indicators,
          'fromMs': from.millisecondsSinceEpoch,
          'toMs': to.millisecondsSinceEpoch,
          'compare': compare,
        };
}

/// Lightweight rules-based parser for indicator + date range extraction.
class TrendQueryParser {
  // Synonym map (lowercase token -> canonical code)
  static const Map<String, String> _synonyms = {
    'glucose': 'GLU_FAST', 'sugar': 'GLU_FAST', 'fasting': 'GLU_FAST', 'fasting glucose': 'GLU_FAST', 'fasting sugar': 'GLU_FAST',
    'a1c': 'HBA1C', 'hba1c': 'HBA1C',
    'bp': 'BP_SYS', 'blood pressure': 'BP_SYS', 'pressure': 'BP_SYS',
    'weight': 'WEIGHT', 'wt': 'WEIGHT',
    'steps': 'STEPS', 'step count': 'STEPS',
    'heart rate': 'HR', 'pulse': 'HR', 'hr': 'HR',
    'temperature': 'TEMP', 'temp': 'TEMP', 'fever': 'TEMP',
    'cholesterol total': 'TC',
    'ldl': 'LDL', 'hdl': 'HDL',
    'triglycerides': 'TG', 'trigs': 'TG', 'tg': 'TG',
  };

  static final List<String> _multiWordKeys = _synonyms.keys.where((k) => k.contains(' ')).toList()
    ..sort((a,b)=>b.length.compareTo(a.length));

  TrendQueryParseResult parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return TrendQueryParseResult.failure('empty', hint: "Try 'glucose last 90 days'");
    }
    final text = raw.toLowerCase();
    final now = DateTime.now();
    DateTime? from; DateTime to = now;

    // Detect explicit range phrases first.
    // 1. last N days
    final lastNum = RegExp(r'last (\d{1,3}) ?(day|days|d)');
    final mLastNum = lastNum.firstMatch(text);
    if (mLastNum != null) {
      final n = int.tryParse(mLastNum.group(1)!);
      if (n != null && n > 0) {
        from = now.subtract(Duration(days: n));
      }
    }
    // 2. last week/month/year
    if (from == null) {
      if (text.contains('last week')) from = now.subtract(const Duration(days: 7));
      else if (text.contains('last month')) from = now.subtract(const Duration(days: 30));
      else if (text.contains('last 7 days')) from = now.subtract(const Duration(days: 7));
      else if (text.contains('last 30 days')) from = now.subtract(const Duration(days: 30));
      else if (text.contains('last 90 days')) from = now.subtract(const Duration(days: 90));
      else if (text.contains('last year')) from = now.subtract(const Duration(days: 365));
    }
    // 3. today / yesterday
    if (from == null) {
      if (text.contains('today')) {
        from = DateTime(now.year, now.month, now.day);
        to = from.add(const Duration(days: 1));
      } else if (text.contains('yesterday')) {
        final y = DateTime(now.year, now.month, now.day).subtract(const Duration(days:1));
        from = y; to = y.add(const Duration(days:1));
      }
    }
    // 4. since <date>
    final sinceRe = RegExp(r'since ([a-zA-Z]{3,9}) ?(\d{1,2})(?:,? ?(\d{4}))?');
    final mSince = sinceRe.firstMatch(text);
    if (mSince != null) {
      final monthName = mSince.group(1)!; final dayStr = mSince.group(2)!; final yearStr = mSince.group(3);
      final month = _monthIndex(monthName);
      final day = int.tryParse(dayStr);
      if (month != null && day != null) {
        int year = yearStr != null ? int.parse(yearStr) : now.year;
        // if future assume previous year
        final candidate = DateTime(year, month, day);
        from = candidate.isAfter(now) ? DateTime(year - 1, month, day) : candidate;
      }
    }
    // 5. from <date> to <date>
    final rangeRe = RegExp(r'from ([a-zA-Z]{3,9}) ?(\d{1,2})(?:,? ?(\d{4}))? to ([a-zA-Z]{3,9}) ?(\d{1,2})(?:,? ?(\d{4}))?');
    final mRange = rangeRe.firstMatch(text);
    if (mRange != null) {
      final m1 = _monthIndex(mRange.group(1)!); final d1 = int.tryParse(mRange.group(2)!); final y1 = mRange.group(3);
      final m2 = _monthIndex(mRange.group(4)!); final d2 = int.tryParse(mRange.group(5)!); final y2 = mRange.group(6);
      if (m1 != null && d1 != null && m2 != null && d2 != null) {
        final year1 = y1 != null ? int.parse(y1) : now.year;
        final year2 = y2 != null ? int.parse(y2) : now.year;
        from = DateTime(year1, m1, d1);
        to = DateTime(year2, m2, d2).add(const Duration(days:1));
      }
    }

    // Default if still null: use 30 days
    from ??= now.subtract(const Duration(days: 30));

    // Extract indicators (multi-word first)
    final indicators = <String>[];
    String remaining = text;
    for (final key in _multiWordKeys) {
      if (remaining.contains(key)) {
        indicators.add(_synonyms[key]!);
        remaining = remaining.replaceAll(key, ' ');
      }
    }
    // Single words
    for (final entry in _synonyms.entries) {
      if (!entry.key.contains(' ') && RegExp('(?<![a-z])${RegExp.escape(entry.key)}(?![a-z])').hasMatch(remaining)) {
        if (!indicators.contains(entry.value)) indicators.add(entry.value);
      }
    }
    if (indicators.isEmpty) {
      return TrendQueryParseResult.failure('unrecognized', hint: "Try 'glucose last 90 days'");
    }
    // Keep max 2 indicators for compare readability
    if (indicators.length > 2) {
      indicators.removeRange(2, indicators.length);
    }
    final compare = indicators.length > 1 || text.contains('compare');
    if (from.isAfter(to)) {
      // swap just in case
      final tmp = from; from = to; to = tmp;
    }

    return TrendQueryParseResult.success(indicators: indicators, from: from, to: to, compare: compare);
  }

  static int? _monthIndex(String name) {
    final m = name.substring(0, min(3, name.length)).toLowerCase();
    const months = ['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
    final idx = months.indexOf(m);
    return idx == -1 ? null : idx + 1;
  }
}
