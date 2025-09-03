import 'package:flutter/foundation.dart';

@immutable
class TrendContextEntry {
  final DateTime timestamp;
  final String type; // FOOD | MED | NOTE | OTHER
  final String title;
  final String? details;
  const TrendContextEntry({required this.timestamp, required this.type, required this.title, this.details});
}
