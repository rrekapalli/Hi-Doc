// GENERATED CODE - DO NOT MODIFY BY HAND
// Manual generation (build_runner unavailable due to environment constraints)

part of 'health_entry.dart';

T _$enumDecode<T>(Map<T, String> enumMap, Object? source) {
	return enumMap.entries.singleWhere((e) => e.value == source).key;
}

const _HealthEntryTypeEnumMap = {
	HealthEntryType.vital: 'vital',
	HealthEntryType.medication: 'medication',
	HealthEntryType.labResult: 'labResult',
	HealthEntryType.note: 'note',
};

const _VitalTypeEnumMap = {
	VitalType.glucose: 'glucose',
	VitalType.weight: 'weight',
	VitalType.bloodPressure: 'bloodPressure',
	VitalType.temperature: 'temperature',
	VitalType.heartRate: 'heartRate',
	VitalType.steps: 'steps',
	VitalType.hba1c: 'hba1c',
};

HealthEntry _$HealthEntryFromJson(Map<String, dynamic> json) => HealthEntry(
			id: json['id'] as String,
			timestamp: DateTime.parse(json['timestamp'] as String),
			type: _$enumDecode(_HealthEntryTypeEnumMap, json['type']),
			personId: json['personId'] as String?,
			vital: json['vital'] == null
					? null
					: VitalReading.fromJson(json['vital'] as Map<String, dynamic>),
			medication: json['medication'] == null
					? null
					: MedicationCourse.fromJson(
							json['medication'] as Map<String, dynamic>),
			labResult: json['labResult'] == null
					? null
					: LabResult.fromJson(json['labResult'] as Map<String, dynamic>),
			note: json['note'] as String?,
		);

Map<String, dynamic> _$HealthEntryToJson(HealthEntry instance) => <String, dynamic>{
			'id': instance.id,
			'personId': instance.personId,
			'timestamp': instance.timestamp.toIso8601String(),
			'type': _HealthEntryTypeEnumMap[instance.type],
			'vital': instance.vital?.toJson(),
			'medication': instance.medication?.toJson(),
			'labResult': instance.labResult?.toJson(),
			'note': instance.note,
		};

VitalReading _$VitalReadingFromJson(Map<String, dynamic> json) => VitalReading(
			vitalType: _$enumDecode(_VitalTypeEnumMap, json['vitalType']),
			value: (json['value'] as num?)?.toDouble(),
			systolic: (json['systolic'] as num?)?.toDouble(),
			diastolic: (json['diastolic'] as num?)?.toDouble(),
			unit: json['unit'] as String?,
		);

Map<String, dynamic> _$VitalReadingToJson(VitalReading instance) => <String, dynamic>{
			'vitalType': _VitalTypeEnumMap[instance.vitalType],
			'value': instance.value,
			'systolic': instance.systolic,
			'diastolic': instance.diastolic,
			'unit': instance.unit,
		};

MedicationCourse _$MedicationCourseFromJson(Map<String, dynamic> json) => MedicationCourse(
			name: json['name'] as String,
			dose: (json['dose'] as num?)?.toDouble(),
			doseUnit: json['doseUnit'] as String?,
			frequencyPerDay: json['frequencyPerDay'] as int?,
			durationDays: json['durationDays'] as int?,
			startDate: json['startDate'] == null
					? null
					: DateTime.parse(json['startDate'] as String),
		);

Map<String, dynamic> _$MedicationCourseToJson(MedicationCourse instance) => <String, dynamic>{
			'name': instance.name,
			'dose': instance.dose,
			'doseUnit': instance.doseUnit,
			'frequencyPerDay': instance.frequencyPerDay,
			'durationDays': instance.durationDays,
			'startDate': instance.startDate?.toIso8601String(),
		};

LabResultParameter _$LabResultParameterFromJson(Map<String, dynamic> json) => LabResultParameter(
			name: json['name'] as String,
			value: json['value'] as String?,
			unit: json['unit'] as String?,
			referenceRange: json['referenceRange'] as String?,
		);

Map<String, dynamic> _$LabResultParameterToJson(LabResultParameter instance) => <String, dynamic>{
			'name': instance.name,
			'value': instance.value,
			'unit': instance.unit,
			'referenceRange': instance.referenceRange,
		};

LabResult _$LabResultFromJson(Map<String, dynamic> json) => LabResult(
			sourceFilePath: json['sourceFilePath'] as String,
			parameters: (json['parameters'] as List<dynamic>)
					.map((e) => LabResultParameter.fromJson(e as Map<String, dynamic>))
					.toList(),
		);

Map<String, dynamic> _$LabResultToJson(LabResult instance) => <String, dynamic>{
			'sourceFilePath': instance.sourceFilePath,
			'parameters': instance.parameters.map((e) => e.toJson()).toList(),
		};

