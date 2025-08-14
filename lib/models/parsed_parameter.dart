import 'package:uuid/uuid.dart';

class ParsedParameter {
  final String id;
  final String category;
  final String parameter;
  final String value; // keep as string for uniformity
  final String? unit;
  final String? datetime; // ISO or null
  ParsedParameter({required this.id, required this.category, required this.parameter, required this.value, this.unit, this.datetime});

  factory ParsedParameter.fromJson(Map<String,dynamic> j) => ParsedParameter(
    id: j['id'] ?? const Uuid().v4(),
    category: j['category'] as String,
    parameter: j['parameter'] as String,
    value: j['value']?.toString() ?? '',
    unit: j['unit'] as String?,
    datetime: j['datetime'] as String?,
  );

  Map<String,dynamic> toMap(String messageId) => {
    'id': id,
    'message_id': messageId,
    'category': category,
    'parameter': parameter,
    'value': value,
    'unit': unit,
    'datetime': datetime,
    'raw_json': toJsonString(),
  };

  String toJsonString() => '{"category":"$category","parameter":"$parameter","value":"$value"${unit!=null? ',"unit":"$unit"':''}${datetime!=null? ',"datetime":"$datetime"':''}}';
}
