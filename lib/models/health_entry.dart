import 'package:json_annotation/json_annotation.dart';

part 'health_entry.g.dart';

enum HealthEntryType { vital, medication, labResult, note }

enum VitalType { glucose, weight, bloodPressure, temperature, heartRate, steps, hba1c }

@JsonSerializable(explicitToJson: true)
class HealthEntry {
  final String id;
  final String? personId; // For group member association
  final DateTime timestamp;
  final HealthEntryType type;
  final VitalReading? vital;
  final MedicationCourse? medication;
  final LabResult? labResult;
  final String? note;

  HealthEntry({
    required this.id,
    required this.timestamp,
    required this.type,
    this.personId,
    this.vital,
    this.medication,
    this.labResult,
    this.note,
  });

  factory HealthEntry.vital({
    required String id,
    required DateTime timestamp,
    required VitalReading vital,
    String? personId,
  }) => HealthEntry(id: id, timestamp: timestamp, type: HealthEntryType.vital, vital: vital, personId: personId);

  factory HealthEntry.medication({
    required String id,
    required DateTime timestamp,
    required MedicationCourse medication,
    String? personId,
  }) => HealthEntry(id: id, timestamp: timestamp, type: HealthEntryType.medication, medication: medication, personId: personId);

  factory HealthEntry.lab({
    required String id,
    required DateTime timestamp,
    required LabResult labResult,
    String? personId,
  }) => HealthEntry(id: id, timestamp: timestamp, type: HealthEntryType.labResult, labResult: labResult, personId: personId);

  factory HealthEntry.note({
    required String id,
    required DateTime timestamp,
    required String note,
    String? personId,
  }) => HealthEntry(id: id, timestamp: timestamp, type: HealthEntryType.note, note: note, personId: personId);

  factory HealthEntry.fromJson(Map<String, dynamic> json) => _$HealthEntryFromJson(json);
  Map<String, dynamic> toJson() => _$HealthEntryToJson(this);

  HealthEntry copyWith({
    String? id,
    String? personId,
    DateTime? timestamp,
    HealthEntryType? type,
    VitalReading? vital,
    MedicationCourse? medication,
    LabResult? labResult,
    String? note,
  }) {
    return HealthEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      type: type ?? this.type,
      personId: personId ?? this.personId,
      vital: vital ?? this.vital,
      medication: medication ?? this.medication,
      labResult: labResult ?? this.labResult,
      note: note ?? this.note,
    );
  }
}

@JsonSerializable()
class VitalReading {
  final VitalType vitalType;
  final double? value; // Single-valued metrics
  final double? systolic; // BP
  final double? diastolic; // BP
  final String? unit;

  VitalReading({required this.vitalType, this.value, this.systolic, this.diastolic, this.unit});

  factory VitalReading.fromJson(Map<String, dynamic> json) => _$VitalReadingFromJson(json);
  Map<String, dynamic> toJson() => _$VitalReadingToJson(this);
}

@JsonSerializable()
class MedicationCourse {
  final String name;
  final double? dose;
  final String? doseUnit;
  final int? frequencyPerDay;
  final int? durationDays;
  final DateTime? startDate;

  MedicationCourse({required this.name, this.dose, this.doseUnit, this.frequencyPerDay, this.durationDays, this.startDate});

  factory MedicationCourse.fromJson(Map<String, dynamic> json) => _$MedicationCourseFromJson(json);
  Map<String, dynamic> toJson() => _$MedicationCourseToJson(this);
}

@JsonSerializable()
class LabResultParameter {
  final String name;
  final String? value;
  final String? unit;
  final String? referenceRange;

  LabResultParameter({required this.name, this.value, this.unit, this.referenceRange});

  factory LabResultParameter.fromJson(Map<String, dynamic> json) => _$LabResultParameterFromJson(json);
  Map<String, dynamic> toJson() => _$LabResultParameterToJson(this);
}

@JsonSerializable(explicitToJson: true)
class LabResult {
  final String sourceFilePath;
  final List<LabResultParameter> parameters;

  LabResult({required this.sourceFilePath, required this.parameters});

  factory LabResult.fromJson(Map<String, dynamic> json) => _$LabResultFromJson(json);
  Map<String, dynamic> toJson() => _$LabResultToJson(this);
}
