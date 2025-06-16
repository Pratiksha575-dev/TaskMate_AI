import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'notification_service.dart';



class AddTaskPage extends StatefulWidget {
  final String collectionName;
  final String? taskId;
  final String? initialTitle;
  final String? initialDescription;
  final DateTime? initialDueDate;
  final int? initialReminderMinutes;

  AddTaskPage({
    required this.collectionName,
    this.taskId,
    this.initialTitle,
    this.initialDescription,
    this.initialDueDate,
    this.initialReminderMinutes,
  });

  @override
  _AddTaskPageState createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  DateTime _dueDate = DateTime.now();
  String _selectedReminder = '5 minutes before'; // Default


  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    if (widget.taskId != null) {
      _titleController.text = widget.initialTitle ?? '';
      _descriptionController.text = widget.initialDescription ?? '';
      _dueDate = widget.initialDueDate ?? DateTime.now();

      // ✅ Set selectedReminder correctly
      if (widget.initialReminderMinutes != null) {
        if (widget.initialReminderMinutes == 5) {
          _selectedReminder = '5 minutes before';
        } else if (widget.initialReminderMinutes == 10) {
          _selectedReminder = '10 minutes before';
        } else if (widget.initialReminderMinutes == 30) {
          _selectedReminder = '30 minutes before';
        } else if (widget.initialReminderMinutes == 60) {
          _selectedReminder = '1 hour before';
        }
      }
    }
  }


  /// Function to select both Date and Time for the due date
  Future<void> _pickDueDate() async {
    DateTime today = DateTime.now();
    DateTime firstAvailableDate = today; // First available date is today

    // Ensure initialDate is at least firstAvailableDate
    DateTime initialDate = _dueDate.isBefore(firstAvailableDate) ? firstAvailableDate : _dueDate;

    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstAvailableDate,
      lastDate: DateTime(2100),
    );

    if (pickedDate != null) {
      TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_dueDate),
      );

      if (pickedTime != null) {
        setState(() {
          _dueDate = DateTime(
            pickedDate.year,
            pickedDate.month,
            pickedDate.day,
            pickedTime.hour,
            pickedTime.minute,
          );
        });
      }
    }
  }


  void _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Not logged in!")));
      return;
    }
    final fcmToken = await FirebaseMessaging.instance.getToken();
    int reminderMinutes = 5; // Default to 5 mins

    if (_selectedReminder == '10 minutes before') {
      reminderMinutes = 10;
    } else if (_selectedReminder == '30 minutes before') {
      reminderMinutes = 30;
    } else if (_selectedReminder == '1 hour before') {
      reminderMinutes = 60;
    }

    CollectionReference tasksCollection = FirebaseFirestore.instance.collection(widget.collectionName);

    if (widget.taskId != null) {
      // Updating an existing task
      await tasksCollection.doc(widget.taskId).update({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'DueDate': Timestamp.fromDate(_dueDate),
        'reminderTime': Timestamp.fromDate(_dueDate.subtract(Duration(minutes: reminderMinutes)).toUtc()),
        'timestamp': FieldValue.serverTimestamp(),
        'completed': false,
        'userId': user.uid,
        'reminderMinutes': reminderMinutes,
        'reminderSent': false,
        'token': fcmToken,
      });
    } else {
      // ✅ Adding a new task without setting manual ID
      await tasksCollection.add({
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'DueDate': Timestamp.fromDate(_dueDate),
        'reminderTime': Timestamp.fromDate(_dueDate.subtract(Duration(minutes: reminderMinutes)).toUtc()),
        'timestamp': FieldValue.serverTimestamp(),
        'completed': false,
        'userId': user.uid,
        'reminderMinutes': reminderMinutes,
        'reminderSent': false,
        'token': fcmToken,
      });
    }
    print("Saving task to Firestore: ${_titleController.text}, ${_descriptionController.text}, $_dueDate,Reminder: $reminderMinutes minutes");
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.taskId == null ? "Add Task" : "Edit Task")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _titleController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: "Task Title")
                ,
                validator: (value) => value!.isEmpty ? 'Enter task title' : null,
              ),
              SizedBox(height: 20),
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(labelText: "Description"),
                maxLines: 3,
              ),
              SizedBox(height: 20),
              ListTile(
                title: Text("Due Date: ${DateFormat.yMMMEd().add_jm().format(_dueDate)}",
                    style: TextStyle(fontSize: 14, color: Colors.white)),
                trailing: Icon(Icons.calendar_today,color:Colors.white),
                onTap: _pickDueDate,
              ),
              SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _selectedReminder,
                decoration: InputDecoration(
                  labelText: 'Reminder Time',
                  border: OutlineInputBorder(),
                  labelStyle: TextStyle(color: Colors.white),
                  filled: true,
                  fillColor: Color(0xFF1E1E2E),
                ),
                items: [
                  '5 minutes before',
                  '10 minutes before',
                  '30 minutes before',
                  '1 hour before',
                ].map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: (newValue) {
                  setState(() {
                    _selectedReminder = newValue!;
                  });

                },
                dropdownColor: Color(0xFF1E1E2E),
                style: TextStyle(color: Colors.white),
              ),

              SizedBox(height: 40),
              ElevatedButton(
                onPressed: _saveTask,
                child: Text(widget.taskId == null ? "Save" : "Update"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
