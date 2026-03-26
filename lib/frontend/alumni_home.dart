import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';

class AlumniHomePage extends StatefulWidget {
  const AlumniHomePage({super.key});
  @override
  State<AlumniHomePage> createState() => _AlumniHomePageState();
}

class _AlumniHomePageState extends State<AlumniHomePage>
    with TickerProviderStateMixin {
  // ================= PROFILE =================
  String name = "Loading...";
  String email = "";
  String imageUrl = "";
  String company = "";
  String designation = "";
  String batch = "";
  String phone = "";

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // ================= REQUESTS =================
  // Pending connection requests where this alumni is the target
  List<Map<String, dynamic>> _requests = [];
  bool _requestsLoading = true;
  StreamSubscription? _requestsSub;

  // ================= ACCEPTED =================
  // Accepted connections — we read from 'user' collection's acceptedAlumni array
  // but we also listen to connectionRequests for the accepted list.
  // Since student's `acceptedAlumni` stores alumniEmail/alumniId/alumniName,
  // we query connectionRequests with status=accepted to get student details.
  List<Map<String, dynamic>> _accepted = [];
  StreamSubscription? _acceptedSub;

  // ================= TAB =================
  int _currentTab = 0;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();

    _loadProfile();
    _startRequestsListener();
    _startAcceptedListener();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _requestsSub?.cancel();
    _acceptedSub?.cancel();
    super.dispose();
  }

  // ================= PROFILE =================
  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Collection is 'alumini' (matching your Firestore)
      final doc = await FirebaseFirestore.instance
          .collection('alumini')
          .doc(user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          name = data['name'] ?? 'Alumni';
          email = data['email'] ?? user.email ?? '';
          imageUrl = data['imageUrl'] ?? '';
          company = data['company'] ?? '';
          designation = data['designation'] ?? '';
          batch = data['batch'] ?? '';
          phone = data['phone'] ?? '';
        });
      }
    } catch (e) {
      debugPrint("Profile Error: $e");
    }
  }

  // ================= EMAIL FUNCTION =================
  Future<void> sendEmail(String studentEmail) async {
    final url = Uri.parse('https://api.emailjs.com/api/v1.0/email/send');
    try {
      final response = await http.post(
        url,
        headers: {
          'origin': 'http://localhost',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'service_id': 'service_wqbzw24',
          'template_id': 'template_rz8eq54',
          'user_id': '2UARGC9xXMSl69kXm',
          'template_params': {'to_email': studentEmail, 'alumni_email': email},
        }),
      );
      if (response.statusCode == 200) {
        debugPrint("✅ Email Sent");
      } else {
        debugPrint("❌ Email Failed: ${response.body}");
      }
    } catch (e) {
      debugPrint("❌ Email Error: $e");
    }
  }

  // ================= REQUEST LISTENER =================
  void _startRequestsListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _requestsSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .where('alumniId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _requests = snap.docs
                .map((d) => {'id': d.id, ...d.data()})
                .toList();
            _requestsLoading = false;
          });
        });
  }

  // ================= ACCEPTED LISTENER =================
  // Listens to connectionRequests where status='accepted' for this alumni.
  // This gives us studentName + studentEmail directly from the request doc.
  void _startAcceptedListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _acceptedSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .where('alumniId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _accepted = snap.docs
                .map((d) => {'id': d.id, ...d.data()})
                .toList();
          });
        });
  }

  // ================= ACCEPT =================
  Future<void> _acceptRequest(Map<String, dynamic> req) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;

      // 1. Update connectionRequests status to accepted
      await FirebaseFirestore.instance
          .collection('connectionRequests')
          .doc(req['id'])
          .update({'status': 'accepted'});

      // 2. Add this alumni's details to the student's acceptedAlumni array
      //    Student is in 'user' collection (your Firestore structure)
      await FirebaseFirestore.instance
          .collection('user')
          .doc(req['studentId'])
          .update({
            'acceptedAlumni': FieldValue.arrayUnion([
              {
                'alumniId': currentUser.uid,
                'alumniName': name,
                'alumniEmail': email, // uses email from alumni's 'alumini' doc
              },
            ]),
          });

      // 3. Save student email to this alumni's connectedStudents array in 'alumini' collection
      await FirebaseFirestore.instance
          .collection('alumini')
          .doc(currentUser.uid)
          .update({
            'connectedStudents': FieldValue.arrayUnion([
              req['studentEmail'] ?? '',
            ]),
          });

      // 4. Send email notification to the student
      if (req['studentEmail'] != null &&
          (req['studentEmail'] as String).isNotEmpty) {
        await sendEmail(req['studentEmail']);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Accepted & Email Sent"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Accept Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ================= REJECT =================
  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    try {
      await FirebaseFirestore.instance
          .collection('connectionRequests')
          .doc(req['id'])
          .update({'status': 'rejected'});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Request Rejected")));
      }
    } catch (e) {
      debugPrint("Reject Error: $e");
    }
  }

  // ================= LOGOUT =================
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const loginPage()),
        (route) => false,
      );
    }
  }

  // ============================================================
  //  PAGES
  // ============================================================

  // ---- HOME TAB ----
  Widget _buildHomePage() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),

            // Welcome card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    backgroundImage: imageUrl.isNotEmpty
                        ? NetworkImage(imageUrl)
                        : null,
                    child: imageUrl.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 30,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Welcome back,",
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                        Text(
                          name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (designation.isNotEmpty)
                          Text(
                            designation,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Stats row
            Row(
              children: [
                _statCard(
                  "Pending\nRequests",
                  _requests.length.toString(),
                  Icons.pending_actions,
                  Colors.orange,
                ),
                const SizedBox(width: 12),
                _statCard(
                  "Connections\nAccepted",
                  _accepted.length.toString(),
                  Icons.people,
                  Colors.green,
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Quick info
            const Text(
              "Your Details",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _infoTile(Icons.business, "Company", company),
            _infoTile(Icons.school, "Batch", batch),
            _infoTile(Icons.email, "Email", email),
            _infoTile(Icons.phone, "Phone", phone),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Text(
                value.isEmpty ? '—' : value,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- REQUESTS TAB ----
  Widget _buildRequestsPage() {
    if (_requestsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, color: Colors.white30, size: 64),
            SizedBox(height: 16),
            Text(
              "No Pending Requests",
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _requests.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final req = _requests[i];

        // Safely read fields — studentName & studentEmail must be set
        // when student creates the connectionRequest document
        final studentName = req['studentName']?.toString() ?? 'Unknown Student';
        final studentEmail = req['studentEmail']?.toString() ?? 'No email';

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.blueAccent.withOpacity(0.2),
              child: Text(
                studentName[0].toUpperCase(),
                style: const TextStyle(color: Colors.blueAccent),
              ),
            ),
            title: Text(
              studentName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              studentEmail,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Accept button
                GestureDetector(
                  onTap: () => _acceptRequest(req),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Reject button
                GestureDetector(
                  onTap: () => _rejectRequest(req),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.close, color: Colors.red, size: 20),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---- CONNECTIONS TAB ----
  // Reads from _accepted which is populated by the connectionRequests listener.
  // Each doc in connectionRequests (status=accepted) has:
  //   studentName, studentEmail, studentId, alumniId
  Widget _buildConnectionsPage() {
    if (_accepted.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, color: Colors.white30, size: 64),
            SizedBox(height: 16),
            Text(
              "No Connections Yet",
              style: TextStyle(color: Colors.white54, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _accepted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final con = _accepted[i];

        // Safe field reads from the connectionRequests document
        final studentName = con['studentName']?.toString() ?? 'Unknown Student';
        final studentEmail = con['studentEmail']?.toString() ?? 'No email';

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withOpacity(0.2)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.green.withOpacity(0.2),
              child: Text(
                studentName[0].toUpperCase(),
                style: const TextStyle(color: Colors.green),
              ),
            ),
            title: Text(
              studentName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  studentEmail,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "Connected",
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: const Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 22,
            ),
          ),
        );
      },
    );
  }

  // ---- PROFILE TAB ----
  Widget _buildProfilePage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 55,
            backgroundColor: Colors.blueAccent.withOpacity(0.2),
            backgroundImage: imageUrl.isNotEmpty
                ? NetworkImage(imageUrl)
                : null,
            child: imageUrl.isEmpty
                ? const Icon(Icons.person, size: 55, color: Colors.white)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (designation.isNotEmpty)
            Text(
              designation,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          const SizedBox(height: 24),
          _infoTile(Icons.business, "Company", company),
          _infoTile(Icons.school, "Batch", batch),
          _infoTile(Icons.email, "Email", email),
          _infoTile(Icons.phone, "Phone", phone),
          const SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.logout, color: Colors.white),
              label: const Text(
                "Logout",
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              onPressed: _logout,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  //  BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      _buildHomePage(),
      _buildRequestsPage(),
      _buildConnectionsPage(),
      _buildProfilePage(),
    ];

    final List<String> titles = [
      "Dashboard",
      "Requests",
      "Connections",
      "Profile",
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D1F),
        elevation: 0,
        title: Text(
          titles[_currentTab],
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_currentTab != 1 && _requests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Badge(
                label: Text(_requests.length.toString()),
                child: IconButton(
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: Colors.white,
                  ),
                  onPressed: () => setState(() => _currentTab = 1),
                ),
              ),
            ),
        ],
      ),
      body: IndexedStack(index: _currentTab, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        backgroundColor: const Color(0xFF0D1B2E),
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.white38,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: "Home",
          ),
          BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: _requests.isNotEmpty,
              label: Text(_requests.length.toString()),
              child: const Icon(Icons.pending_actions_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: _requests.isNotEmpty,
              label: Text(_requests.length.toString()),
              child: const Icon(Icons.pending_actions),
            ),
            label: "Requests",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.people_outline),
            activeIcon: Icon(Icons.people),
            label: "Connections",
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: "Profile",
          ),
        ],
      ),
    );
  }
}
