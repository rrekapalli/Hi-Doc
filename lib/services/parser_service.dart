import '../models/health_entry.dart';
import 'package:uuid/uuid.dart';

class ParseResult {
  final HealthEntry? entry;
  final String? error;
  ParseResult.success(this.entry) : error = null;
  ParseResult.failure(this.error) : entry = null;
}

abstract class ParserEngine {
  Future<ParseResult> parse(String message, {String? personId});
}

class RuleBasedParserEngine implements ParserEngine {
  static final _uuid = Uuid();
  final RegExp glucose = RegExp(r'(glucose|sugar)\s+(\d{2,3})\s*mg/dl', caseSensitive: false);
  // Pattern when user types number first then optional 'fasting' then glucose keyword, unit optional
  final RegExp glucoseNumberFirst = RegExp(r'(\d{2,3})\s*(?:mg/?dL)?\s*(?:fasting\s+)?(glucose|sugar)', caseSensitive: false);
  final RegExp weight = RegExp(r'weight\s+(\d{2,3}(?:\.\d)?)\s*(kg|kgs)?', caseSensitive: false);
  final RegExp bp = RegExp(r'(?:bp|blood pressure)\s+(\d{2,3})\s*/\s*(\d{2,3})', caseSensitive: false);
  final RegExp medication = RegExp(r'(start(ed)?|take|taking)\s+([a-zA-Z0-9\- ]+)\s+(\d+(?:\.\d+)?)?\s*(mg|mcg|g)?\s*(?:x|times)?\s*(\d)?\s*(?:per)?\s*(day|d)?\s*(?:for)?\s*(\d+)?\s*(day|days|d)?', caseSensitive: false);

  @override
  Future<ParseResult> parse(String message, {String? personId}) async {
    final lower = message.toLowerCase().trim();
    final ts = DateTime.now();

    // Glucose: keyword-first pattern
    final g = glucose.firstMatch(lower);
    if (g != null) {
      final value = double.tryParse(g.group(2)!);
      return ParseResult.success(HealthEntry.vital(
          id: _uuid.v4(),
          timestamp: ts,
          vital: VitalReading(vitalType: VitalType.glucose, value: value, unit: 'mg/dL'),
          personId: personId));
    }
    // Glucose: number-first pattern (e.g., "112 fasting glucose", "95 glucose")
    final g2 = glucoseNumberFirst.firstMatch(lower);
    if (g2 != null) {
      final value = double.tryParse(g2.group(1)!);
      return ParseResult.success(HealthEntry.vital(
          id: _uuid.v4(),
          timestamp: ts,
          vital: VitalReading(vitalType: VitalType.glucose, value: value, unit: 'mg/dL'),
          personId: personId));
    }
    final w = weight.firstMatch(lower);
    if (w != null) {
      final value = double.tryParse(w.group(2)!);
      return ParseResult.success(HealthEntry.vital(
          id: _uuid.v4(),
          timestamp: ts,
          vital: VitalReading(vitalType: VitalType.weight, value: value, unit: 'kg'),
          personId: personId));
    }
    final b = bp.firstMatch(lower);
    if (b != null) {
      final sys = double.tryParse(b.group(1)!);
      final dia = double.tryParse(b.group(2)!);
      return ParseResult.success(HealthEntry.vital(
          id: _uuid.v4(),
          timestamp: ts,
          vital: VitalReading(vitalType: VitalType.bloodPressure, systolic: sys, diastolic: dia, unit: 'mmHg'),
          personId: personId));
    }
    final m = medication.firstMatch(lower);
    if (m != null) {
      final name = m.group(3)?.trim();
      final dose = double.tryParse(m.group(4) ?? '');
      final doseUnit = m.group(5);
      final freq = int.tryParse(m.group(7) ?? '');
      final durationDays = int.tryParse(m.group(9) ?? '');
      return ParseResult.success(HealthEntry.medication(
          id: _uuid.v4(),
          timestamp: ts,
          medication: MedicationCourse(
              name: name ?? 'Medication',
              dose: dose,
              doseUnit: doseUnit,
              frequencyPerDay: freq,
              durationDays: durationDays,
              startDate: ts),
          personId: personId));
    }
    return ParseResult.failure('Unrecognized pattern');
  }
}

class ParserService {
  final ParserEngine engine;
  ParserService({ParserEngine? engine}) : engine = engine ?? RuleBasedParserEngine();

  Future<ParseResult> parseMessage(String message, {String? personId}) => engine.parse(message, personId: personId);
}
