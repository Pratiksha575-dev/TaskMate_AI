import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'add_tasks.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TaskList extends StatefulWidget {
  final String title;
  final String collectionName;

  TaskList({required this.title, required this.collectionName});

  @override
  _TaskListState createState() => _TaskListState();
}

class _TaskListState extends State<TaskList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late CollectionReference tasksCollection;

  @override
  void initState() {
    super.initState();
    print("🚀 TaskList Initialized: ${widget.title}");

    tasksCollection = _firestore.collection(
      widget.collectionName.replaceAll(' ', '').toLowerCase(),
    );
  }

  void _addTask() async {
    print("➕ Adding new task...");
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskPage(collectionName: widget.collectionName),
      ),
    );
    print("✅ Task added successfully!");
  }

  void _editTask(DocumentSnapshot task) async {
    print("✏️ Editing Task ID: ${task.id}");

    try {
      dynamic dueDateValue = task['DueDate'];
      DateTime taskDueDate;

      if (dueDateValue is Timestamp) {
        taskDueDate = dueDateValue.toDate();
      } else if (dueDateValue is String) {
        taskDueDate = DateFormat('yyyy-MM-dd HH:mm:ss').parse(dueDateValue);
      } else {
        taskDueDate = DateTime.now();
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddTaskPage(
            collectionName: widget.collectionName,
            taskId: task.id,
            initialTitle: task['title'],
            initialDescription: task['description'],
            initialDueDate: taskDueDate,
          ),
        ),
      );
      print("✅ Task updated successfully!");
    } catch (e) {
      print("❌ Error editing task: $e");
    }
  }

  void _completeTask(String taskId) async {
    try {
      print("✔️ Completing Task ID: $taskId");
      await tasksCollection.doc(taskId).update({'completed': true});

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Task Completed"),
          duration: Duration(seconds: 1),
        ),
      );

      Future.delayed(Duration(seconds: 1), () {
        tasksCollection.doc(taskId).delete();
        print("🗑️ Task deleted after completion.");
      });
    } catch (e) {
      print("❌ Error completing task: $e");
    }
  }

  void _deleteTask(String taskId) async {
    try {
      print("🗑️ Deleting Task ID: $taskId");
      await tasksCollection.doc(taskId).delete();
      print("✅ Task deleted successfully!");
    } catch (e) {
      print("❌ Error deleting task: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF101828),
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Color(0xFF101828),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: tasksCollection
            .where('userId', isEqualTo: FirebaseAuth.instance.currentUser!.uid) // 🆕 only current user's tasks
            .orderBy('DueDate')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            print("⏳ Loading tasks...");
            return Center(child: CircularProgressIndicator());
          }

          final tasks = snapshot.data!.docs;
          print("📋 Loaded ${tasks.length} tasks.");

          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              var task = tasks[index];
              dynamic dueDateValue = task['DueDate'];
              DateTime taskDueDate;

              try {
                if (dueDateValue is Timestamp) {
                  taskDueDate = dueDateValue.toDate();
                } else if (dueDateValue is String) {
                  taskDueDate = DateFormat('yyyy-MM-dd HH:mm:ss').parse(dueDateValue);
                } else {
                  taskDueDate = DateTime.now();
                }
              } catch (e) {
                print("❌ Error parsing DueDate for Task ${task.id}: $e");
                taskDueDate = DateTime.now();
              }

              bool isCompleted = task['completed'] ?? false;

              return Card(
                color: Color(0xFF1E1E2E),
                elevation: 3,
                margin: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ListTile(
                  onTap: () => _editTask(task),
                  leading: CircleAvatar(
                    backgroundColor: Color(0xFF9D4EDD),
                    child: Text(
                      "${index + 1}",
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  title: Text(
                    task['title'],
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      decoration: isCompleted ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      "📅 ${DateFormat.yMMMEd().add_jm().format(taskDueDate)}\n📝 ${task['description']}",
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.check_circle,
                            color: isCompleted ? Colors.green : Color(0xFF9D4EDD)),
                        onPressed: () => _completeTask(task.id),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _deleteTask(task.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Color(0xFF9D4EDD),
        onPressed: _addTask,
        child: Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
