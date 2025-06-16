import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'notification_service.dart';
import 'dart:math';
import 'package:firebase_auth/firebase_auth.dart';


class AddEventPage extends StatefulWidget {
  final DateTime selectedDate;
  final String? eventId;
  final String? initialTitle;

  AddEventPage({required this.selectedDate, this.eventId, this.initialTitle});

  @override
  _AddEventPageState createState() => _AddEventPageState();
}

class _AddEventPageState extends State<AddEventPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  late DateTime _startDate;
  late DateTime _endDate;
  bool _allDay = false;
  String _reminder = '10 minutes before';
  String _repeat = 'None';
  String _priority = 'Medium';
  String _category = 'General';


  final List<String> _reminderOptions = [
    'None',
    '5 minutes before',
    '10 minutes before',
    '15 minutes before',
    '30 minutes before',
    '45 minutes before',
    '1 hour before',
    '2 hours before',
    '3 hours before',
    '6 hours before',
    '12 hours before',
    '1 day before',
    '2 days before',
    '3 days before',
    '1 week before',
  ];

  final List<String> _repeatOptions = [
    'None',
    'Daily',
    'Weekly',
    'Monthly',
    'Custom'
  ];
  final List<String> _priorityOptions = ['High', 'Medium', 'Low'];
  final List<String> _categoryOptions = [
    'Work',
    'Health',
    'Finance',
    'Personal',
    'General'
  ];

  String _generateRandomNotificationBody(String title, DateTime startTime) {
    final String time = DateFormat('MMM d, h:mm a').format(startTime);

    final List<String> variations = [
      "🧠 Reminder: *$title*\n⏰ $time\n✨ Stay sharp & be on time!",
      "📅 You’ve got *$title* at $time. Don’t miss it! ⏳",
      "⏰ Heads up! *$title* starts soon — $time. 📍 Be ready!",
      "🎯 Time for *$title* at $time.\nLet’s crush it! 💼🔥",
      "🗓️ Event: *$title*\nTime: $time\n⚡ Make it count!",
      "🔔 Just in: *$title* kicks off at $time. 💪 Go shine!",
    ];

    return variations[Random().nextInt(variations.length)];
  }

  @override
  void initState() {
    super.initState();
    _startDate = widget.selectedDate;
    _endDate = widget.selectedDate.add(Duration(hours: 1));
    _titleController.text = widget.initialTitle ?? '';
    _initializePermissions();

    if (widget.eventId != null) {
      _loadEventDetails();
    }
  }

  void _loadEventDetails() async {
    if (widget.eventId != null) {
      DocumentSnapshot eventDoc = await FirebaseFirestore.instance.collection(
          'events').doc(widget.eventId).get();
      if (eventDoc.exists) {
        Map<String, dynamic> data = eventDoc.data() as Map<String, dynamic>;
        setState(() {
          _titleController.text = data['title'];
          _startDate = (data['start'] as Timestamp).toDate();
          _endDate = (data['end'] as Timestamp).toDate();
          _allDay = data['allDay'] ?? false;
          _reminder = data['reminder'] ?? '10 minutes before';
          _repeat = data['repeat'] ?? 'None';
          _priority = data['priority'] ?? 'Medium';
          _category = data['category'] ?? 'General';
          _locationController.text = data['location'] ?? '';
          _descriptionController.text = data['description'] ?? '';
        });
      }
    }
  }

  Future<void> _pickDateTime(bool isStart) async {
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(isStart ? _startDate : _endDate),
      );

      if (pickedTime != null) {
        setState(() {
          DateTime finalDateTime = DateTime(
              pickedDate.year, pickedDate.month, pickedDate.day,
              pickedTime.hour, pickedTime.minute);
          if (isStart) {
            _startDate = finalDateTime;
          } else {
            _endDate = finalDateTime;
          }
        });
      }
    }
  }

  String _safeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll(
        RegExp(r'[^a-z0-9]+'), '_') // replace non-alphanumeric with underscore
        .replaceAll(
        RegExp(r'^_+|_+$'), ''); // remove leading/trailing underscores
  }

  Duration _getReminderDuration(String reminder) {
    final Map<String, Duration> reminderMap = {
      'None': Duration.zero,
      '5 minutes before': Duration(minutes: 5),
      '10 minutes before': Duration(minutes: 10),
      '15 minutes before': Duration(minutes: 15),
      '30 minutes before': Duration(minutes: 30),
      '45 minutes before': Duration(minutes: 45),
      '1 hour before': Duration(hours: 1),
      '2 hours before': Duration(hours: 2),
      '3 hours before': Duration(hours: 3),
      '6 hours before': Duration(hours: 6),
      '12 hours before': Duration(hours: 12),
      '1 day before': Duration(days: 1),
      '2 days before': Duration(days: 2),
      '3 days before': Duration(days: 3),
      '1 week before': Duration(days: 7),
    };

    return reminderMap[reminder] ?? Duration.zero;
  }


  void _saveEvent() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Not logged in!")));
      return;
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();

    if (_formKey.currentState!.validate()) {
      int urgency = _startDate.difference(DateTime.now()).inDays;
      Duration reminderDuration = _getReminderDuration(_reminder);
      DateTime reminderTime = _startDate.subtract(reminderDuration);

      Map<String, dynamic> eventData = {
        'title': _titleController.text.trim(),
        'start': Timestamp.fromDate(_startDate),
        'end': Timestamp.fromDate(_endDate),
        'allDay': _allDay,
        'reminder': _reminder,
        'repeat': _repeat,
        'priority': _priority,
        'category': _category,
        'urgency': urgency,
        'location': _locationController.text.trim(),
        'description': _descriptionController.text.trim(),
        'reminderTime':Timestamp.fromDate(reminderTime.toUtc()),

    'userId': user.uid,
        'reminderSent': false,
        'token': fcmToken,

      };

      try {
        DocumentReference eventRef;

        if (widget.eventId != null) {
          // Editing existing event
          eventRef = FirebaseFirestore.instance.collection('events').doc(widget.eventId);
          await eventRef.update(eventData);
        } else {
          // New event
          String safeEventId = "${user.uid}_${_safeTitle(_titleController.text.trim())}";
          eventRef = FirebaseFirestore.instance.collection('events').doc(safeEventId);
          await eventRef.set(eventData);
        }


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.eventId == null ? "Event Added!" : "Event Updated!")),
        );

        Future.delayed(Duration(milliseconds: 300), () {
          Navigator.pop(context, true);
        });

      } catch (e) {
        print("❌ Error saving event: $e");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to save event.")),
        );
      }
    }
  }

  Future<void> _initializePermissions() async {
    await Permission.scheduleExactAlarm.request();
    if (await Permission.scheduleExactAlarm.isDenied) {
      await Permission.scheduleExactAlarm.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF101828),
      appBar: AppBar(
          backgroundColor: Color(0xFF101828),title: Text(widget.eventId == null ? "Add Event" : "Edit Event")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: "Event Title",
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),
                  labelStyle: TextStyle(color: Colors.white),),
                validator: (value) => value!.isEmpty ? 'Enter event title' : null,
              ),
              SizedBox(height: 20),
              SwitchListTile(
                title: Text("All-day event", style: TextStyle(color: Colors.white)),
                activeColor: Color(0xFF9D4EDD), // switch color (lavender)
                value: _allDay,
                onChanged: (value) => setState(() => _allDay = value),
              ),
              SizedBox(height: 20),
              ListTile(
                title: Text(
                  "Start: ${DateFormat.yMMMEd().add_jm().format(_startDate)}",
                  style: TextStyle(color: Colors.white),
                ),
                trailing: Icon(Icons.calendar_today, color: Colors.white),
                onTap: () => _pickDateTime(true),
              ),
              SizedBox(height: 20),
              ListTile(
                title: Text("End: ${DateFormat.yMMMEd().add_jm().format(_endDate)}",
                  style: TextStyle(color: Colors.white),),
                trailing: Icon(Icons.calendar_today,color:Colors.white),
                onTap: () => _pickDateTime(false),
              ),
              SizedBox(height: 20),
              DropdownButtonFormField(
                value: _priority,
                decoration: InputDecoration(labelText: "Priority",
                  labelStyle: TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),),
                items: _priorityOptions.map((priority) {
                  return DropdownMenuItem(value: priority, child: Text(priority));
                }).toList(),
                onChanged: (value) {
                  setState(() => _priority = value.toString());
                },
                dropdownColor: Color(0xFF1E1E2E),
                style: TextStyle(color: Colors.white),

              ),
              SizedBox(height: 20),
              DropdownButtonFormField(
                value: _category,
                decoration: InputDecoration(labelText: "Category",
                  labelStyle: TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),),
                items: _categoryOptions.map((category) {
                  return DropdownMenuItem(value: category, child: Text(category));
                }).toList(),
                onChanged: (value) {
                  setState(() => _category = value.toString());
                },
                dropdownColor: Color(0xFF1E1E2E),
                style: TextStyle(color: Colors.white),

              ),
              SizedBox(height: 20),
              DropdownButtonFormField(
                value: _reminder,
                decoration: InputDecoration(labelText: "Reminder",
                  labelStyle: TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),
                ),
                items: _reminderOptions.map((reminder) {
                  return DropdownMenuItem(value: reminder, child: Text(reminder));
                }).toList(),
                onChanged: (value) {
                  setState(() => _reminder = value.toString());
                  // ✅ SHOW SNACKBAR WHEN "None" IS SELECTED
                  if (value.toString().toLowerCase() == 'none') {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("⚠️ Reminder set to None — notification will not be scheduled."),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                dropdownColor: Color(0xFF1E1E2E),
                style: TextStyle(color: Colors.white),

              ),
              SizedBox(height: 20),
              DropdownButtonFormField(
                value: _repeat,
                decoration: InputDecoration(labelText: "Repeat",
                  labelStyle: TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),),
                items: _repeatOptions.map((repeat) {
                  return DropdownMenuItem(value: repeat, child: Text(repeat));
                }).toList(),
                onChanged: (value) {
                  setState(() => _repeat = value.toString());
                },
                dropdownColor: Color(0xFF1E1E2E),
                style: TextStyle(color: Colors.white),

              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _locationController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: "Location",
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),
                  labelStyle: TextStyle(color: Colors.white),),
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: "Description",
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),
                  labelStyle: TextStyle(color: Colors.white),),
                maxLines: 3,
              ),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saveEvent,
                child: Text(widget.eventId == null ? "Save" : "Update"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}