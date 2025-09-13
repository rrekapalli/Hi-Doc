import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trend_models.dart';
import '../services/health_trends_service.dart';
import '../services/trend_query_parser.dart';
import '../models/trend_context_entry.dart';
import '../config/performance_config.dart';

/// Cached data wrapper with expiry
class _CachedData<T> {
  final T data;
  final DateTime timestamp;

  _CachedData(this.data) : timestamp = DateTime.now();

  bool get isExpired {
    return DateTime.now().difference(timestamp) > PerformanceConfig.cacheExpiry;
  }
}

class TrendsProvider with ChangeNotifier {
  final HealthTrendsService service;
  final TrendQueryParser _parser = TrendQueryParser();
  TrendsProvider({required this.service});

  static const _prefKeyLastType = 'trends.lastType';

  List<String> _types = [];
  final Map<String, String> _descToCode = {}; // description -> code
  List<String> _descriptions = [];
  String _typesSearchQuery = '';
  Timer? _typesSearchDebounce;
  bool _loadingTypes = false;
  bool _loadingSeries = false;
  String? _typesError;
  String? _seriesError;
  String? _selectedType;
  TrendRange _range = TrendRange.d90;
  List<TrendPoint> _series = [];
  // Multi-series support
  final Map<String, List<TrendPoint>> _multiSeries = {}; // indicator -> points
  TargetRange? _target;
  List<TrendContextEntry> _contextEntries = [];
  DateTime? _from;
  DateTime? _to;
  Timer? _debounce;

  // Enhanced caching with expiry
  final Map<String, _CachedData<List<TrendPoint>>> _seriesCache = {};
  final Map<String, _CachedData<TargetRange?>> _targetCache = {};

  // Derived stats
  double? _avg;
  double? _min;
  double? _max;
  bool _mixedUnits = false;
  String? _dominantUnit;

  List<String> get types => _types; // codes (legacy)
  List<String> get descriptions => _descriptions; // for UI display
  bool get isLoadingTypes => _loadingTypes;
  bool get isLoadingSeries => _loadingSeries;
  String? get typesError => _typesError;
  String? get seriesError => _seriesError;
  String? get selectedType => _selectedType;
  TrendRange get range => _range;
  List<TrendPoint> get series => _series;
  Map<String, List<TrendPoint>> get multiSeries => _multiSeries;
  List<TrendContextEntry> get contextEntries => _contextEntries;
  TargetRange? get target => _target;
  DateTime? get from => _from;
  DateTime? get to => _to;
  double? get avg => _avg;
  double? get minValue => _min;
  double? get maxValue => _max;
  bool get mixedUnits => _mixedUnits;
  String? get dominantUnit => _dominantUnit;

  Future<void> init() async {
    await _loadTypes();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(_prefKeyLastType);
    if (last != null && _types.contains(last)) {
      _selectedType = last;
    } else if (_types.isNotEmpty) {
      // Prefer GLU_FAST as default indicator when available
      if (_types.contains('GLU_FAST')) {
        _selectedType = 'GLU_FAST';
      } else {
        _selectedType = _types.first;
      }
    }
    if (_selectedType != null) {
      await _loadSeries();
    } else {
      notifyListeners();
    }
  }

  void setRange(TrendRange r) {
    if (_range == r) return;
    _range = r;
    _scheduleReload();
    notifyListeners();
  }

  void setSelectedType(String? valueOrDesc) {
    if (valueOrDesc == null) return;
    final code =
        _descToCode[valueOrDesc] ?? valueOrDesc; // accept description or code
    if (code == _selectedType) return;
    _selectedType = code;
    SharedPreferences.getInstance().then((p) {
      p.setString(_prefKeyLastType, code);
    });
    _scheduleReload();
    notifyListeners();
  }

  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _loadSeries();
    });
  }

  Future<void> _loadTypes() async {
    if (_loadingTypes) return;
    _loadingTypes = true;
    _typesError = null;
    notifyListeners();
    try {
      final meta = await service.fetchIndicatorMeta(
        query: _typesSearchQuery.isEmpty ? null : _typesSearchQuery,
      );
      _descToCode.clear();
      for (final m in meta) {
        _descToCode[m['description']!] = m['code']!;
      }
      _descriptions = _descToCode.keys.toList();
      _types = _descToCode.values.toSet().toList();
      if (_selectedType != null && !_types.contains(_selectedType)) {
        _selectedType = _types.isNotEmpty ? _types.first : null;
      }
    } catch (e) {
      _typesError = e.toString();
    } finally {
      _loadingTypes = false;
      notifyListeners();
    }
  }

  String? codeForDescription(String desc) => _descToCode[desc];
  String? descriptionForCode(String code) {
    for (final entry in _descToCode.entries) {
      if (entry.value == code) return entry.key;
    }
    return null;
  }

  void searchTypes(String query) {
    _typesSearchQuery = query.trim();
    _typesSearchDebounce?.cancel();
    _typesSearchDebounce = Timer(const Duration(milliseconds: 250), () {
      _loadTypes();
    });
  }

  Future<void> _loadSeries() async {
    String? type = _selectedType;
    if (type == null) {
      _series = [];
      _target = null;
      return;
    }
    // Defensive: if somehow a description (with space / lowercase) got stored, map it to code.
    if (type.contains(' ') || !_types.contains(type)) {
      final mapped = codeForDescription(type);
      if (mapped != null) {
        type = mapped;
        _selectedType = type; // normalize
      }
    }
    if (_loadingSeries) return;

    // Clean up expired cache entries periodically
    _cleanupExpiredCache();

    _loadingSeries = true;
    _seriesError = null;
    notifyListeners();
    try {
      final now = DateTime.now();
      DateTime from;
      if (_range.duration != null) {
        from = now.subtract(_range.duration!);
      } else {
        from = DateTime.fromMillisecondsSinceEpoch(0);
      }
      _from = from;
      _to = now;
      final cacheKey = '$type|${_range.name}';
      List<TrendPoint> data;
      if (_seriesCache.containsKey(cacheKey) &&
          !_seriesCache[cacheKey]!.isExpired) {
        data = _seriesCache[cacheKey]!.data;
      } else {
        data = await service.fetchSeries(type: type, from: from, to: now);
        _seriesCache[cacheKey] = _CachedData(data);
      }
      _series = data;
      _multiSeries.clear();
      _multiSeries[type] = data;

      if (_targetCache.containsKey(type) && !_targetCache[type]!.isExpired) {
        _target = _targetCache[type]!.data;
      } else {
        _target = await service.fetchTarget(type);
        _targetCache[type] = _CachedData(_target);
      }
      _computeDerived();
      _loadContextEntriesForPrimaryDay();
    } catch (e) {
      _seriesError = e.toString();
    } finally {
      _loadingSeries = false;
      notifyListeners();
    }
  }

  void _computeDerived() {
    if (_series.isEmpty) {
      _avg = _min = _max = null;
      _mixedUnits = false;
      _dominantUnit = null;
      return;
    }
    _min = _series.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    _max = _series.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    _avg = _series.map((e) => e.value).reduce((a, b) => a + b) / _series.length;
    final units = _series.map((e) => e.unit).whereType<String>().toList();
    if (units.isEmpty) {
      _mixedUnits = false;
      _dominantUnit = target?.preferredUnit;
      return;
    }
    final freq = <String, int>{};
    for (final u in units) {
      freq[u] = (freq[u] ?? 0) + 1;
    }
    _dominantUnit = freq.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
    _mixedUnits = freq.length > 1;
  }

  // Natural language query handling
  bool _nlLoading = false;
  String? _nlError;
  TrendQueryParseResult? _lastParse;
  bool get nlLoading => _nlLoading;
  String? get nlError => _nlError;
  TrendQueryParseResult? get lastParse => _lastParse;

  Future<TrendQueryParseResult> runNaturalLanguageQuery(String message) async {
    _nlError = null;
    _nlLoading = true;
    notifyListeners();
    try {
      final parsed = _parser.parse(message);
      _lastParse = parsed;
      if (parsed.error != null) {
        _nlError = parsed.hint ?? parsed.error;
        return parsed;
      }
      // Fetch each indicator
      _multiSeries.clear();
      for (final ind in parsed.indicators) {
        try {
          final pts = await service.fetchSeries(
            type: ind,
            from: parsed.from,
            to: parsed.to,
          );
          _multiSeries[ind] = pts;
        } catch (_) {
          _multiSeries[ind] = [];
        }
      }
      // Primary = first
      final primary = parsed.indicators.first;
      _selectedType = primary;
      _from = parsed.from;
      _to = parsed.to;
      _series = _multiSeries[primary] ?? [];
      if (_targetCache.containsKey(primary) &&
          !_targetCache[primary]!.isExpired) {
        _target = _targetCache[primary]!.data;
      } else {
        _target = await service.fetchTarget(primary);
        _targetCache[primary] = _CachedData(_target);
      }
      _computeDerived();
      _loadContextEntriesForPrimaryDay();
      return parsed;
    } catch (e) {
      _nlError = e.toString();
      return TrendQueryParseResult.failure('error', hint: e.toString());
    } finally {
      _nlLoading = false;
      notifyListeners();
    }
  }

  // Placeholder: load contextual entries (food intake / meds) for the current FROM date only.
  void _loadContextEntriesForPrimaryDay() {
    if (_from == null || _to == null) {
      _contextEntries = [];
      return;
    }
    final dayStart = DateTime(
      _to!.year,
      _to!.month,
      _to!.day,
    ); // focus on latest day in range
    final dayEnd = dayStart.add(const Duration(days: 1));
    // TODO: Replace with real service call when endpoints exist.
    // For now keep empty; structure ready.
    _contextEntries = _contextEntries
        .where(
          (e) => e.timestamp.isAfter(dayStart) && e.timestamp.isBefore(dayEnd),
        )
        .toList();
  }

  /// Clean up expired cache entries to prevent memory leaks
  void _cleanupExpiredCache() {
    _seriesCache.removeWhere((key, value) => value.isExpired);
    _targetCache.removeWhere((key, value) => value.isExpired);
  }

  /// Force clear all cached data
  void clearCache() {
    _seriesCache.clear();
    _targetCache.clear();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _typesSearchDebounce?.cancel();
    clearCache();
    super.dispose();
  }
}
