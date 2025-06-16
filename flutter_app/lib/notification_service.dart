import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  print('[DEBUG] (Background) Notification tapped: ${response.payload}');
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
  FlutterLocalNotificationsPlugin();
  static bool _notificationsEnabled = true;
  static List<String> motivationalMessages = [
    "👋 Hey! Ready to organize your day?",
    "🧠 Let’s clear your head with a quick plan session.",
    "📌 A little planning goes a long way!",
    "🗓️ Today is a blank page. Fill it with focus.",
    "✨ Your time is precious — plan it wisely!",
  ];


  static Future<void> init() async {
    print('[DEBUG] Initializing notifications');

    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

    const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    final initialized = await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('[DEBUG] Notification tapped: ${response.payload}');
      },
      onDidReceiveBackgroundNotificationResponse: onDidReceiveBackgroundNotificationResponse,
    );

    print('[DEBUG] Plugin initialized: $initialized');

    await _loadNotificationPreference();

    // Check notification permission (Android 13+)
    final permissionStatus = await Permission.notification.status;
    print('[DEBUG] Notification permission status: $permissionStatus');

    if (permissionStatus.isDenied || permissionStatus.isPermanentlyDenied) {
      final result = await Permission.notification.request();
      print('[DEBUG] Permission request result: $result');

      if (!result.isGranted) {
        print(
            '[ERROR] Notification permission not granted! Notifications will NOT work.');
        return;
      }
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        showFCMForegroundNotification(
          title: message.notification!.title ?? 'Reminder',
          body: message.notification!.body ?? '',
        );
      }
    });

    // Initialize timezone

    print('[DEBUG] NotificationService initialized.');
  }

  static Future<void> _loadNotificationPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    print('[DEBUG] Loaded notificationsEnabled: $_notificationsEnabled');
  }
  static Future<void> setNotificationsEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notifications_enabled', enabled);
    _notificationsEnabled = enabled;
    print('[DEBUG] Updated notificationsEnabled: $_notificationsEnabled');
  }

  static bool get notificationsEnabled => _notificationsEnabled;


  static Future<String?> getFCMToken() async {
    try {
      String? token = await FirebaseMessaging.instance.getToken();
      await FirebaseFirestore.instance
          .collection("users")
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .set({"fcm_token": token}, SetOptions(merge: true));
      print("📲 FCM Token: $token");
      return token;
    } catch (e) {
      print("❌ Failed to get FCM token: $e");
      return null;
    }
  }

  static Future<void> showFCMForegroundNotification({required String title, required String body}) async {
    const androidDetails = AndroidNotificationDetails(
      'fcm_foreground_channel',
      'Foreground FCM',
      channelDescription: 'Notifications shown when app is open',
      importance: Importance.max,
      priority: Priority.high,
    );

    const notificationDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      notificationDetails,
    );
  }

  /// Show notification for today's tasks
  static Future<void> showTaskNotifications(
      List<Map<String, dynamic>> tasks) async {
    if (tasks.isEmpty) return;

    String taskDetails = tasks.map((task) {
      final title = task['title'] ?? 'Unnamed Task';
      final dueDate = (task['DueDate'] as Timestamp?)?.toDate();
      final formattedDate = dueDate != null
          ? DateFormat('MMM d, h:mm a').format(dueDate)
          : 'Unknown time';
      return '📌 $title\n🕒 Due: $formattedDate\n';
    }).join('\n');

    final androidDetails = AndroidNotificationDetails(
      'task_due_today_channel',
      'Today\'s Task Reminder',
      channelDescription: 'Notifications for tasks due today',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Task Due Reminder',
      playSound: true,
      enableVibration: true,
      fullScreenIntent: true,
      styleInformation: BigTextStyleInformation(taskDetails),
    );

    final platformDetails = NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      1,
      "📝 Today's Due Tasks",
      "You have ${tasks.length} task(s) due today. Tap to view.",
      platformDetails,
    );
  }

  /// Check and trigger notification for today's tasks
  static Future<void> notifyTodayTasks() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("[ERROR] No logged-in user for notifications.");
      return;
    }
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(Duration(days: 1));

    List<String> collections = [
      'tasks_self',
      'tasks_family',
      'tasks_team',
      'tasks_self_work',
    ];

    List<Map<String, dynamic>> allTodayTasks = [];

    for (String collection in collections) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection(collection)
            .where('userId', isEqualTo: user.uid) // ✅ only my tasks
            .where('DueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('DueDate', isLessThan: Timestamp.fromDate(endOfDay))
            .get();

        final todayTasks = snapshot.docs
            .map((doc) => doc.data())
            .cast<Map<String, dynamic>>()
            .toList();

        allTodayTasks.addAll(todayTasks);
      } catch (e) {
        print("[ERROR] Error fetching tasks from $collection: $e");
      }
    }

    await showTaskNotifications(allTodayTasks);
  }

  static Future<void> sendFCMScheduledNotification({
    required String token,
    required String title,
    required String body,
    required DateTime sendTime,
  }) async {
    final url = Uri.parse('https://personal-ai-assistant-l3h3.onrender.com/schedule_notification');
    print('[DEBUG] About to send POST request for FCM scheduling.');
    print('[DEBUG] URL: $url');
    print('[DEBUG] Payload: {token: $token, title: $title, body: $body, send_time: ${sendTime.toIso8601String()}}');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'title': title,
          'body': body,
          'send_time': sendTime.toIso8601String(),
        }),
      );
      print('[DEBUG] Sending POST request to backend to schedule notification');
      print('[DEBUG] Payload: token=$token, title=$title, body=$body, send_time=${sendTime.toIso8601String()}');

      if (response.statusCode == 200) {
        print('[FCM] Scheduled notification via server!');
      } else {
        print('[FCM] Server scheduling failed: ${response.body}');
      }
    } catch (e) {
      print('[FCM] Error sending request: $e');
    }
  }

  static Future<void> checkPermissions() async {
    final statusNotification = await Permission.notification.status;
    final statusExactAlarm = await Permission.scheduleExactAlarm.status;

    print('[DEBUG] Notification Permission: $statusNotification');
    print('[DEBUG] Exact Alarm Permission: $statusExactAlarm');

    if (!statusNotification.isGranted) {
      print('[ERROR] Notification permission not granted.');
    }
    if (!statusExactAlarm.isGranted) {
      print('[ERROR] Exact alarm permission not granted.');
    }
  }

  static Future<void> maybeShowRandomNudge() async {
    final random = Random();
    if (random.nextBool()) { // 50% chance
      final List<String> messages = [
        "👋 Hey! Ready to organize your day?",
        "🗓️ Don’t forget to schedule your tasks!",
        "🔔 Time to plan — what’s your priority today?",
        "🧠 Let's clear your head with a quick plan session.",
        "📌 Organize your day before it organizes you!",
        "✨ Small plans = Big wins. Start now!",
      ];

      final message = messages[random.nextInt(messages.length)];

      await _notificationsPlugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "🌟 Spare Some time for Planning!!",
        message,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'nudge_channel',
            'Planning Nudges',
            channelDescription: 'Reminders to plan your day',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
      );
    }
  }

  static Future<void> scheduleMorningAndNightNudges() async {
    final androidImplementation =
    FlutterLocalNotificationsPlugin().resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    final permissionGranted = await androidImplementation?.requestExactAlarmsPermission() ?? false;

    if (!permissionGranted) {
      print("[ERROR] Exact alarm permission not granted. Skipping nudges.");
      return; // ✅ Just return safely if no permission
    }
    final androidDetails = AndroidNotificationDetails(
      'daily_nudges',
      'Daily Planning Nudges',
      channelDescription: 'Daily motivational reminders',
      importance: Importance.max,
      priority: Priority.high,
    );

    final notificationDetails = NotificationDetails(android: androidDetails);

    // 8:00 AM
    await _notificationsPlugin.zonedSchedule(
      1001,
      "🌞 Morning Motivation",
      motivationalMessages[Random().nextInt(motivationalMessages.length)],
      _nextInstanceOfTime(8, 0),
      notificationDetails,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );

    // 9:00 PM
    await _notificationsPlugin.zonedSchedule(
      1002,
      "🌙 Night Check-in",
      motivationalMessages[Random().nextInt(motivationalMessages.length)],
      _nextInstanceOfTime(23, 0),
      notificationDetails,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(Duration(days: 1));
    }
    return scheduled;
  }

  static Future<void> saveNotificationToFirestore({
    required String title,
    required String body,
    required DateTime reminderTime,
    required String token,
  }) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      print("No user logged in.");
      return;
    }

    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': userId,
      'token': token,
      'title': title,
      'body': body,
      'reminderTime': Timestamp.fromDate(reminderTime.toUtc()), // ⚡ Save UTC time
      'createdAt': FieldValue.serverTimestamp(),
    });

    print('🔔 Notification info saved to Firestore.');
  }

}
