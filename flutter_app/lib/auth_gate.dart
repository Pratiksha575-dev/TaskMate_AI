import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart'; // for HomePage
import 'login.dart';
import 'package:dialog_flowtter/dialog_flowtter.dart';

class AuthGate extends StatelessWidget {
  final DialogFlowtter dialogFlowtter;

  AuthGate({required this.dialogFlowtter});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasData) {
          return HomePage(dialogFlowtter: dialogFlowtter);
        } else {
          return LoginPage(dialogFlowtter: dialogFlowtter);
        }
      },
    );
  }
}