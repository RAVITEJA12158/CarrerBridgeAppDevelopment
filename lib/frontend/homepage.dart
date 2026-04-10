import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import './login.dart';
import './user_cache.dart';
import './job_detail_page.dart';
import './chat_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String name = "Loading...";
  String email = "";
  String imageUrl = "";
  String role = "student";
  String phone = "";
  String branch = "";
  String regNo = "";
  String rollNo = "";
  String year = "";

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // ── Jobs from Firestore ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _jobs = [];
  bool _jobsLoading = true;
  Set<String> _savedJobIds = {};
  Set<String> _pendingAlumniIds = {};
  List<Map<String, dynamic>> _acceptedConnections = [];
  int _currentTab = 0;

  // ── Search ────────────────────────────────────────────────────────────────
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // ── Job tab filter: 0=All, 1=Admin, 2=Alumni ──────────────────────────────
  int _jobTabFilter = 0;

  // ── Real-time stream subscriptions ───────────────────────────────────────
  StreamSubscription? _studentDocSub;
  StreamSubscription? _pendingRequestsSub;

  // ── Alumni from Firestore ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _alumni = [];
  bool _alumniLoading = true;
  String? _alumniError;

  final List<Color> _alumniColors = [
    Color(0xFF1E90FF),
    Color(0xFF00C9A7),
    Color(0xFFFFA940),
    Color(0xFFFF6B8A),
    Color(0xFFA78BFA),
    Color(0xFF34D399),
  ];

  final List<Color> _jobColors = [
    Color(0xFF1E90FF),
    Color(0xFF00C9A7),
    Color(0xFFFFA940),
    Color(0xFFFF6B8A),
    Color(0xFFA78BFA),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    loadUserProfile();
    _loadJobs();
    loadAlumni();
    _loadSavedJobs();
    _startRealTimeListeners();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _studentDocSub?.cancel();
    _pendingRequestsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ── Filtered jobs (search + tab filter) ─────────────────────────────────
  List<Map<String, dynamic>> get _filteredJobs {
    var list = _jobs;
    if (_jobTabFilter == 1) {
      list = list
          .where(
            (j) =>
                (j['postedByRole'] ?? 'admin').toString().toLowerCase() ==
                'admin',
          )
          .toList();
    } else if (_jobTabFilter == 2) {
      list = list
          .where(
            (j) =>
                (j['postedByRole'] ?? '').toString().toLowerCase() == 'alumni',
          )
          .toList();
    }
    if (_searchQuery.isEmpty) return list;
    final q = _searchQuery.toLowerCase();
    return list.where((j) {
      return (j['title'] as String).toLowerCase().contains(q) ||
          (j['company'] as String).toLowerCase().contains(q) ||
          (j['location'] as String).toLowerCase().contains(q) ||
          (j['type'] as String).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> loadUserProfile() async {
    try {
      await UserCache.instance.load();
      final user = FirebaseAuth.instance.currentUser;
      Map<String, dynamic> extra = {};
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('user')
            .doc(user.uid)
            .get();
        if (doc.exists) extra = doc.data() ?? {};
      }
      if (!mounted) return;
      setState(() {
        name = UserCache.instance.name.isNotEmpty
            ? UserCache.instance.name
            : "User";
        email = UserCache.instance.email;
        imageUrl = UserCache.instance.imageUrl;
        role = UserCache.instance.role;
        phone = extra['phone'] ?? '';
        branch = extra['branch'] ?? '';
        regNo = extra['regNo'] ?? '';
        rollNo = extra['rollNo'] ?? '';
        year = extra['year'] ?? '';
      });
    } catch (e) {
      debugPrint("Profile error: $e");
      setState(() => name = "User");
    }
  }

  Future<void> _loadJobs() async {
    try {
      setState(() => _jobsLoading = true);
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .orderBy('createdAt', descending: true)
          .get();

      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < snap.docs.length; i++) {
        final d = snap.docs[i].data();
        list.add({
          'id': snap.docs[i].id,
          'title': d['title'] ?? '',
          'company': d['company'] ?? '',
          'location': d['location'] ?? '',
          'type': d['type'] ?? 'Full-time',
          'description': d['description'] ?? '',
          'applyLink': d['applyLink'] ?? '',
          'postedBy': d['postedBy'] ?? '',
          'postedByRole': d['postedByRole'] ?? 'admin',
          'color': _jobColors[i % _jobColors.length],
        });
      }
      if (mounted)
        setState(() {
          _jobs = list;
          _jobsLoading = false;
        });
    } catch (e) {
      debugPrint("Jobs error: $e");
      if (mounted) setState(() => _jobsLoading = false);
    }
  }

  void _startRealTimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _studentDocSub = FirebaseFirestore.instance
        .collection('user')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
          if (!mounted || !doc.exists) return;
          final List accepted = doc.data()?['acceptedAlumni'] ?? [];
          setState(
            () => _acceptedConnections = List<Map<String, dynamic>>.from(
              accepted,
            ),
          );
        }, onError: (e) => debugPrint('Student doc stream error: $e'));

    _pendingRequestsSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .where('studentId', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          final pending = snap.docs
              .where((d) => d.data()['status'] == 'pending')
              .map((d) => d.data()['alumniId'] as String)
              .toSet();
          setState(() => _pendingAlumniIds = pending);
        }, onError: (e) => debugPrint('Requests stream error: $e'));
  }

  Future<void> _loadSavedJobs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('user')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        final List saved = doc.data()?['savedJobs'] ?? [];
        setState(() => _savedJobIds = Set<String>.from(saved));
      }
    } catch (e) {
      debugPrint('Load saved jobs error: $e');
    }
  }

  void _showJobDetail(Map<String, dynamic> job) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobDetailPage(
          job: job,
          isSaved: _savedJobIds.contains(job['id']),
          onSave: () => _toggleSaveJob(job['id']),
        ),
      ),
    );
  }

  Future<void> _toggleSaveJob(String jobId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isSaved = _savedJobIds.contains(jobId);
    setState(() {
      if (isSaved) {
        _savedJobIds.remove(jobId);
      } else {
        _savedJobIds.add(jobId);
      }
    });
    try {
      await FirebaseFirestore.instance.collection('user').doc(user.uid).update({
        'savedJobs': isSaved
            ? FieldValue.arrayRemove([jobId])
            : FieldValue.arrayUnion([jobId]),
      });
    } catch (e) {
      setState(() {
        if (isSaved)
          _savedJobIds.add(jobId);
        else
          _savedJobIds.remove(jobId);
      });
      debugPrint('Toggle save error: $e');
    }
  }

  Future<void> _sendConnectRequest(Map<String, dynamic> alumni) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final studentDoc = await FirebaseFirestore.instance
        .collection('user')
        .doc(user.uid)
        .get();
    final studentName = studentDoc.data()?['name'] ?? '';
    final studentEmail = studentDoc.data()?['email'] ?? '';

    try {
      await FirebaseFirestore.instance.collection('connectionRequests').add({
        'studentId': user.uid,
        'studentName': studentName,
        'studentEmail': studentEmail,
        'alumniId': alumni['uid'],
        'alumniName': alumni['name'],
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      setState(() => _pendingAlumniIds.add(alumni['uid']));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Connection request sent to ${alumni['name']}! ✅'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send request: $e')));
    }
  }

  Future<void> loadAlumni() async {
    try {
      setState(() {
        _alumniLoading = true;
        _alumniError = null;
      });
      final snap = await FirebaseFirestore.instance.collection('alumini').get();
      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < snap.docs.length; i++) {
        final d = snap.docs[i].data();
        final n = (d['name'] ?? 'Alumni') as String;
        final parts = n.trim().split(' ');
        final initials = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
        list.add({
          'uid': snap.docs[i].id,
          'name': n,
          'company': d['company'] ?? '',
          'designation': d['designation'] ?? '',
          'batch': d['batch'] ?? '',
          'imageUrl': d['imageUrl'] ?? '',
          'initials': initials,
          'color': _alumniColors[i % _alumniColors.length],
        });
      }
      if (mounted)
        setState(() {
          _alumni = list;
          _alumniLoading = false;
        });
    } catch (e) {
      debugPrint("Alumni error: $e");
      if (mounted)
        setState(() {
          _alumniLoading = false;
          _alumniError = "Could not load alumni data.";
        });
    }
  }

  Future<void> logout() async {
    UserCache.instance.clear();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const loginPage()),
      (_) => false,
    );
  }

  // ── Navigate to Jobs page (from notification bell) ────────────────────────
  void _openJobsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _AllJobsPage(
          jobs: _jobs,
          savedJobIds: _savedJobIds,
          onSave: _toggleSaveJob,
          onTap: _showJobDetail,
        ),
      ),
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProfileBottomSheet(
        name: name,
        email: email,
        imageUrl: imageUrl,
        role: role,
        phone: phone,
        branch: branch,
        regNo: regNo,
        rollNo: rollNo,
        year: year,
        onLogout: () {
          Navigator.pop(context);
          logout();
        },
        onEditProfile: () {
          Navigator.pop(context);
          _openEditProfile();
        },
        onSettings: () {
          Navigator.pop(context);
          _openSettings();
        },
        onAboutUs: () {
          Navigator.pop(context);
          _showAboutUsDialog();
        },
        onHelpSupport: () {
          Navigator.pop(context);
          _showHelpSupportDialog();
        },
      ),
    );
  }

  void _openEditProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _EditProfilePage(
          uid: user.uid,
          initialName: name,
          initialPhone: phone,
          initialBranch: branch,
          initialRegNo: regNo,
          initialRollNo: rollNo,
          initialYear: year,
          onSaved: (updated) {
            setState(() {
              name = updated['name'] ?? name;
              phone = updated['phone'] ?? phone;
              branch = updated['branch'] ?? branch;
              regNo = updated['regNo'] ?? regNo;
              rollNo = updated['rollNo'] ?? rollNo;
              year = updated['year'] ?? year;
            });
          },
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsPage(
          name: name,
          email: email,
          role: role,
          onLogout: logout,
        ),
      ),
    );
  }

  void _showAboutUsDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E90FF).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF1E90FF).withOpacity(0.3),
                        ),
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        color: Color(0xFF1E90FF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'About Us',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text(
                  'Alumni-Student Connect Platform',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E90FF),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'This project is a cross-platform mobile application built using Flutter, designed to streamline communication between alumni and current students of an institution.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'The system enables structured feedback collection, automated email notifications, and centralized data management using Firebase. The application includes authentication for users, an admin dashboard for managing feedback and user interactions, and a Firestore database to store and retrieve data in real time.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Alumni can submit feedback or responses through the app, while students and administrators can view, filter, and manage the submitted information. EmailJS integration is used to automate email communication between users, ensuring quick and reliable message delivery without requiring a dedicated backend server.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'The project focuses on improving engagement between alumni and students, simplifying feedback workflows, and providing a scalable digital communication platform for academic institutions.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 20),
                _InfoChip(
                  icon: Icons.flutter_dash,
                  label: 'Built with Flutter',
                ),
                const SizedBox(height: 8),
                _InfoChip(
                  icon: Icons.cloud_outlined,
                  label: 'Powered by Firebase',
                ),
                const SizedBox(height: 8),
                _InfoChip(
                  icon: Icons.email_outlined,
                  label: 'EmailJS Integration',
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E90FF),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text(
                      'Got it',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showHelpSupportDialog() {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: const Color(0xFF0D1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C9A7).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF00C9A7).withOpacity(0.3),
                      ),
                    ),
                    child: const Icon(
                      Icons.help_outline,
                      color: Color(0xFF00C9A7),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Help & Support',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Need help? Reach out to our developer directly.',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.6),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFF00C9A7).withOpacity(0.25),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Raviteja TSNV',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                          const ClipboardData(text: 'tsnvraviteja@gmail.com'),
                        );
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📋 Email copied to clipboard!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      child: Row(
                        children: [
                          const Text(
                            'tsnvraviteja@gmail.com',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF1E90FF),
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline,
                              decorationColor: Color(0xFF1E90FF),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.copy,
                            size: 14,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E90FF).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1E90FF).withOpacity(0.15),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Color(0xFF1E90FF),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tap the email above to copy it to your clipboard.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.55),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C9A7),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      body: IndexedStack(
        index: _currentTab,
        children: [
          // ── Tab 0: HOME ───────────────────────────────────────
          FadeTransition(
            opacity: _fadeAnim,
            child: CustomScrollView(
              slivers: [
                // ── App Bar ────────────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 130,
                  floating: false,
                  pinned: true,
                  backgroundColor: const Color(0xFF060D1F),
                  automaticallyImplyLeading: false,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF0A1628), Color(0xFF060D1F)],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 52, 20, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  'Good morning 👋',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // ── Notification bell → opens Jobs page ───────
                          GestureDetector(
                            onTap: _openJobsPage,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.1),
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(
                                    Icons.notifications_outlined,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  if (_jobs.isNotEmpty)
                                    Positioned(
                                      right: 7,
                                      top: 7,
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF1E90FF),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _showProfileSheet,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF1E90FF),
                                  width: 2,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 20,
                                backgroundColor: const Color(0xFF1E3A5F),
                                backgroundImage: imageUrl.isNotEmpty
                                    ? NetworkImage(imageUrl)
                                    : null,
                                child: imageUrl.isEmpty
                                    ? Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : 'U',
                                        style: const TextStyle(
                                          color: Color(0xFF1E90FF),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 20),

                        // ── Search Bar ─────────────────────────────────
                        Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              Icon(
                                Icons.search,
                                color: Colors.white.withOpacity(0.35),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: (v) =>
                                      setState(() => _searchQuery = v.trim()),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search jobs, internships...',
                                    hintStyle: TextStyle(
                                      fontSize: 14,
                                      color: Colors.white.withOpacity(0.35),
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 10),
                                    child: Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white.withOpacity(0.4),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 30),

                        // ── Jobs header ────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Latest Jobs'
                                  : 'Results (${_filteredJobs.length})',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            GestureDetector(
                              onTap: _loadJobs,
                              child: const Text(
                                'Refresh',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1E90FF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),

                // ── Job Source Filter ────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _JobFilterChip(
                            label: 'All Jobs',
                            active: _jobTabFilter == 0,
                            onTap: () => setState(() => _jobTabFilter = 0),
                          ),
                          const SizedBox(width: 8),
                          _JobFilterChip(
                            label: 'Admin Jobs',
                            active: _jobTabFilter == 1,
                            onTap: () => setState(() => _jobTabFilter = 1),
                          ),
                          const SizedBox(width: 8),
                          _JobFilterChip(
                            label: 'Alumni Jobs',
                            active: _jobTabFilter == 2,
                            onTap: () => setState(() => _jobTabFilter = 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // ── Jobs List ──────────────────────────────────────────
                _jobsLoading
                    ? SliverToBoxAdapter(
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFF1E90FF),
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                      )
                    : _filteredJobs.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 24,
                            horizontal: 20,
                          ),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(
                                  _searchQuery.isEmpty
                                      ? Icons.work_off_outlined
                                      : Icons.search_off,
                                  color: Colors.white.withOpacity(0.2),
                                  size: 42,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'No jobs posted yet.\nCheck back soon!'
                                      : 'No jobs found for "$_searchQuery"',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.35),
                                    fontSize: 13,
                                    height: 1.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => GestureDetector(
                              onTap: () => _showJobDetail(_filteredJobs[i]),
                              child: _JobCard(
                                job: _filteredJobs[i],
                                isSaved: _savedJobIds.contains(
                                  _filteredJobs[i]['id'],
                                ),
                                onSave: () =>
                                    _toggleSaveJob(_filteredJobs[i]['id']),
                              ),
                            ),
                            childCount: _filteredJobs.length,
                          ),
                        ),
                      ),

                // ── Alumni Section Header ──────────────────────────────
                if (_searchQuery.isEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Alumni Network',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _alumniLoading
                                    ? 'Loading...'
                                    : '${_alumni.length} alumni registered',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF7FA7C9),
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: loadAlumni,
                            child: const Text(
                              'Refresh',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF1E90FF),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Alumni Cards ─────────────────────────────────────
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 190,
                      child: _alumniLoading
                          ? ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                              itemCount: 3,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, __) => _AlumniCardSkeleton(),
                            )
                          : _alumniError != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: Colors.white.withOpacity(0.3),
                                    size: 32,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _alumniError!,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.4),
                                      fontSize: 12,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: loadAlumni,
                                    child: const Text(
                                      'Retry',
                                      style: TextStyle(
                                        color: Color(0xFF1E90FF),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : _alumni.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.people_outline,
                                    color: Colors.white.withOpacity(0.25),
                                    size: 36,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No alumni registered yet.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.35),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                              itemCount: _alumni.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) => _AlumniCard(
                                alumni: _alumni[i],
                                isPending: _pendingAlumniIds.contains(
                                  _alumni[i]['uid'],
                                ),
                                onConnect: () =>
                                    _sendConnectRequest(_alumni[i]),
                              ),
                            ),
                    ),
                  ),

                  // ── My Connections ───────────────────────────────────
                  if (_acceptedConnections.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Connections',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${_acceptedConnections.length} alumni connected',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF7FA7C9),
                                  ),
                                ),
                              ],
                            ),
                            GestureDetector(
                              onTap: () => setState(() {}),
                              child: const Text(
                                'Refresh',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF1E90FF),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => _ConnectionTile(
                            connection: _acceptedConnections[i],
                            parentContext: context,
                          ),
                          childCount: _acceptedConnections.length,
                        ),
                      ),
                    ),
                  ],
                ],

                SliverToBoxAdapter(
                  child: Builder(
                    builder: (ctx) => SizedBox(
                      height: 32 + MediaQuery.of(ctx).padding.bottom,
                    ),
                  ),
                ),
              ],
            ),
          ), // end Tab 0
          // ── Tab 1: EXPLORE ────────────────────────────────────
          _ExploreTab(
            jobs: _jobs,
            alumni: _alumni,
            savedJobIds: _savedJobIds,
            pendingAlumniIds: _pendingAlumniIds,
            onSaveJob: _toggleSaveJob,
            onJobTap: _showJobDetail,
            onConnect: _sendConnectRequest,
          ),

          // ── Tab 2: SAVED JOBS ─────────────────────────────────
          _SavedJobsTab(
            savedJobIds: _savedJobIds,
            allJobs: _jobs,
            onUnsave: _toggleSaveJob,
          ),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _currentTab,
        onTabChanged: (i) => setState(() => _currentTab = i),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALL JOBS PAGE (opened from notification bell)
// ─────────────────────────────────────────────────────────────────────────────
class _AllJobsPage extends StatelessWidget {
  final List<Map<String, dynamic>> jobs;
  final Set<String> savedJobIds;
  final void Function(String) onSave;
  final void Function(Map<String, dynamic>) onTap;

  const _AllJobsPage({
    required this.jobs,
    required this.savedJobIds,
    required this.onSave,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'All Jobs',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: jobs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.work_off_outlined,
                    color: Colors.white.withOpacity(0.2),
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No jobs posted yet.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: jobs.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () => onTap(jobs[i]),
                child: _JobCard(
                  job: jobs[i],
                  isSaved: savedJobIds.contains(jobs[i]['id']),
                  onSave: () => onSave(jobs[i]['id']),
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INFO CHIP (used in About Us dialog)
// ─────────────────────────────────────────────────────────────────────────────
class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF1E90FF)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB CARD
// ─────────────────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool isSaved;
  final VoidCallback onSave;

  const _JobCard({
    required this.job,
    required this.isSaved,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = job['color'] as Color;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.withOpacity(0.3)),
                ),
                child: Icon(Icons.business_center, color: c, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job['title'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      job['company'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onSave,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSaved
                        ? const Color(0xFF1E90FF).withOpacity(0.15)
                        : Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSaved
                          ? const Color(0xFF1E90FF).withOpacity(0.4)
                          : Colors.white.withOpacity(0.1),
                    ),
                  ),
                  child: Icon(
                    isSaved ? Icons.bookmark : Icons.bookmark_outline,
                    color: isSaved
                        ? const Color(0xFF1E90FF)
                        : Colors.white.withOpacity(0.4),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (job['location'].toString().isNotEmpty) ...[
                Icon(
                  Icons.location_on_outlined,
                  size: 12,
                  color: Colors.white.withOpacity(0.4),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    job['location'],
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  job['type'],
                  style: TextStyle(
                    fontSize: 10,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (job['postedByRole'].toString().toLowerCase() == 'alumni') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00C9A7).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Text(
                    'Alumni Referral',
                    style: TextStyle(
                      fontSize: 9,
                      color: Color(0xFF00C9A7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (job['applyLink'] != null &&
              job['applyLink'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final rawUrl = job['applyLink'].toString().trim();
                final url = rawUrl.startsWith('http')
                    ? rawUrl
                    : 'https://$rawUrl';
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.open_in_new, size: 12, color: Color(0xFF1E90FF)),
                  SizedBox(width: 4),
                  Text(
                    'Apply Now',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1E90FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ALUMNI CARD
// ─────────────────────────────────────────────────────────────────────────────
class _AlumniCard extends StatelessWidget {
  final Map<String, dynamic> alumni;
  final bool isPending;
  final VoidCallback onConnect;

  const _AlumniCard({
    required this.alumni,
    required this.isPending,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = alumni['color'] as Color;
    final String imageUrl = alumni['imageUrl'] ?? '';
    final String company = alumni['company'] ?? '';
    final String designation = alumni['designation'] ?? '';
    final String batch = alumni['batch'] ?? '';
    final String subtitle = (designation.isNotEmpty && company.isNotEmpty)
        ? '$designation @ $company'
        : designation.isNotEmpty
        ? designation
        : company.isNotEmpty
        ? company
        : 'Alumni';

    return Container(
      width: 162,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withOpacity(0.15),
              border: Border.all(color: c.withOpacity(0.4), width: 1.5),
            ),
            child: imageUrl.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Text(
                          alumni['initials'],
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c,
                          ),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Text(
                      alumni['initials'],
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: c,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            alumni['name'],
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.5),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          if (batch.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                batch,
                style: TextStyle(
                  fontSize: 9,
                  color: c,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: isPending ? null : onConnect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: isPending
                    ? Colors.white.withOpacity(0.06)
                    : c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isPending
                      ? Colors.white.withOpacity(0.12)
                      : c.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isPending ? Icons.hourglass_top : Icons.person_add_outlined,
                    size: 12,
                    color: isPending ? Colors.white.withOpacity(0.35) : c,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isPending ? 'Pending' : 'Connect',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPending ? Colors.white.withOpacity(0.35) : c,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────
class _AlumniCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 148,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(0.07)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _s(52, 52, circular: true),
        const SizedBox(height: 10),
        _s(80, 10),
        const SizedBox(height: 6),
        _s(100, 8),
        const SizedBox(height: 4),
        _s(60, 8),
        const SizedBox(height: 8),
        _s(50, 16, radius: 6),
      ],
    ),
  );

  Widget _s(double w, double h, {bool circular = false, double radius = 4}) =>
      Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: circular
              ? BorderRadius.circular(w)
              : BorderRadius.circular(radius),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileBottomSheet extends StatelessWidget {
  final String name, email, imageUrl, role;
  final String phone, branch, regNo, rollNo, year;
  final VoidCallback onLogout;
  final VoidCallback onEditProfile;
  final VoidCallback onSettings;
  final VoidCallback onAboutUs;
  final VoidCallback onHelpSupport;

  const _ProfileBottomSheet({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.role,
    required this.phone,
    required this.branch,
    required this.regNo,
    required this.rollNo,
    required this.year,
    required this.onLogout,
    required this.onEditProfile,
    required this.onSettings,
    required this.onAboutUs,
    required this.onHelpSupport,
  });

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF0D1B2E),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF1E90FF), width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1E90FF).withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 38,
              backgroundColor: const Color(0xFF1E3A5F),
              backgroundImage: imageUrl.isNotEmpty
                  ? NetworkImage(imageUrl)
                  : null,
              child: imageUrl.isEmpty
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : 'U',
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E90FF),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1E90FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFF1E90FF).withOpacity(0.3),
              ),
            ),
            child: Text(
              role,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1E90FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // ── Mini info pills ──────────────────────────────────
          if (branch.isNotEmpty || year.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                if (branch.isNotEmpty)
                  _InfoPill(icon: Icons.school_outlined, label: branch),
                if (year.isNotEmpty)
                  _InfoPill(icon: Icons.calendar_today_outlined, label: year),
                if (rollNo.isNotEmpty)
                  _InfoPill(icon: Icons.badge_outlined, label: 'Roll: $rollNo'),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 8),
          _MenuItem(
            icon: Icons.person_outline,
            label: 'Edit Profile',
            onTap: onEditProfile,
          ),
          _MenuItem(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: onSettings,
          ),
          _MenuItem(
            icon: Icons.info_outline,
            label: 'About Us',
            onTap: onAboutUs,
          ),
          _MenuItem(
            icon: Icons.help_outline,
            label: 'Help & Support',
            onTap: onHelpSupport,
          ),
          const SizedBox(height: 8),
          Divider(color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text(
                'Logout',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B5C).withOpacity(0.15),
                foregroundColor: const Color(0xFFFF3B5C),
                elevation: 0,
                side: const BorderSide(color: Color(0xFFFF3B5C), width: 1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ── Small pill chip for profile sheet ────────────────────────────────────────
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white.withOpacity(0.45)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.65),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    contentPadding: EdgeInsets.zero,
    leading: Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 18),
    ),
    title: Text(
      label,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: Colors.white.withOpacity(0.3),
      size: 18,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EDIT PROFILE PAGE
// ─────────────────────────────────────────────────────────────────────────────
class _EditProfilePage extends StatefulWidget {
  final String uid;
  final String initialName, initialPhone, initialBranch;
  final String initialRegNo, initialRollNo, initialYear;
  final void Function(Map<String, String>) onSaved;

  const _EditProfilePage({
    required this.uid,
    required this.initialName,
    required this.initialPhone,
    required this.initialBranch,
    required this.initialRegNo,
    required this.initialRollNo,
    required this.initialYear,
    required this.onSaved,
  });

  @override
  State<_EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<_EditProfilePage> {
  late TextEditingController _nameCtr;
  late TextEditingController _phoneCtr;
  late TextEditingController _branchCtr;
  late TextEditingController _regNoCtr;
  late TextEditingController _rollNoCtr;
  late TextEditingController _yearCtr;

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtr = TextEditingController(text: widget.initialName);
    _phoneCtr = TextEditingController(text: widget.initialPhone);
    _branchCtr = TextEditingController(text: widget.initialBranch);
    _regNoCtr = TextEditingController(text: widget.initialRegNo);
    _rollNoCtr = TextEditingController(text: widget.initialRollNo);
    _yearCtr = TextEditingController(text: widget.initialYear);
  }

  @override
  void dispose() {
    _nameCtr.dispose();
    _phoneCtr.dispose();
    _branchCtr.dispose();
    _regNoCtr.dispose();
    _rollNoCtr.dispose();
    _yearCtr.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtr.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    try {
      final data = {
        'name': name,
        'phone': _phoneCtr.text.trim(),
        'branch': _branchCtr.text.trim(),
        'regNo': _regNoCtr.text.trim(),
        'rollNo': _rollNoCtr.text.trim(),
        'year': _yearCtr.text.trim(),
      };
      await FirebaseFirestore.instance
          .collection('user')
          .doc(widget.uid)
          .update(data);
      widget.onSaved(data);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Profile updated successfully!'),
          backgroundColor: Color(0xFF00C9A7),
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF1E90FF),
                    ),
                  )
                : GestureDetector(
                    onTap: _save,
                    child: const Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E90FF),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar placeholder ─────────────────────────────────
            Center(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1E90FF),
                        width: 2.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF1E90FF).withOpacity(0.25),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: const Color(0xFF1E3A5F),
                      child: Text(
                        _nameCtr.text.isNotEmpty
                            ? _nameCtr.text[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E90FF),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF060D1F),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // ── Section: Personal Info ─────────────────────────────
            _SectionLabel(label: 'Personal Information'),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _nameCtr,
              label: 'Full Name',
              icon: Icons.person_outline,
              hint: 'Enter your full name',
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _phoneCtr,
              label: 'Phone Number',
              icon: Icons.phone_outlined,
              hint: 'Enter your phone number',
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 24),

            // ── Section: Academic Info ─────────────────────────────
            _SectionLabel(label: 'Academic Information'),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _branchCtr,
              label: 'Branch',
              icon: Icons.school_outlined,
              hint: 'e.g. CSE, ECE, MECH',
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _yearCtr,
              label: 'Year / Batch',
              icon: Icons.calendar_today_outlined,
              hint: 'e.g. 2024-2028',
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _regNoCtr,
              label: 'Registration Number',
              icon: Icons.numbers_outlined,
              hint: 'Enter your reg. number',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _ProfileField(
              controller: _rollNoCtr,
              label: 'Roll Number',
              icon: Icons.badge_outlined,
              hint: 'Enter your roll number',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 32),

            // ── Save Button ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E90FF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: const Color(
                    0xFF1E90FF,
                  ).withOpacity(0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Section label helper ──────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E90FF),
          letterSpacing: 0.5,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Container(
          height: 1,
          color: const Color(0xFF1E90FF).withOpacity(0.2),
        ),
      ),
    ],
  );
}

// ── Profile text field ────────────────────────────────────────────────────────
class _ProfileField extends StatelessWidget {
  final TextEditingController controller;
  final String label, hint;
  final IconData icon;
  final TextInputType keyboardType;

  const _ProfileField({
    required this.controller,
    required this.label,
    required this.icon,
    required this.hint,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white.withOpacity(0.5),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.25),
              ),
              prefixIcon: Icon(
                icon,
                size: 18,
                color: Colors.white.withOpacity(0.4),
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class _SettingsPage extends StatefulWidget {
  final String name, email, role;
  final VoidCallback onLogout;

  const _SettingsPage({
    required this.name,
    required this.email,
    required this.role,
    required this.onLogout,
  });

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool _notificationsEnabled = true;
  bool _jobAlerts = true;
  bool _connectionAlerts = true;
  bool _emailNotifications = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF060D1F),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account Info Card ──────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF1E90FF).withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1E90FF).withOpacity(0.15),
                      border: Border.all(
                        color: const Color(0xFF1E90FF).withOpacity(0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        widget.name.isNotEmpty
                            ? widget.name[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E90FF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.45),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E90FF).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            widget.role,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF1E90FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── Notifications ──────────────────────────────────────
            _SectionLabel(label: 'Notifications'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _ToggleTile(
                  icon: Icons.notifications_outlined,
                  iconColor: const Color(0xFF1E90FF),
                  title: 'Push Notifications',
                  subtitle: 'Receive in-app notifications',
                  value: _notificationsEnabled,
                  onChanged: (v) => setState(() => _notificationsEnabled = v),
                ),
                _Divider(),
                _ToggleTile(
                  icon: Icons.work_outline,
                  iconColor: const Color(0xFF00C9A7),
                  title: 'Job Alerts',
                  subtitle: 'New job postings in your feed',
                  value: _jobAlerts,
                  onChanged: (v) => setState(() => _jobAlerts = v),
                ),
                _Divider(),
                _ToggleTile(
                  icon: Icons.people_outline,
                  iconColor: const Color(0xFFFFA940),
                  title: 'Connection Alerts',
                  subtitle: 'Alumni accepted your request',
                  value: _connectionAlerts,
                  onChanged: (v) => setState(() => _connectionAlerts = v),
                ),
                _Divider(),
                _ToggleTile(
                  icon: Icons.email_outlined,
                  iconColor: const Color(0xFFA78BFA),
                  title: 'Email Notifications',
                  subtitle: 'Receive updates via email',
                  value: _emailNotifications,
                  onChanged: (v) => setState(() => _emailNotifications = v),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Account ────────────────────────────────────────────
            _SectionLabel(label: 'Account'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _TapTile(
                  icon: Icons.lock_outline,
                  iconColor: const Color(0xFF1E90FF),
                  title: 'Change Password',
                  subtitle: 'Update your account password',
                  onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password change coming soon'),
                    ),
                  ),
                ),
                _Divider(),
                _TapTile(
                  icon: Icons.privacy_tip_outlined,
                  iconColor: const Color(0xFF00C9A7),
                  title: 'Privacy Policy',
                  subtitle: 'Read our privacy policy',
                  onTap: () {},
                ),
                _Divider(),
                _TapTile(
                  icon: Icons.description_outlined,
                  iconColor: const Color(0xFFFFA940),
                  title: 'Terms of Service',
                  subtitle: 'Read our terms of service',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── App Info ───────────────────────────────────────────
            _SectionLabel(label: 'App'),
            const SizedBox(height: 12),
            _SettingsCard(
              children: [
                _TapTile(
                  icon: Icons.info_outline,
                  iconColor: const Color(0xFFA78BFA),
                  title: 'App Version',
                  subtitle: 'v1.0.0',
                  onTap: null,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C9A7).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Latest',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF00C9A7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Danger Zone ────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  widget.onLogout();
                },
                icon: const Icon(Icons.logout, size: 18),
                label: const Text(
                  'Logout',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B5C).withOpacity(0.12),
                  foregroundColor: const Color(0xFFFF3B5C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFFFF3B5C), width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ── Settings helpers ──────────────────────────────────────────────────────────
class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white.withOpacity(0.09)),
    ),
    child: Column(children: children),
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    thickness: 1,
    indent: 56,
    endIndent: 16,
    color: Colors.white.withOpacity(0.07),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: const Color(0xFF1E90FF),
          activeTrackColor: const Color(0xFF1E90FF).withOpacity(0.3),
          inactiveThumbColor: Colors.white.withOpacity(0.4),
          inactiveTrackColor: Colors.white.withOpacity(0.1),
        ),
      ],
    ),
  );
}

class _TapTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _TapTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
          trailing ??
              Icon(
                Icons.chevron_right,
                size: 18,
                color: Colors.white.withOpacity(0.25),
              ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTION TILE
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectionTile extends StatelessWidget {
  final Map<String, dynamic> connection;
  final BuildContext parentContext;
  const _ConnectionTile({
    required this.connection,
    required this.parentContext,
  });

  @override
  Widget build(BuildContext context) {
    final String alumniName = connection['alumniName'] ?? 'Alumni';
    final String alumniEmail = connection['alumniEmail'] ?? '';
    final String alumniId = connection['alumniId'] ?? '';
    final parts = alumniName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : alumniName.substring(0, alumniName.length >= 2 ? 2 : 1).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF00C9A7).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00C9A7).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00C9A7).withOpacity(0.15),
              border: Border.all(
                color: const Color(0xFF00C9A7).withOpacity(0.4),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00C9A7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        alumniName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00C9A7).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'Connected ✓',
                        style: TextStyle(
                          fontSize: 9,
                          color: Color(0xFF00C9A7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: () {
                    if (alumniEmail.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: alumniEmail));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('📋 Copied: $alumniEmail'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  child: Row(
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        size: 13,
                        color: Color(0xFF1E90FF),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          alumniEmail.isNotEmpty
                              ? alumniEmail
                              : 'Email not available',
                          style: TextStyle(
                            fontSize: 12,
                            color: alumniEmail.isNotEmpty
                                ? const Color(0xFF1E90FF)
                                : Colors.white.withOpacity(0.35),
                            decoration: alumniEmail.isNotEmpty
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: const Color(0xFF1E90FF),
                          ),
                        ),
                      ),
                      if (alumniEmail.isNotEmpty) ...[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.copy,
                          size: 11,
                          color: Color(0xFF1E90FF),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Chat button ────────────────────────────────────────
          if (alumniId.isNotEmpty)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  parentContext,
                  MaterialPageRoute(
                    builder: (_) =>
                        ChatPage(peerId: alumniId, peerName: alumniName),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E90FF).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF1E90FF).withOpacity(0.3),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPLORE TAB — full search for jobs + alumni
// ─────────────────────────────────────────────────────────────────────────────
class _ExploreTab extends StatefulWidget {
  final List<Map<String, dynamic>> jobs;
  final List<Map<String, dynamic>> alumni;
  final Set<String> savedJobIds;
  final Set<String> pendingAlumniIds;
  final void Function(String) onSaveJob;
  final void Function(Map<String, dynamic>) onJobTap;
  final void Function(Map<String, dynamic>) onConnect;

  const _ExploreTab({
    required this.jobs,
    required this.alumni,
    required this.savedJobIds,
    required this.pendingAlumniIds,
    required this.onSaveJob,
    required this.onJobTap,
    required this.onConnect,
  });

  @override
  State<_ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends State<_ExploreTab> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';
  // 0=All, 1=Jobs, 2=Alumni
  int _filter = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredJobs {
    if (_query.isEmpty) return widget.jobs;
    final q = _query.toLowerCase();
    return widget.jobs.where((j) {
      return (j['title'] as String).toLowerCase().contains(q) ||
          (j['company'] as String).toLowerCase().contains(q) ||
          (j['location'] as String).toLowerCase().contains(q) ||
          (j['type'] as String).toLowerCase().contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredAlumni {
    if (_query.isEmpty) return widget.alumni;
    final q = _query.toLowerCase();
    return widget.alumni.where((a) {
      return (a['name'] as String).toLowerCase().contains(q) ||
          (a['company'] as String).toLowerCase().contains(q) ||
          (a['designation'] as String).toLowerCase().contains(q) ||
          (a['batch'] as String).toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final showJobs = _filter == 0 || _filter == 1;
    final showAlumni = _filter == 0 || _filter == 2;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Search jobs and alumni',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withOpacity(0.4),
                  ),
                ),
                const SizedBox(height: 16),
                // ── Search Bar ────────────────────────────────────
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.12)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.35),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _ctrl,
                          autofocus: false,
                          onChanged: (v) => setState(() => _query = v.trim()),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search jobs, companies, alumni...',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.3),
                            ),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _ctrl.clear();
                            setState(() => _query = '');
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white.withOpacity(0.4),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Filter Chips ─────────────────────────────────
                Row(
                  children: [
                    _FilterChip(
                      label: 'All',
                      active: _filter == 0,
                      onTap: () => setState(() => _filter = 0),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Jobs',
                      active: _filter == 1,
                      onTap: () => setState(() => _filter = 1),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'Alumni',
                      active: _filter == 2,
                      onTap: () => setState(() => _filter = 2),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Results ───────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                if (showJobs) ...[
                  if (_filter == 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Jobs (${_filteredJobs.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (_filteredJobs.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No jobs available'
                              : 'No jobs found for "$_query"',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._filteredJobs.map(
                      (job) => GestureDetector(
                        onTap: () => widget.onJobTap(job),
                        child: _JobCard(
                          job: job,
                          isSaved: widget.savedJobIds.contains(job['id']),
                          onSave: () => widget.onSaveJob(job['id']),
                        ),
                      ),
                    ),
                ],
                if (showAlumni) ...[
                  if (_filter == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 10),
                      child: Text(
                        'Alumni (${_filteredAlumni.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  if (_filteredAlumni.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Text(
                          _query.isEmpty
                              ? 'No alumni available'
                              : 'No alumni found for "$_query"',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                      ),
                    )
                  else
                    ..._filteredAlumni.map(
                      (a) => _AlumniListTile(
                        alumni: a,
                        isPending: widget.pendingAlumniIds.contains(a['uid']),
                        onConnect: () => widget.onConnect(a),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter Chip ───────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? const Color(0xFF1E90FF)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF1E90FF)
                : Colors.white.withOpacity(0.12),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : Colors.white.withOpacity(0.5),
          ),
        ),
      ),
    );
  }
}

// ── Alumni List Tile (for Explore tab) ────────────────────────────────────────
class _AlumniListTile extends StatelessWidget {
  final Map<String, dynamic> alumni;
  final bool isPending;
  final VoidCallback onConnect;
  const _AlumniListTile({
    required this.alumni,
    required this.isPending,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = alumni['color'] as Color;
    final String company = alumni['company'] ?? '';
    final String designation = alumni['designation'] ?? '';
    final String batch = alumni['batch'] ?? '';
    final String subtitle = (designation.isNotEmpty && company.isNotEmpty)
        ? '$designation @ $company'
        : designation.isNotEmpty
        ? designation
        : company.isNotEmpty
        ? company
        : 'Alumni';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withOpacity(0.15),
              border: Border.all(color: c.withOpacity(0.4), width: 1.5),
            ),
            child: Center(
              child: Text(
                alumni['initials'],
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alumni['name'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                if (batch.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: c.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      batch,
                      style: TextStyle(
                        fontSize: 9,
                        color: c,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          GestureDetector(
            onTap: isPending ? null : onConnect,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: isPending
                    ? Colors.white.withOpacity(0.06)
                    : c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isPending
                      ? Colors.white.withOpacity(0.12)
                      : c.withOpacity(0.4),
                ),
              ),
              child: Text(
                isPending ? 'Pending' : 'Connect',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isPending ? Colors.white.withOpacity(0.35) : c,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVED JOBS TAB
// ─────────────────────────────────────────────────────────────────────────────
class _SavedJobsTab extends StatelessWidget {
  final Set<String> savedJobIds;
  final List<Map<String, dynamic>> allJobs;
  final void Function(String jobId) onUnsave;

  const _SavedJobsTab({
    required this.savedJobIds,
    required this.allJobs,
    required this.onUnsave,
  });

  @override
  Widget build(BuildContext context) {
    final savedJobs = allJobs
        .where((j) => savedJobIds.contains(j['id']))
        .toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saved Jobs',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${savedJobs.length} job${savedJobs.length == 1 ? '' : 's'} saved',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7FA7C9),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: savedJobs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.bookmark_outline,
                          size: 52,
                          color: Colors.white.withOpacity(0.15),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'No saved jobs yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Tap the bookmark icon on any job to save it',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    itemCount: savedJobs.length,
                    itemBuilder: (_, i) => _SavedJobCard(
                      job: savedJobs[i],
                      onUnsave: () => onUnsave(savedJobs[i]['id']),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVED JOB CARD
// ─────────────────────────────────────────────────────────────────────────────
class _SavedJobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onUnsave;
  const _SavedJobCard({required this.job, required this.onUnsave});

  @override
  Widget build(BuildContext context) {
    final Color c = job['color'] as Color;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E90FF).withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: c.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: c.withOpacity(0.3)),
                ),
                child: Icon(Icons.business_center, color: c, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job['title'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      job['company'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onUnsave,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E90FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF1E90FF).withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.bookmark,
                    color: Color(0xFF1E90FF),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (job['location'].toString().isNotEmpty) ...[
                Icon(
                  Icons.location_on_outlined,
                  size: 12,
                  color: Colors.white.withOpacity(0.4),
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    job['location'],
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: c.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  job['type'],
                  style: TextStyle(
                    fontSize: 10,
                    color: c,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (job['applyLink'] != null &&
              job['applyLink'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final rawUrl = job['applyLink'].toString().trim();
                final url = rawUrl.startsWith('http')
                    ? rawUrl
                    : 'https://$rawUrl';
                final uri = Uri.parse(url);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.open_in_new, size: 12, color: Color(0xFF1E90FF)),
                  SizedBox(width: 4),
                  Text(
                    'Apply Now',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF1E90FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB FILTER CHIP (Admin / Alumni / All tabs)
// ─────────────────────────────────────────────────────────────────────────────
class _JobFilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _JobFilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF1E90FF) : const Color(0xFF0D1B2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? const Color(0xFF1E90FF)
                : Colors.white.withOpacity(0.15),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  const _BottomNav({required this.currentIndex, required this.onTabChanged});

  static const _items = [
    {'icon': Icons.home_outlined, 'active': Icons.home, 'label': 'Home'},
    {'icon': Icons.search, 'active': Icons.search, 'label': 'Explore'},
    {
      'icon': Icons.bookmark_outline,
      'active': Icons.bookmark,
      'label': 'Saved',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF0D1B2E),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.07)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(_items.length, (i) {
            final active = currentIndex == i;
            return GestureDetector(
              onTap: () => onTabChanged(i),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 64,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      active
                          ? _items[i]['active'] as IconData
                          : _items[i]['icon'] as IconData,
                      color: active
                          ? const Color(0xFF1E90FF)
                          : Colors.white.withOpacity(0.35),
                      size: 22,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _items[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? const Color(0xFF1E90FF)
                            : Colors.white.withOpacity(0.35),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
