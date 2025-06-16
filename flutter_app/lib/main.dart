import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gif_view/gif_view.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'calendarPage.dart';
import 'settings.dart';
import 'Checklist.dart';
import 'chatbot.dart';
import 'package:dialog_flowtter/dialog_flowtter.dart';
import 'dialogflow_service.dart';
import 'package:async/async.dart';
import 'package:rxdart/rxdart.dart';
import 'auth_gate.dart';
import 'login.dart';
import 'signup.dart';
import 'profile.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'notification_service.dart';
import 'dart:io'; // Required for platform check
import 'dart:core';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'dart:io' show Platform;
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));
  await NotificationService.init();
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    await NotificationService.notifyTodayTasks();
  }
  await NotificationService.checkPermissions();
  await NotificationService.scheduleMorningAndNightNudges();
  if (!(await Permission.notification.isGranted)) {
    await requestPermissions();
  }

  if (!(await Permission.scheduleExactAlarm.isGranted)) {
    await requestExactAlarmPermission();
  }

  DialogFlowtter dialogFlowtter = await DialogFlowtter.fromFile(
    path: "assets/dialogflow-key.json",
  );

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('📩 FCM Foreground Notification Received: ${message.notification?.title}');
    if (message.notification != null) {
      NotificationService.showFCMForegroundNotification(
        title: message.notification!.title ?? 'No Title',
        body: message.notification!.body ?? 'No Body',
      );
    }
  });

  runApp(MyApp(dialogFlowtter: dialogFlowtter));
}




class MyApp extends StatefulWidget {
  final DialogFlowtter dialogFlowtter;

  const MyApp({Key? key, required this.dialogFlowtter}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
  FlutterLocalNotificationsPlugin();
  @override
  void initState() {
    super.initState();
    final deviceInfo = DeviceInfoPlugin();
  }



  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: Color(0xFF9D4EDD),
        scaffoldBackgroundColor: Color(0xFF101828),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF101828),
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(color: Colors.white, fontSize: 20),
        ),
        textTheme: TextTheme(
          bodyMedium: TextStyle(color: Colors.white),
          labelLarge: TextStyle(color: Colors.white),
          bodySmall: TextStyle(color: Colors.white70),
          titleMedium: TextStyle(color: Colors.white),
        ),
        iconTheme: IconThemeData(color: Colors.white),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: Colors.white),
          filled: true,
          fillColor: Color(0xFF1E1E2E),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white54),
            borderRadius: BorderRadius.circular(10),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF9D4EDD), width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Color(0xFF9D4EDD),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: Color(0xFF6C43E0),
          contentTextStyle: TextStyle(color: Colors.white),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            labelStyle: TextStyle(color: Colors.white),
          ),
          menuStyle: MenuStyle(
            backgroundColor: WidgetStateProperty.all(Color(0xFF1E1E2E)),
          ),
        ),
      ),

      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
                builder: (_) => AuthGate(dialogFlowtter: widget.dialogFlowtter));
          case '/home':
            return MaterialPageRoute(
                builder: (_) => HomePage(dialogFlowtter: widget.dialogFlowtter));
          case '/login':
            return MaterialPageRoute(
                builder: (_) => LoginPage(dialogFlowtter: widget.dialogFlowtter));
          case '/signup':
            return MaterialPageRoute(
                builder: (_) => SignUpPage(dialogFlowtter: widget.dialogFlowtter));
          case '/profile':
            final auth.User? user = settings.arguments as auth.User?;
            return MaterialPageRoute(builder: (_) => ProfilePage(user: user));
          default:
            return MaterialPageRoute(
              builder: (_) => Scaffold(
                  body: Center(child: Text('Unknown route: ${settings.name}'))),
            );
        }
      },
    );
  }
}

class HomePage extends StatefulWidget {
  final DialogFlowtter dialogFlowtter;

  const HomePage({Key? key, required this.dialogFlowtter}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState()  {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.maybeShowRandomNudge();
    });
  }



  Future<void> requestPermission() async {
    NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
    print('Permission status: ${settings.authorizationStatus}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    backgroundColor: Color(0xFF101828),
      body: SafeArea(
      child: SingleChildScrollView(
      child:Column(
        children: [
        //   ElevatedButton(
        //     onPressed: () {
        //       NotificationService.showImmediateTestNotification();
        //     },
        //     child: Text("Test Notification"),
        //   ),
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Siya',
                  style: TextStyle(
                    fontFamily: 'Cursive',
                    fontSize: MediaQuery.of(context).size.width * 0.08,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.calendar_month_outlined,
                          color: Colors.white, size: 35),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => CalendarPage()));
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.checklist,
                          color: Colors.white, size: 35),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => CheckListPage()));
                      },
                    ),
                    IconButton(
                      icon:
                      Icon(Icons.settings, color: Colors.white, size: 35),
                      onPressed: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => SettingsPage()));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 10),
          Center(
            child: Container(
              width: 300,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                    offset: Offset(0, 10),
                  ),
                ],
                color: Colors.black,
              ),
              clipBehavior: Clip.antiAlias,
              child: Transform.scale(
                scale: 2.5,
                child: GifView.asset(
                  'assets/avatar.gif',
                  frameRate: 30,
                ),
              ),
            ),
          ),
          SizedBox(height: 20),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 700), // Max width cap
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.all(8),
                      child: _buildTaskBox("Today's events", Icons.alarm, _fetchReminders()),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.all(8),
                      child: _buildTaskBox("Today's Tasks", Icons.task, _fetchTasks()),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 20),
          IconButton(
            icon: Icon(Icons.chat, color: Colors.white, size: 50),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        ChatScreen(dialogflowService: DialogflowService(widget.dialogFlowtter))),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Your AI Assistant, always here to help!',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 16,
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    ),
    ),
    );
  }
}




  Widget _buildTaskBox(String title, IconData icon, Stream<List<String>> stream) {
    return StreamBuilder<List<String>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingBox(title, icon);
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return _emptyBox(title, icon);
        }

        return _taskBox(title, icon, snapshot.data!);
      },
    );
  }


Stream<List<String>> _fetchReminders() {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser;

  DateTime now = DateTime.now();
  DateTime startOfDay = DateTime(now.year, now.month, now.day);
  DateTime endOfDay = startOfDay.add(Duration(days: 1));

  return firestore
      .collection("events")
      .where("userId", isEqualTo: user!.uid)
      .where("start", isGreaterThanOrEqualTo: Timestamp.fromDate(now)) // ✅ Only future events
      .where("start", isLessThan: Timestamp.fromDate(endOfDay))         // ✅ Before tomorrow
      .orderBy("start")
      .snapshots()
      .map((snapshot) {
    return snapshot.docs.map((doc) {
      String title = doc['title'] ?? "Untitled Event";
      Timestamp startTimestamp = doc['start'];
      DateTime startTime = startTimestamp.toDate();
      String formattedTime = DateFormat.jm().format(startTime);
      return "$formattedTime - $title";
    }).toList();
  });
}


/// Fetch Today's Tasks
Stream<List<String>> _fetchTasks() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return Stream.value([]);
  }

  DateTime now = DateTime.now();
  DateTime startOfToday = DateTime(now.year, now.month, now.day);
  DateTime endOfToday = startOfToday.add(Duration(days: 1));

  List<String> collections = [
    'tasks_self',
    'tasks_family',
    'tasks_team',
    'tasks_self_work'
  ];

  List<Stream<QuerySnapshot>> streams = collections.map((collection) {
    return FirebaseFirestore.instance
        .collection(collection)
        .where('userId', isEqualTo: user.uid)
        .where('DueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .where('DueDate', isLessThan: Timestamp.fromDate(endOfToday))
        .snapshots();
  }).toList();

  return CombineLatestStream.list(streams).map((snapshots) {
    final tasks = <String>[];
    for (var snapshot in snapshots) {
      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String title = data['title'] ?? "Untitled";
        Timestamp dueTimestamp = data['DueDate'];
        DateTime dueDate = dueTimestamp.toDate().toLocal();
        String formattedDue = DateFormat.jm().format(dueDate);
        tasks.add("$formattedDue - $title");
      }
    }
    return tasks;
  });
}


  Widget _loadingBox(String title, IconData icon) {
    return _boxTemplate(title, icon, Center(child: CircularProgressIndicator(color: Colors.white)));
  }

  Widget _emptyBox(String title, IconData icon) {
    return _boxTemplate(title, icon, Center(child: Text("No $title", style: TextStyle(color: Colors.white))));
  }

  Widget _taskBox(String title, IconData icon, List<String> tasks) {
    return _boxTemplate(
      title,
      icon,
      SizedBox(
        child: ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 8),
          itemCount: tasks.length,
          itemBuilder: (context, index) => _taskItem(tasks[index]),
        ),
      ),
    );
  }

  Widget _boxTemplate(String title, IconData icon, Widget child) {
    return LayoutBuilder(builder: (context, constraints)
    {
      double boxWidth = constraints.maxWidth < 450
          ? constraints.maxWidth * 0.9
          : 200;
      return Container(
        width: boxWidth,
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
              colors: [Color(0xFF6C43E0), Color(0xFF4A2CC5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4),
                blurRadius: 12,
                offset: Offset(4, 6))
          ],
        ),
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(9.0),
              child: Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: 24),
                    SizedBox(width: 4),
                    Text(title, style: TextStyle(fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white))
                  ])),
          Expanded(child: child)
        ]),
      );
    },
    );
  }

Widget _taskItem(String task) {
  List<String> parts = task.split(" - ");
  String title = parts.isNotEmpty ? parts[0] : "No Title";
  String date = parts.length > 1 ? parts[1] : "No Date";

  return Container(
    margin: EdgeInsets.symmetric(vertical: 6, horizontal: 10),
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.5)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 5),
        Text(
          date,
          style: TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    ),
  );
}




Future<void> requestPermissions() async {
  final FlutterLocalNotificationsPlugin notificationsPlugin =
  FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    // ✅ Android-specific permission request
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    notificationsPlugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      bool? granted = await androidImplementation
          .requestNotificationsPermission();
      print("🔔 Android notification permission granted: $granted");
    }
  } else if (Platform.isIOS) {
    // ✅ iOS-specific permission request
    final IOSFlutterLocalNotificationsPlugin? iosImplementation =
    notificationsPlugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();

    if (iosImplementation != null) {
      await iosImplementation.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      print("🍏 iOS notification permission requested.");
    }
  }
}




Future<void> requestExactAlarmPermission() async {
  if (Platform.isAndroid) {
    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;

    if (androidInfo.version.sdkInt >= 31) {
      const platform = MethodChannel('alarm_permission');
      try {
        await platform.invokeMethod('requestExactAlarmPermission');
      } on PlatformException catch (e) {
        print("[ERROR] Exact alarm permission not granted.");
      }
    }
  }
}