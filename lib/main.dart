import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'frontend/login.dart';
import 'frontend/homepage.dart';       // Student
import 'frontend/alumni_home.dart';    // Alumni
import 'frontend/admin_home.dart';     // Admin

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const Myapp());
}

class Myapp extends StatelessWidget {
  const Myapp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'Georgia'),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {

          // ── Still connecting ───────────────────────────────────
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _SplashScreen();
          }

          // ── Not logged in ──────────────────────────────────────
          if (!snapshot.hasData || snapshot.data == null) {
            return const loginPage();
          }

          // ── Logged in — fetch role and route ───────────────────
          // ✅ Check all 3 collections to find which one this user belongs to
          return FutureBuilder<String>(
            future: _resolveUserRole(snapshot.data!.uid),
            builder: (context, roleSnap) {
              if (roleSnap.connectionState == ConnectionState.waiting) {
                return const _SplashScreen();
              }
              switch (roleSnap.data ?? 'student') {
                case 'admin':
                  return const AdminHomePage();
                case 'alumni':
                  return const AlumniHomePage();
                default:
                  return const HomePage();
              }
            },
          );
        },
      ),
    );
  }
}

// ── Resolve which collection the user belongs to ──────────────────────────────
// Collections: 'user' (students), 'alumini' (alumni), 'admin' (admins)
Future<String> _resolveUserRole(String uid) async {
  // Check 'user' collection first (most common)
  final userDoc = await FirebaseFirestore.instance
      .collection('user').doc(uid).get();
  if (userDoc.exists) return 'student';

  // Check 'alumini' collection
  final alumniDoc = await FirebaseFirestore.instance
      .collection('alumini').doc(uid).get();
  if (alumniDoc.exists) return 'alumni';

  // Check 'admin' collection
  final adminDoc = await FirebaseFirestore.instance
      .collection('admin').doc(uid).get();
  if (adminDoc.exists) return 'admin';

  // Not found in any collection — default to student home
  return 'student';
}

// ── Splash Screen ─────────────────────────────────────────────────────────────
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E27), Color(0xFF0D2137), Color(0xFF0A3D62)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFF1E90FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFF1E90FF).withOpacity(0.4),
                    width: 1.5),
              ),
              child: const Icon(Icons.work_outline,
                  color: Color(0xFF1E90FF), size: 36),
            ),
            const SizedBox(height: 20),
            const Text('CareerBridge',
                style: TextStyle(fontSize: 26,
                    fontWeight: FontWeight.w800, color: Colors.white,
                    letterSpacing: 0.5)),
            const SizedBox(height: 6),
            const Text('Student Job & Internship Finder',
                style: TextStyle(fontSize: 13, color: Color(0xFF7FA7C9))),
            const SizedBox(height: 40),
            const SizedBox(width: 28, height: 28,
                child: CircularProgressIndicator(
                    strokeWidth: 2.5, color: Color(0xFF1E90FF))),
          ]),
        ),
      ),
    );
  }
}