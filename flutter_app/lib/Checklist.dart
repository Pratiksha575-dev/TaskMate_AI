import 'package:flutter/material.dart';
import 'tasklist.dart';

class CheckListPage extends StatefulWidget {
  @override
  _CheckListPageState createState() => _CheckListPageState();
}

class _CheckListPageState extends State<CheckListPage> {
  List<Map<String, dynamic>> categories = [
    {'name': 'Personal', 'subcategories': ['Self', 'Family']},
    {'name': 'Work', 'subcategories': ['Self Work', 'Team']},
  ];

  void _addCategory() {
    TextEditingController categoryController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Add New Category"),
        content: TextField(
          controller: categoryController,
          decoration: InputDecoration(hintText: "Enter category name"),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (categoryController.text.isNotEmpty) {
                setState(() {
                  categories.add({'name': categoryController.text, 'subcategories': ['Default']});
                });
              }
              Navigator.pop(context);
            },
            child: Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('TO-DO LIST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        elevation: 5,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: categories.map((category) {
            return _buildCategoryCard(context, category['name'], category['subcategories']);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, String title, List<String> subcategories) {
    return GestureDetector(
      onTap: () => _navigateTo(context, CategoryPage(title: title, categories: subcategories)),
      child: Card(
        margin: EdgeInsets.symmetric(vertical: 15, horizontal: 30),
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.deepPurple[400],
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

void _navigateTo(BuildContext context, Widget page) {
  Navigator.push(context, MaterialPageRoute(builder: (context) => page));
}

class CategoryPage extends StatelessWidget {
  final String title;
  final List<String> categories;

  CategoryPage({required this.title, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        elevation: 5,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: categories
              .map((cat) => _buildCategoryButton(context, cat))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCategoryButton(BuildContext context, String title) {
    return GestureDetector(
      onTap: () => _navigateTo(context, TaskList(title: '$title Tasks', collectionName: 'tasks_$title'.replaceAll(' ', '_').toLowerCase())),

      child: Container(
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 40),
        padding: EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: Colors.deepPurple[300],
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(color: Colors.deepPurple.withOpacity(0.4), blurRadius: 8, offset: Offset(2, 2)),
          ],
        ),
        child: Center(
          child: Text(
            title,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
