import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hi_doc/models/trend_models.dart';
import 'package:hi_doc/providers/trends_provider.dart';
import 'package:hi_doc/services/health_trends_service.dart';

class _FakeService extends HealthTrendsService {
  _FakeService() : super(null);
  @override
  Future<List<String>> fetchIndicatorTypes({String? query}) async =>
      ['GLU_FAST'];
  @override
  Future<List<TrendPoint>> fetchSeries(
      {required String type,
      required DateTime from,
      required DateTime to}) async {
    return [
      TrendPoint(
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
          value: 90,
          unit: 'mg/dL'),
      TrendPoint(timestamp: DateTime.now(), value: 100, unit: 'mg/dL'),
    ];
  }

  @override
  Future<TargetRange?> fetchTarget(String type) async =>
      const TargetRange(min: 80, max: 110, preferredUnit: 'mg/dL');
}

// No auth needed for test

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test('TrendsProvider loads types and series', () async {
    final tp = TrendsProvider(service: _FakeService());
    await tp.init();
    expect(tp.types, isNotEmpty);
    expect(tp.series, isNotEmpty);
    expect(tp.target?.hasRange, true);
    expect(tp.avg, isNotNull);
    expect(tp.mixedUnits, false);
  });
}
