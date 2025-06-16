import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart'; // Update path as needed

class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadNotificationSetting();
  }

  Future<void> _loadNotificationSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
    });
  }

  Future<void> _toggleNotifications(bool value) async {
    setState(() => _notificationsEnabled = value);
    await NotificationService.setNotificationsEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF101828),
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF101828),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(Icons.person, color: Color(0xFF9D4EDD)),
            title: Text('Profile', style: TextStyle(color: Colors.white)),
            subtitle: Text('Manage your account', style: TextStyle(color: Colors.white70)),
            onTap: () {
              final user = FirebaseAuth.instance.currentUser;
              if (user != null) {
                Navigator.pushNamed(context, '/profile', arguments: user);
              }
            },
          ),
          Divider(color: Colors.white24),

          // Notification Toggle
          SwitchListTile(
            secondary: Icon(Icons.notifications, color: Color(0xFF9D4EDD)),
            title: Text('Notifications', style: TextStyle(color: Colors.white)),
            subtitle: Text('Enable or disable app notifications', style: TextStyle(color: Colors.white70)),
            value: _notificationsEnabled,
            onChanged: _toggleNotifications,
            activeColor: Colors.greenAccent,
          ),
          Divider(color: Colors.white24),

          // Privacy Info
          ListTile(
            leading: Icon(Icons.lock, color: Color(0xFF9D4EDD)),
            title: Text('Privacy', style: TextStyle(color: Colors.white)),
            subtitle: Text('How we handle your data', style: TextStyle(color: Colors.white70)),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: Color(0xFF1F2937),
                  title: Text('Privacy Policy', style: TextStyle(color: Colors.white)),
                  content: Text(
                    'We respect your privacy. Your data is stored securely and is never shared with third parties.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      child: Text('Close', style: TextStyle(color: Color(0xFF9D4EDD))),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(color: Colors.white24),

          // About Info
          ListTile(
            leading: Icon(Icons.info, color: Color(0xFF9D4EDD)),
            title: Text('About', style: TextStyle(color: Colors.white)),
            subtitle: Text('App version and developer', style: TextStyle(color: Colors.white70)),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: Color(0xFF1F2937),
                  title: Text('About This App', style: TextStyle(color: Colors.white)),
                  content: Text(
                    'Version: 1.0.0\nDeveloper: PDR\n\nThis app helps you plan, track, and manage tasks efficiently.Our Chatbot is at your service!!',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      child: Text('Close', style: TextStyle(color: Color(0xFF9D4EDD))),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              );
            },
          ),
          Divider(color: Colors.white24),

          ListTile(
            leading: Icon(Icons.logout, color: Colors.redAccent),
            title: Text('Logout', style: TextStyle(color: Colors.white)),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).pushReplacementNamed('/login');
            },
          ),
        ],
      ),
    );
  }
}
