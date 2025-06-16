import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'events.dart';
import 'package:firebase_auth/firebase_auth.dart';


class CalendarPage extends StatefulWidget {
  @override
  _CalendarPageState createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with SingleTickerProviderStateMixin {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _selectedDay = DateTime.now();
  DateTime _focusedDay = DateTime.now();
  List<Map<String, String>> _activeEvents = [];
  List<Map<String, String>> _expiredEvents = [];

  TabController? _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadEvents(_selectedDay);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  void _loadEvents(DateTime selectedDate) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    FirebaseFirestore.instance
        .collection('events')
        .where('userId', isEqualTo: user!.uid)
        .orderBy('start')
        .get()
        .then((snapshot) async {
      List<Map<String, String>> userEvents = [];
      List<Map<String, String>> expiredEvents = [];
      DateTime now = DateTime.now();

      for (var doc in snapshot.docs) {
        Map<String, dynamic> eventData = doc.data() as Map<String, dynamic>;

        if (!eventData.containsKey('start') || eventData['start'] is! Timestamp) {
          print("❌ Skipping event, missing or invalid 'start' field");
          continue;
        }

        // ✅ Convert to LOCAL time
        DateTime eventStartDate = (eventData['start'] as Timestamp).toDate().toLocal();

        if (isSameDay(eventStartDate, selectedDate)) {
          Map<String, String> event = {
            'id': doc.id,
            'title': eventData['title'],
            'time': DateFormat.jm().format(eventStartDate),
            'completed': eventData.containsKey('completed') && eventData['completed'] ? 'true' : 'false'
          };

          if (eventStartDate.isAfter(now)) {
            userEvents.add(event); // Future event ➔ Active
          } else {
            expiredEvents.add(event); // Past event ➔ Expired
          }
        }
      }

      List<Map<String, String>> tithiFestivals = await _fetchHolidayEvents(selectedDate);

      setState(() {
        _activeEvents = userEvents + tithiFestivals; // Always add holidays to active
        _expiredEvents = expiredEvents;
      });

      print("✅ Loaded ${_activeEvents.length} active events and ${_expiredEvents.length} expired events for $selectedDate");
    });
  }


  Future<List<Map<String, String>>> _fetchHolidayEvents(
      DateTime selectedDate) async {
    List<Map<String, String>> events = [];
    String formattedDate = DateFormat('yyyy-MM-dd').format(selectedDate);
    String url = "https://personal-ai-assistant-l3h3.onrender.com/holidays?date=$formattedDate";


    try {
      final response = await http.get(Uri.parse(url));

      print("Response Status Code: ${response.statusCode}");
      print("Response Body: ${response.body}");

      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);

        for (var holiday in data["holidays"]) {
          events.add({
            'id': holiday,
            'title': holiday,
            'time': 'All Day',
            'completed': 'false'
          });
        }
      } else {
        print("Holiday API Error: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching holidays: $e");
    }

    return events;
  }

  void _completeEvent(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DocumentSnapshot eventSnapshot = await FirebaseFirestore.instance.collection('events').doc(eventId).get();

    if (eventSnapshot.exists && eventSnapshot['userId'] == user.uid) {
      await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Event marked as completed"), duration: Duration(seconds: 1)),
      );
      Future.delayed(Duration(seconds: 1), () {
        _loadEvents(_selectedDay);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Unauthorized action")),
      );
    }
  }


  void _removeEvent(String eventId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    DocumentSnapshot eventSnapshot = await FirebaseFirestore.instance.collection('events').doc(eventId).get();

    if (eventSnapshot.exists && eventSnapshot['userId'] == user.uid) {
      await FirebaseFirestore.instance.collection('events').doc(eventId).delete();
      _loadEvents(_selectedDay);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Unauthorized action")),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Calendar"),
        bottom: _tabController != null
            ? TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: "Active Events"),
            Tab(text: "Expired Events"),
          ],
        )
            : null,
      ),
      body: _tabController == null
          ? Center(child: CircularProgressIndicator())
          : Column(
        children: [
          TableCalendar(
            firstDay: DateTime(2000),
            lastDay: DateTime(2100),
            focusedDay: _focusedDay,
            calendarFormat: _calendarFormat,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });

              _loadEvents(selectedDay);
            },
            onFormatChanged: (format) {
              setState(() {
                _calendarFormat = format;
              });
            },
        calendarStyle: CalendarStyle(
        defaultTextStyle: TextStyle(color: Colors.white),    // Normal days
        weekendTextStyle: TextStyle(color: Colors.white),   // Weekends
        outsideTextStyle: TextStyle(color: Colors.white54), // Out-of-month days
        selectedTextStyle: TextStyle(color: Colors.black),  // Selected day text
        selectedDecoration: BoxDecoration(
          color: Colors.deepPurple,
          shape: BoxShape.circle,
        ),
          ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildActiveEventsList(),
                _buildExpiredEventsList(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final updated = await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => AddEventPage(selectedDate: _selectedDay)),
          );
          if (updated == true) {
            _loadEvents(_selectedDay);
          }
    },
        child: Icon(Icons.add),
      ),
    );
  }

  Widget _buildActiveEventsList() {
    return _activeEvents.isNotEmpty
        ? ListView.builder(
      itemCount: _activeEvents.length,
      itemBuilder: (context, index) {
        final event = _activeEvents[index];
        return ListTile(
          leading: CircleAvatar(child: Text("${index + 1}")),
          title: Text("${event['time']} - ${event['title']}",
            style: TextStyle(color: Colors.white),
          ),

          onTap: () async {
             await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AddEventPage(
                      selectedDate: _selectedDay,
                      eventId: event['id'], // ✅ Pass event ID
                      initialTitle: event['title'], // ✅ Pass existing title
                    ),
              ),
            );
          _loadEvents(_selectedDay);

      },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check_circle, color: Colors.green),
                onPressed: () => _completeEvent(event['id']!),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeEvent(event['id']!),
              ),
            ],
          ),
        );
      },
    )
        : Center(child: Text("No active events", style: TextStyle(color: Colors.white)));
  }

  Widget _buildExpiredEventsList() {
    return _expiredEvents.isNotEmpty
        ? ListView.builder(
      itemCount: _expiredEvents.length,
      itemBuilder: (context, index) {
        final event = _expiredEvents[index];
        return ListTile(
          leading: CircleAvatar(child: Text("${index + 1}")),
          title: Text("${event['time']} - ${event['title']}",
              style: TextStyle(color: Colors.white),),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AddEventPage(
                      selectedDate: _selectedDay,
                      eventId: event['id'], // ✅ Pass event ID
                      initialTitle: event['title'], // ✅ Pass existing title
                    ),
              ),
            );
          _loadEvents(_selectedDay);

      },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(Icons.check_circle, color: Colors.grey),
                onPressed: () => _completeEvent(event['id']!),
              ),
              IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () => _removeEvent(event['id']!),
              ),
            ],
          ),
        );
      },
    )
        : Center(child: Text("No expired events",style: TextStyle(color: Colors.white)));
  }
  DateTime calculateReminderTime(DateTime eventStart, String reminder) {
    switch (reminder) {
      case '10 minutes before':
        return eventStart.subtract(Duration(minutes: 10));
      case '30 minutes before':
        return eventStart.subtract(Duration(minutes: 30));
      case '1 hour before':
        return eventStart.subtract(Duration(hours: 1));
      default:
        return eventStart; // Default: no change
    }
  }

}
