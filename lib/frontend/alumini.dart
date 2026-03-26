// alumini.dart
// ✅ This page is no longer needed as a separate login/register.
// It simply redirects to the unified loginPage with 'Alumni' pre-selected.
// Keep this file so existing Navigator.push(aluminiPage()) calls don't break.

import 'package:flutter/material.dart';
import 'login.dart';

class aluminiPage extends StatelessWidget {
  const aluminiPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Immediately replace this route with the main login page,
    // pre-selecting the Alumni tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const loginPage(initialRole: 'alumni'),
        ),
      );
    });

    // Show a brief branded splash while the redirect fires
    return const Scaffold(
      backgroundColor: Color(0xFF060D1F),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1E90FF))),
    );
  }
}
