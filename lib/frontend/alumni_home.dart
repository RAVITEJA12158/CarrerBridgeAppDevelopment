import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';
import 'chat_page.dart';

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
  List<Map<String, dynamic>> _requests = [];
  bool _requestsLoading = true;
  StreamSubscription? _requestsSub;

  // ================= ACCEPTED =================
  List<Map<String, dynamic>> _accepted = [];
  StreamSubscription? _acceptedSub;

  // ================= TAB =================
  int _currentTab = 0;

  // ================= JOB POST =================
  final _jobTitleCtrl = TextEditingController();
  final _jobCompanyCtrl = TextEditingController();
  final _jobLocationCtrl = TextEditingController();
  final _jobDescCtrl = TextEditingController();
  final _jobLinkCtrl = TextEditingController();
  String _jobTypeSelected = 'Full-time';

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
    _jobTitleCtrl.dispose();
    _jobCompanyCtrl.dispose();
    _jobLocationCtrl.dispose();
    _jobDescCtrl.dispose();
    _jobLinkCtrl.dispose();
    super.dispose();
  }

  // ================= SAFE HELPERS =================
  // Handles null, empty string, whitespace — prevents RangeError
  String _safeName(dynamic value, String fallback) {
    final s = (value?.toString() ?? '').trim();
    return s.isNotEmpty ? s : fallback;
  }

  // Returns first character safely — NEVER crashes on empty string
  String _initial(String name) {
    final s = name.trim();
    return s.isNotEmpty ? s[0].toUpperCase() : '?';
  }

  // ================= PROFILE =================
  Future<void> _loadProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('alumini')
          .doc(user.uid)
          .get();

      if (doc.exists && mounted) {
        final data = doc.data()!;
        setState(() {
          name = _safeName(data['name'], 'Alumni');
          email = _safeName(data['email'], user.email ?? '');
          imageUrl = (data['imageUrl'] ?? '').toString().trim();
          company = _safeName(data['company'], '');
          designation = _safeName(data['designation'], '');
          batch = _safeName(data['batch'], '');
          phone = _safeName(data['phone'], '');
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

      // 2. Add alumni details into student's acceptedAlumni array
      await FirebaseFirestore.instance
          .collection('user')
          .doc(req['studentId'])
          .update({
            'acceptedAlumni': FieldValue.arrayUnion([
              {
                'alumniId': currentUser.uid,
                'alumniName': name,
                'alumniEmail': email,
              },
            ]),
          });

      // 3. Save student email into alumni's connectedStudents array
      await FirebaseFirestore.instance
          .collection('alumini')
          .doc(currentUser.uid)
          .update({
            'connectedStudents': FieldValue.arrayUnion([
              req['studentEmail'] ?? '',
            ]),
          });

      // 4. Send email notification to student
      final studentEmail = (req['studentEmail'] ?? '').toString().trim();
      if (studentEmail.isNotEmpty) {
        await sendEmail(studentEmail);
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
          border: Border.all(color: color.withValues(alpha: 0.3)),
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
                Text(
                  value.isEmpty ? '—' : value,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
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

        // ✅ _safeName handles null + empty + whitespace
        final studentName = _safeName(req['studentName'], 'Unknown Student');
        final studentEmail = _safeName(req['studentEmail'], 'No email');

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
              backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
              // ✅ _initial() never crashes — returns '?' for empty
              child: Text(
                _initial(studentName),
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
                // Accept
                GestureDetector(
                  onTap: () => _acceptRequest(req),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
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
                // Reject
                GestureDetector(
                  onTap: () => _rejectRequest(req),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
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
        final studentName = _safeName(con['studentName'], 'Unknown Student');
        final studentEmail = _safeName(con['studentEmail'], 'No email');
        final studentId = _safeName(con['studentId'], '');

        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1B2E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: CircleAvatar(
              backgroundColor: Colors.green.withValues(alpha: 0.2),
              child: Text(
                _initial(studentName),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
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
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 22),
                // ── Chat button ────────────────────────────────────
                if (studentId.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChatPage(
                            peerId: studentId,
                            peerName: studentName,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E90FF).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF1E90FF).withValues(alpha: 0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.chat_bubble_outline,
                        color: Color(0xFF1E90FF),
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ],
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
            backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
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

  // ---- POST JOB TAB ----
  Widget _buildPostJobPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              children: [
                Icon(Icons.work_outline, color: Colors.white, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Post a Job',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Help students with opportunities',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Job Type',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: ['Full-time', 'Internship', 'Part-time']
                .map(
                  (t) => GestureDetector(
                    onTap: () => setState(() => _jobTypeSelected = t),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _jobTypeSelected == t
                            ? const Color(0xFF1E90FF)
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _jobTypeSelected == t
                              ? const Color(0xFF1E90FF)
                              : Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Text(
                        t,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _jobTypeSelected == t
                              ? Colors.white
                              : Colors.white54,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 20),
          _jobField(_jobTitleCtrl, 'Job Title *', Icons.work_outline),
          const SizedBox(height: 12),
          _jobField(_jobCompanyCtrl, 'Company *', Icons.business_outlined),
          const SizedBox(height: 12),
          _jobField(_jobLocationCtrl, 'Location', Icons.location_on_outlined),
          const SizedBox(height: 12),
          _jobField(
            _jobDescCtrl,
            'Description',
            Icons.description_outlined,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _jobField(_jobLinkCtrl, 'Apply Link (URL)', Icons.link_outlined),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _postJob,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E90FF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Post Job',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _jobField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hint,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: TextField(
            controller: ctrl,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 13,
              ),
              prefixIcon: Icon(icon, color: const Color(0xFF1E90FF), size: 18),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _postJob() async {
    if (_jobTitleCtrl.text.trim().isEmpty ||
        _jobCompanyCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and Company are required.')),
      );
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('jobs').add({
        'title': _jobTitleCtrl.text.trim(),
        'company': _jobCompanyCtrl.text.trim(),
        'location': _jobLocationCtrl.text.trim(),
        'type': _jobTypeSelected,
        'description': _jobDescCtrl.text.trim(),
        'applyLink': _jobLinkCtrl.text.trim(),
        'postedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'postedByRole': 'alumni',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _jobTitleCtrl.clear();
      _jobCompanyCtrl.clear();
      _jobLocationCtrl.clear();
      _jobDescCtrl.clear();
      _jobLinkCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Job posted! Students can now see it.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() => _currentTab = 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
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
      _buildPostJobPage(),
      _buildProfilePage(),
    ];

    final List<String> titles = [
      "Dashboard",
      "Requests",
      "Connections",
      "Post Job",
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
            icon: Icon(Icons.post_add_outlined),
            activeIcon: Icon(Icons.post_add),
            label: "Post Job",
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
