import 'dart:convert';

class HealthDataEntry {
  final String id;
  final String userId;
  final String type;
  final String category;
  final String? value;
  final String? quantity;
  final String? unit;
  final int timestamp;
  final String? notes;

  HealthDataEntry({
    required this.id,
    required this.userId,
    required this.type,
    this.category = 'HEALTH_PARAMS',
    this.value,
    this.quantity,
    this.unit,
    required this.timestamp,
    this.notes,
  });

  factory HealthDataEntry.fromJson(Map<String, dynamic> json) {
    return HealthDataEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      category: json['category'] as String? ?? 'HEALTH_PARAMS',
      value: json['value'] as String?,
      quantity: json['quantity'] as String?,
      unit: json['unit'] as String?,
      timestamp: json['timestamp'] as int,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'type': type,
      'category': category,
      'value': value,
      'quantity': quantity,
      'unit': unit,
      'timestamp': timestamp,
      'notes': notes,
    };
  }

  @override
  String toString() {
    return 'HealthDataEntry(${jsonEncode(toJson())})';
  }
}