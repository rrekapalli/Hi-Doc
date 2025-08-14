import 'package:flutter_test/flutter_test.dart';
import 'package:hi_doc/services/parser_service.dart';

void main() {
  final parser = ParserService();

  test('parses glucose reading', () async {
    final res = await parser.parseMessage('Fasting glucose 98 mg/dL');
    expect(res.entry, isNotNull);
    expect(res.entry!.vital!.value, 98);
  });

  test('parses weight reading', () async {
    final res = await parser.parseMessage('Weight 75.5 kg');
    expect(res.entry, isNotNull);
    expect(res.entry!.vital!.value, 75.5);
  });

  test('parses blood pressure', () async {
    final res = await parser.parseMessage('BP 120/80');
    expect(res.entry, isNotNull);
    expect(res.entry!.vital!.systolic, 120);
  });
}
