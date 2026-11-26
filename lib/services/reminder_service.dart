import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/money.dart';
import '../data/models/recurring_rule.dart';
import 'recurring_engine.dart';

/// Schedules local reminders for recurring payments.
///
/// Uses inexact alarms, so no exact-alarm permission is needed (a Play
/// Store policy concern); a reminder may arrive a few minutes late.
class ReminderService {
  ReminderService({FlutterLocalNotificationsPlugin? plugin, this.engine = const RecurringEngine()})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final RecurringEngine engine;
  bool _initialised = false;

  static const _channel = AndroidNotificationDetails(
    'recurring_reminders',
    'Recurring payment reminders',
    channelDescription: 'Reminders before rent, bills and other repeating payments are due',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  /// Time zone used for scheduling. The app is set up for India.
  static const timeZone = 'Asia/Kolkata';

  Future<void> init() async {
    if (_initialised) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(timeZone));
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
    _initialised = true;
  }

  /// Android 13+ asks the user before showing notifications.
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Replaces every scheduled reminder with one per active rule. A reminder
  /// time that has already passed fires a minute from now.
  Future<void> rescheduleAll(List<RecurringRule> rules, {required String Function(RecurringRule) labelFor}) async {
    await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    for (final rule in rules) {
      final at = engine.reminderTime(rule);
      if (at == null || rule.id == null) continue;
      final when = at.isAfter(now) ? at : now.add(const Duration(minutes: 1));
      if (rule.nextDue.isBefore(now.subtract(const Duration(days: 1)))) continue;
      final days = rule.remindDaysBefore;
      final dueText = days == 0 ? 'today' : (days == 1 ? 'tomorrow' : 'in $days days');
      await _plugin.zonedSchedule(
        id: rule.id!,
        title: '${labelFor(rule)} due $dueText',
        body: '${formatMoney(rule.amount)} · open the app to record it',
        scheduledDate: tz.TZDateTime.from(when, tz.local),
        notificationDetails: const NotificationDetails(android: _channel),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}
