import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tz_data.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin.initialize(initSettings);
  }

  Future<void> scheduleDaily(String id, String title, String body, DateTime at) async {
    final tzTime = tz.TZDateTime.from(at, tz.local);
    await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        title,
        body,
        tzTime,
        const NotificationDetails(
            android: AndroidNotificationDetails('meds', 'Medications', importance: Importance.high)),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time);
  }
}
