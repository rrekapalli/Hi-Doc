import 'package:flutter/foundation.dart';

/// Represents a single numeric reading for an indicator.
@immutable
class TrendPoint {
  final DateTime timestamp;
  final double value;
  final String? unit;
  const TrendPoint({required this.timestamp, required this.value, this.unit});
}

/// Represents target range (band) for an indicator.
@immutable
class TargetRange {
  final double? min;
  final double? max;
  final String? preferredUnit;
  final String? description;
  const TargetRange({this.min, this.max, this.preferredUnit, this.description});
  bool get hasRange => min != null && max != null;
}

enum TrendRange { d7, d30, d90, y1, all }

extension TrendRangeX on TrendRange {
  String get label {
    switch (this) {
      case TrendRange.d7: return '7D';
      case TrendRange.d30: return '30D';
      case TrendRange.d90: return '90D';
      case TrendRange.y1: return '1Y';
      case TrendRange.all: return 'ALL';
    }
  }

  Duration? get duration {
    switch (this) {
      case TrendRange.d7: return const Duration(days: 7);
      case TrendRange.d30: return const Duration(days: 30);
      case TrendRange.d90: return const Duration(days: 90);
      case TrendRange.y1: return const Duration(days: 365);
      case TrendRange.all: return null; // no limit
    }
  }
}
