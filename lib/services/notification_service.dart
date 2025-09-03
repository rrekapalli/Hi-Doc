import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

/// Service to handle all notification-related functionality
class NotificationService {
  // Singleton pattern implementation
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  // Plugin instance
  final _plugin = FlutterLocalNotificationsPlugin();

  // Notification channel configuration
  final _channelId = 'medications';
  final _channelName = 'Medications';

  /// Initialize notification settings
  Future<void> init() async {
    if (kIsWeb) {
      debugPrint('Notifications not supported on web platform');
      return;
    }

    try {
      tz_data.initializeTimeZones();
      
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );
      
      // Request permissions for iOS
      await _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
    } catch (e) {
      debugPrint('Failed to initialize notifications: $e');
    }
  }

  /// Handle notification tap
  void _handleNotificationResponse(NotificationResponse details) {
    debugPrint('Notification tapped: ${details.payload}');
  }

  /// Cancel all scheduled notifications
  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    try {
      await _plugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Failed to cancel notifications: $e');
    }
  }

  /// Cancel a specific notification
  Future<void> cancelNotification(String id) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id.hashCode & 0x7fffffff);
      debugPrint('Cancelled notification: \$id');
    } catch (e) {
      debugPrint('Failed to cancel notification \$id: \$e');
    }
  }

  /// Calculate the next instance of a given time
  tz.TZDateTime _nextInstanceOfTime(String time, {List<int>? days}) {
    if (kIsWeb) return tz.TZDateTime.now(tz.local);

    final now = tz.TZDateTime.now(tz.local);
    final timeComponents = time.split(':').map(int.parse).toList();
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      timeComponents[0],
      timeComponents[1],
    );

    // First, handle weekly schedule
    if (days != null && days.isNotEmpty) {
      // If the current day is not in the selected days, find the next valid day
      if (!days.contains(scheduledDate.weekday)) {
        do {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        } while (!days.contains(scheduledDate.weekday));
      }
    }

    // Then check if the time has already passed today
    if (scheduledDate.isBefore(now)) {
      if (days != null && days.isNotEmpty) {
        // For weekly schedule, find the next occurrence on a selected day
        do {
          scheduledDate = scheduledDate.add(const Duration(days: 1));
        } while (!days.contains(scheduledDate.weekday));
      } else {
        // For daily schedule, just move to tomorrow
        scheduledDate = tz.TZDateTime(
          tz.local,
          now.year,
          now.month,
          now.day + 1,
          timeComponents[0],
          timeComponents[1],
        );
      }
    }

    return scheduledDate;
  }

  /// Schedule a medication reminder
  Future<void> scheduleMedicationReminder({
    required String id,
    required String title,
    required String message,
    required String time,
    required String repeat,
    String? days,
  }) async {
    if (kIsWeb) {
      debugPrint('Medication reminder scheduled (web - no-op): \$title at \$time');
      return;
    }

    try {
      // Cancel any existing notification with this ID first
      await cancelNotification(id);

      final List<int>? weekDays = days?.split(',').map(int.parse).toList();
      final notificationTime = _nextInstanceOfTime(time, days: weekDays);

      final notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Medication reminders',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(message),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        title,
        message,
        notificationTime,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: repeat == 'daily'
            ? DateTimeComponents.time
            : DateTimeComponents.dayOfWeekAndTime,
        payload: id,
      );

      debugPrint('Scheduled medication reminder: \$title at \${notificationTime.toIso8601String()}');
    } catch (e) {
      debugPrint('Failed to schedule medication reminder: \$e');
    }
  }

  /// Schedule a daily notification
  Future<void> scheduleDaily(String id, String title, String body, DateTime at) async {
    if (kIsWeb) {
      debugPrint('Daily notification scheduled (web - no-op): \$title at \${at.toIso8601String()}');
      return;
    }
    
    try {
      final tzTime = tz.TZDateTime.from(at, tz.local);
      await _plugin.zonedSchedule(
        id.hashCode & 0x7fffffff,
        title,
        body,
        tzTime,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: id,
      );
      debugPrint('Scheduled daily notification: \$title at \${tzTime.toIso8601String()}');
    } catch (e) {
      debugPrint('Failed to schedule daily notification: \$e');
    }
  }
}
