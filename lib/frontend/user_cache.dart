import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// UserCache — Singleton that holds the logged-in user's data in memory.
//
// Usage:
//   await UserCache.instance.load();         // fetch from DB (first time only)
//   String name = UserCache.instance.name;   // read from cache (no DB call)
//   UserCache.instance.clear();              // call on logout
// ─────────────────────────────────────────────────────────────────────────────
class UserCache {
  UserCache._();
  static final UserCache instance = UserCache._();

  // ── Cached fields ─────────────────────────────────────────────────────────
  String name = '';
  String email = '';
  String phone = '';
  String imageUrl = '';
  String role = '';
  String uid = '';

  // Student-specific
  String rollNo = '';
  String regNo = '';
  String branch = '';
  String year = '';

  // Alumni-specific
  String batch = '';
  String company = '';
  String designation = '';

  // Admin-specific
  String department = '';

  // ── State ─────────────────────────────────────────────────────────────────
  bool _loaded = false;
  bool get isLoaded => _loaded;

  // ── Collection resolver ───────────────────────────────────────────────────
  // Returns the correct Firestore collection based on role
  static String collectionForRole(String role) {
    switch (role.toLowerCase()) {
      case 'alumni':
        return 'alumini';
      case 'admin':
        return 'admin';
      default:
        return 'user'; // student
    }
  }

  // ── Load from Firestore (only if not already loaded) ──────────────────────
  Future<void> load({bool forceRefresh = false}) async {
    if (_loaded && !forceRefresh) return; // ← use cache, skip DB call

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      uid = user.uid;
      email = user.email ?? '';

      // We don't know role yet on first load, so check all 3 collections
      DocumentSnapshot? doc = await _findUserDoc(uid);

      if (doc == null || !doc.exists) {
        debugPrint('UserCache: user doc not found in any collection');
        return;
      }

      final d = doc.data() as Map<String, dynamic>;

      // ── Common fields ────────────────────────────────────────────────────
      name = d['name'] ?? '';
      phone = d['phone'] ?? '';
      imageUrl = d['imageUrl'] ?? '';
      role = (d['role'] ?? 'student').toString().toLowerCase();

      // ── Role-specific fields ─────────────────────────────────────────────
      if (role == 'student') {
        rollNo = d['rollNo'] ?? '';
        regNo = d['regNo'] ?? '';
        branch = d['branch'] ?? '';
        year = d['year'] ?? '';
      } else if (role == 'alumni') {
        batch = d['batch'] ?? '';
        company = d['company'] ?? '';
        designation = d['designation'] ?? '';
      } else if (role == 'admin') {
        department = d['department'] ?? '';
      }

      _loaded = true;
      debugPrint('✅ UserCache loaded for: $name ($role)');
    } catch (e) {
      debugPrint('UserCache load error: $e');
    }
  }

  // ── Update a specific field (call after user edits profile) ──────────────
  Future<void> updateField(String key, dynamic value) async {
    try {
      final collection = collectionForRole(role);
      await FirebaseFirestore.instance.collection(collection).doc(uid).update({
        key: value,
      });

      // Update local cache too
      switch (key) {
        case 'name':
          name = value as String;
          break;
        case 'phone':
          phone = value as String;
          break;
        case 'imageUrl':
          imageUrl = value as String;
          break;
        case 'branch':
          branch = value as String;
          break;
        case 'year':
          year = value as String;
          break;
        case 'company':
          company = value as String;
          break;
        case 'designation':
          designation = value as String;
          break;
        case 'department':
          department = value as String;
          break;
        default:
          break;
      }
      debugPrint('✅ UserCache field updated: $key = $value');
    } catch (e) {
      debugPrint('UserCache updateField error: $e');
    }
  }

  // ── Clear cache on logout ─────────────────────────────────────────────────
  void clear() {
    name = '';
    email = '';
    phone = '';
    imageUrl = '';
    role = '';
    uid = '';
    rollNo = '';
    regNo = '';
    branch = '';
    year = '';
    batch = '';
    company = '';
    designation = '';
    department = '';
    _loaded = false;
    debugPrint('🗑️ UserCache cleared');
  }

  // ── Helper: find which collection the user belongs to ────────────────────
  Future<DocumentSnapshot?> _findUserDoc(String uid) async {
    // Try each collection in order of likelihood
    for (final col in ['user', 'alumini', 'admin']) {
      final doc = await FirebaseFirestore.instance
          .collection(col)
          .doc(uid)
          .get();
      if (doc.exists) return doc;
    }
    return null;
  }
}
