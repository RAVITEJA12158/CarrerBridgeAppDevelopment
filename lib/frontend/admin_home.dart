import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});
  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage>
    with TickerProviderStateMixin {
  // ── Admin profile ─────────────────────────────────────────────────────────
  String name = "Loading...";
  String email = "";
  String department = "";
  String imageUrl = "";

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;
  late TabController _tabController;

  // ── Stats ─────────────────────────────────────────────────────────────────
  int _totalStudents = 0;
  int _totalAlumni = 0;
  int _totalAdmins = 0;
  bool _statsLoading = true;

  // ── Users ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _allUsers = [];
  bool _usersLoading = true;
  String _filterRole = 'All';

  // ── Jobs ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _jobs = [];
  bool _jobsLoading = true;

  // ── Post Job form controllers ─────────────────────────────────────────────
  final _jobTitleCtrl = TextEditingController();
  final _jobCompanyCtrl = TextEditingController();
  final _jobLocationCtrl = TextEditingController();
  final _jobTypeCtrl = TextEditingController();
  final _jobDescCtrl = TextEditingController();
  final _jobLinkCtrl = TextEditingController();
  String _jobTypeSelected = 'Internship';

  final List<Color> _colors = [
    Color(0xFFFF6B35),
    Color(0xFFFFA940),
    Color(0xFF1E90FF),
    Color(0xFF00C9A7),
    Color(0xFFA78BFA),
    Color(0xFFFF6B8A),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadAdminProfile();
    _loadStats();
    _loadAllUsers();
    _loadJobs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fadeController.dispose();
    _jobTitleCtrl.dispose();
    _jobCompanyCtrl.dispose();
    _jobLocationCtrl.dispose();
    _jobTypeCtrl.dispose();
    _jobDescCtrl.dispose();
    _jobLinkCtrl.dispose();
    super.dispose();
  }

  // ── Loaders ───────────────────────────────────────────────────────────────

  Future<void> _loadAdminProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('admin')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          name = doc.data()?['name'] ?? 'Admin';
          email = user.email ?? '';
          department = doc.data()?['department'] ?? '';
          imageUrl = doc.data()?['imageUrl'] ?? '';
        });
      }
    } catch (e) {
      debugPrint('Admin profile error: $e');
    }
  }

  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('user').get(),
        FirebaseFirestore.instance.collection('alumini').get(),
        FirebaseFirestore.instance.collection('admin').get(),
      ]);
      if (mounted)
        setState(() {
          _totalStudents = results[0].docs.length;
          _totalAlumni = results[1].docs.length;
          _totalAdmins = results[2].docs.length;
          _statsLoading = false;
        });
    } catch (e) {
      debugPrint('Stats error: $e');
      if (mounted) setState(() => _statsLoading = false);
    }
  }

  Future<void> _loadAllUsers() async {
    try {
      setState(() => _usersLoading = true);
      List<QuerySnapshot> snaps = [];
      if (_filterRole == 'All') {
        snaps = await Future.wait([
          FirebaseFirestore.instance.collection('user').get(),
          FirebaseFirestore.instance.collection('alumini').get(),
          FirebaseFirestore.instance.collection('admin').get(),
        ]);
      } else if (_filterRole == 'student') {
        snaps = [await FirebaseFirestore.instance.collection('user').get()];
      } else if (_filterRole == 'alumni') {
        snaps = [await FirebaseFirestore.instance.collection('alumini').get()];
      } else {
        snaps = [await FirebaseFirestore.instance.collection('admin').get()];
      }
      final allDocs = snaps.expand((s) => s.docs).toList();
      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < allDocs.length; i++) {
        final d = allDocs[i].data() as Map<String, dynamic>;
        final n = (d['name'] ?? 'User') as String;
        final parts = n.trim().split(' ');
        final initials = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
        list.add({
          'uid': allDocs[i].id,
          'name': n,
          'email': d['email'] ?? '',
          'phone': d['phone'] ?? '',
          'role': d['role'] ?? 'student',
          'branch': d['branch'] ?? '',
          'year': d['year'] ?? '',
          'company': d['company'] ?? '',
          'batch': d['batch'] ?? '',
          'rollNo': d['rollNo'] ?? '',
          'regNo': d['regNo'] ?? '',
          'initials': initials,
          'color': _colors[i % _colors.length],
        });
      }
      if (mounted)
        setState(() {
          _allUsers = list;
          _usersLoading = false;
        });
    } catch (e) {
      debugPrint('Users error: $e');
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  Future<void> _loadJobs() async {
    try {
      setState(() => _jobsLoading = true);
      final snap = await FirebaseFirestore.instance
          .collection('jobs')
          .orderBy('createdAt', descending: true)
          .get();
      final list = snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      if (mounted)
        setState(() {
          _jobs = list;
          _jobsLoading = false;
        });
    } catch (e) {
      debugPrint('Jobs error: $e');
      if (mounted) setState(() => _jobsLoading = false);
    }
  }

  // ── Delete user ───────────────────────────────────────────────────────────
  Future<void> _deleteUser(String uid, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete User',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Are you sure you want to delete "$userName"?\nThis cannot be undone.',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF7FA7C9)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final roleVal =
          _allUsers.firstWhere(
            (u) => u['uid'] == uid,
            orElse: () => {},
          )['role'] ??
          'student';
      final delCollection = roleVal == 'alumni'
          ? 'alumini'
          : roleVal == 'admin'
          ? 'admin'
          : 'user';
      await FirebaseFirestore.instance
          .collection(delCollection)
          .doc(uid)
          .delete();
      _showSnack('User "$userName" deleted successfully.');
      _loadStats();
      _loadAllUsers();
    } catch (e) {
      _showSnack('Failed to delete user: $e');
    }
  }

  // ── Delete job ────────────────────────────────────────────────────────────
  Future<void> _deleteJob(String jobId, String jobTitle) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF0D1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Delete Job',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Delete "$jobTitle"?',
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Color(0xFF7FA7C9)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF3B5C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection('jobs').doc(jobId).delete();
      _showSnack('Job deleted.');
      _loadJobs();
    } catch (e) {
      _showSnack('Failed: $e');
    }
  }

  // ── Post job ──────────────────────────────────────────────────────────────
  void _showPostJobSheet() {
    _jobTitleCtrl.clear();
    _jobCompanyCtrl.clear();
    _jobLocationCtrl.clear();
    _jobDescCtrl.clear();
    _jobLinkCtrl.clear();
    _jobTypeSelected = 'Internship';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFF0D1B2E),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Post a Job / Internship',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: ['Internship', 'Full-time', 'Part-time']
                        .map(
                          (t) => GestureDetector(
                            onTap: () =>
                                setSheetState(() => _jobTypeSelected = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _jobTypeSelected == t
                                    ? const Color(0xFFFF6B35)
                                    : Colors.white.withOpacity(0.07),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _jobTypeSelected == t
                                      ? const Color(0xFFFF6B35)
                                      : Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _jobTypeSelected == t
                                      ? Colors.white
                                      : Colors.white.withOpacity(0.6),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(_jobTitleCtrl, 'Job Title', Icons.work_outline),
                  const SizedBox(height: 12),
                  _sheetField(
                    _jobCompanyCtrl,
                    'Company',
                    Icons.business_outlined,
                  ),
                  const SizedBox(height: 12),
                  _sheetField(
                    _jobLocationCtrl,
                    'Location',
                    Icons.location_on_outlined,
                  ),
                  const SizedBox(height: 12),
                  _sheetField(
                    _jobDescCtrl,
                    'Description',
                    Icons.description_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  _sheetField(_jobLinkCtrl, 'Apply Link', Icons.link_outlined),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (_jobTitleCtrl.text.trim().isEmpty ||
                            _jobCompanyCtrl.text.trim().isEmpty) {
                          _showSnack('Title and Company are required.');
                          return;
                        }
                        try {
                          await FirebaseFirestore.instance
                              .collection('jobs')
                              .add({
                                'title': _jobTitleCtrl.text.trim(),
                                'company': _jobCompanyCtrl.text.trim(),
                                'location': _jobLocationCtrl.text.trim(),
                                'type': _jobTypeSelected,
                                'description': _jobDescCtrl.text.trim(),
                                'applyLink': _jobLinkCtrl.text.trim(),
                                'postedBy':
                                    FirebaseAuth.instance.currentUser?.uid ??
                                    '',
                                'createdAt': FieldValue.serverTimestamp(),
                              });
                          if (!mounted) return;
                          Navigator.pop(context);
                          _showSnack('Job posted successfully! ✅');
                          _loadJobs();
                        } catch (e) {
                          _showSnack('Failed to post: $e');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B35),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Post Job',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── View user detail ──────────────────────────────────────────────────────
  void _showUserDetail(Map<String, dynamic> user) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D1B2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
            const SizedBox(height: 20),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (user['color'] as Color).withOpacity(0.15),
                border: Border.all(
                  color: (user['color'] as Color).withOpacity(0.4),
                  width: 2,
                ),
              ),
              child: Center(
                child: Text(
                  user['initials'],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: user['color'],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              user['name'],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _roleColor(user['role']).withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _roleColor(user['role']).withOpacity(0.3),
                ),
              ),
              child: Text(
                user['role'],
                style: TextStyle(
                  fontSize: 12,
                  color: _roleColor(user['role']),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: Colors.white.withOpacity(0.1)),
            const SizedBox(height: 8),
            _detailRow(Icons.email_outlined, user['email']),
            if (user['phone'].toString().isNotEmpty)
              _detailRow(Icons.phone_outlined, user['phone']),
            if (user['branch'].toString().isNotEmpty)
              _detailRow(Icons.school_outlined, user['branch']),
            if (user['year'].toString().isNotEmpty)
              _detailRow(
                Icons.calendar_today_outlined,
                'Year: ${user['year']}',
              ),
            if (user['rollNo'].toString().isNotEmpty)
              _detailRow(Icons.tag, 'Roll: ${user['rollNo']}'),
            if (user['regNo'].toString().isNotEmpty)
              _detailRow(Icons.badge_outlined, 'Reg: ${user['regNo']}'),
            if (user['company'].toString().isNotEmpty)
              _detailRow(Icons.business_outlined, user['company']),
            if (user['batch'].toString().isNotEmpty)
              _detailRow(Icons.people_outline, 'Batch: ${user['batch']}'),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _deleteUser(user['uid'], user['name']);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text(
                  'Delete User',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF3B5C).withOpacity(0.12),
                  foregroundColor: const Color(0xFFFF3B5C),
                  elevation: 0,
                  side: const BorderSide(color: Color(0xFFFF3B5C), width: 1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return const Color(0xFFFF6B35);
      case 'alumni':
        return const Color(0xFF00C9A7);
      default:
        return const Color(0xFF1E90FF);
    }
  }

  String get _initials {
    final parts = name.trim().split(' ');
    return parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _sheetField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    int maxLines = 1,
  }) => TextField(
    controller: ctrl,
    maxLines: maxLines,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFFFF6B35), size: 19),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF6B35), width: 1.5),
      ),
    ),
  );

  Widget _detailRow(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFFF6B35)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback onTap) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: IconButton(
      icon: Icon(icon, color: Colors.white, size: 20),
      onPressed: onTap,
      padding: EdgeInsets.zero,
    ),
  );

  // ✅ FIXED: Added missing _actionTile method
  Widget _actionTile(
    IconData icon,
    String label,
    Color color, {
    required VoidCallback onTap,
  }) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const loginPage()),
      (_) => false,
    );
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AdminProfileSheet(
        name: name,
        email: email,
        imageUrl: imageUrl,
        department: department,
        onLogout: () {
          Navigator.pop(context);
          _logout();
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: NestedScrollView(
          headerSliverBuilder: (_, __) => [
            SliverAppBar(
              expandedHeight: 150,
              pinned: true,
              floating: false,
              automaticallyImplyLeading: false,
              backgroundColor: const Color(0xFF060D1F),
              bottom: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFFFF6B35),
                indicatorWeight: 2.5,
                labelColor: const Color(0xFFFF6B35),
                unselectedLabelColor: Colors.white.withOpacity(0.4),
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: 'Dashboard'),
                  Tab(text: 'Users'),
                  Tab(text: 'Jobs'),
                ],
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF2A1200), Color(0xFF060D1F)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 52, 20, 48),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Dashboard 🛡️',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                            if (department.isNotEmpty)
                              Text(
                                department,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFFFF6B35),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _iconBtn(Icons.notifications_outlined, () {}),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: _showProfileSheet,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFFF6B35),
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF2A1200),
                            backgroundImage: imageUrl.isNotEmpty
                                ? NetworkImage(imageUrl)
                                : null,
                            child: imageUrl.isEmpty
                                ? Text(
                                    _initials,
                                    style: const TextStyle(
                                      color: Color(0xFFFF6B35),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
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
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              // ── TAB 1 — DASHBOARD ────────────────────────────────
              SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _statsLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B35),
                              strokeWidth: 2,
                            ),
                          )
                        : Row(
                            children: [
                              _StatCard(
                                label: 'Students',
                                value: '$_totalStudents',
                                icon: Icons.school_outlined,
                                color: const Color(0xFF1E90FF),
                              ),
                              const SizedBox(width: 10),
                              _StatCard(
                                label: 'Alumni',
                                value: '$_totalAlumni',
                                icon: Icons.people_outline,
                                color: const Color(0xFF00C9A7),
                              ),
                              const SizedBox(width: 10),
                              _StatCard(
                                label: 'Admins',
                                value: '$_totalAdmins',
                                icon: Icons.admin_panel_settings_outlined,
                                color: const Color(0xFFFF6B35),
                              ),
                            ],
                          ),
                    const SizedBox(height: 28),
                    const Text(
                      'Quick Actions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _actionTile(
                          Icons.post_add_outlined,
                          'Post Job',
                          const Color(0xFFFF6B35),
                          onTap: _showPostJobSheet,
                        ),
                        _actionTile(
                          Icons.people_outline,
                          'All Users',
                          const Color(0xFF1E90FF),
                          onTap: () => _tabController.animateTo(1),
                        ),
                        _actionTile(
                          Icons.work_outline,
                          'All Jobs',
                          const Color(0xFF00C9A7),
                          onTap: () => _tabController.animateTo(2),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Recent Users',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _tabController.animateTo(1),
                          child: const Text(
                            'See all',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFFFF6B35),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._allUsers
                        .take(3)
                        .map(
                          (u) => _UserTile(
                            user: u,
                            roleColor: _roleColor(u['role']),
                            onTap: () => _showUserDetail(u),
                            onDelete: () => _deleteUser(u['uid'], u['name']),
                          ),
                        ),
                  ],
                ),
              ),

              // ── TAB 2 — USERS ────────────────────────────────────
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: ['All', 'student', 'alumni', 'admin']
                            .map(
                              (r) => _FilterChip(
                                label: r == 'All'
                                    ? r
                                    : r[0].toUpperCase() + r.substring(1),
                                selected: _filterRole == r,
                                onTap: () {
                                  setState(() => _filterRole = r);
                                  _loadAllUsers();
                                },
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_allUsers.length} users found',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.45),
                          ),
                        ),
                        GestureDetector(
                          onTap: _loadAllUsers,
                          child: const Text(
                            'Refresh',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFFF6B35),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _usersLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B35),
                              strokeWidth: 2,
                            ),
                          )
                        : _allUsers.isEmpty
                        ? Center(
                            child: Text(
                              'No users found.',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: _allUsers.length,
                            itemBuilder: (_, i) => _UserTile(
                              user: _allUsers[i],
                              roleColor: _roleColor(_allUsers[i]['role']),
                              onTap: () => _showUserDetail(_allUsers[i]),
                              onDelete: () => _deleteUser(
                                _allUsers[i]['uid'],
                                _allUsers[i]['name'],
                              ),
                            ),
                          ),
                  ),
                ],
              ),

              // ── TAB 3 — JOBS ─────────────────────────────────────
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_jobs.length} jobs posted',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.45),
                          ),
                        ),
                        GestureDetector(
                          onTap: _showPostJobSheet,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B35),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '+ Post Job',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _jobsLoading
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Color(0xFFFF6B35),
                              strokeWidth: 2,
                            ),
                          )
                        : _jobs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.work_off_outlined,
                                  color: Colors.white.withOpacity(0.25),
                                  size: 40,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'No jobs posted yet.',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.35),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                GestureDetector(
                                  onTap: _showPostJobSheet,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF6B35),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Post First Job',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                            itemCount: _jobs.length,
                            itemBuilder: (_, i) => _JobTile(
                              job: _jobs[i],
                              onDelete: () => _deleteJob(
                                _jobs[i]['id'],
                                _jobs[i]['title'] ?? '',
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showPostJobSheet,
        backgroundColor: const Color(0xFFFF6B35),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Post Job',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// USER TILE
// ─────────────────────────────────────────────────────────────────────────────
class _UserTile extends StatelessWidget {
  final Map<String, dynamic> user;
  final Color roleColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _UserTile({
    required this.user,
    required this.roleColor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final Color c = user['color'] as Color;
    final String sub = user['role'] == 'student'
        ? [
            user['branch'],
            user['year'],
          ].where((s) => s.toString().isNotEmpty).join(' · ')
        : user['role'] == 'alumni'
        ? [
            user['company'],
            user['batch'],
          ].where((s) => s.toString().isNotEmpty).join(' · ')
        : user['email'];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.withOpacity(0.15),
                border: Border.all(color: c.withOpacity(0.35), width: 1.5),
              ),
              child: Center(
                child: Text(
                  user['initials'],
                  style: TextStyle(
                    fontSize: 14,
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
                    user['name'],
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.45),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                user['role'],
                style: TextStyle(
                  fontSize: 10,
                  color: roleColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onDelete,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B5C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFFF3B5C),
                  size: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// JOB TILE
// ─────────────────────────────────────────────────────────────────────────────
class _JobTile extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onDelete;
  const _JobTile({required this.job, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFFF6B35).withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6B35).withOpacity(0.3),
              ),
            ),
            child: const Icon(
              Icons.work_outline,
              color: Color(0xFFFF6B35),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  job['company'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if ((job['location'] ?? '').toString().isNotEmpty) ...[
                      Icon(
                        Icons.location_on_outlined,
                        size: 11,
                        color: Colors.white.withOpacity(0.4),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        job['location'],
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        job['type'] ?? 'Job',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Color(0xFFFF6B35),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFFF3B5C).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF3B5C),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STAT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.45),
            ),
          ),
        ],
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFFFF6B35)
            : Colors.white.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? const Color(0xFFFF6B35)
              : Colors.white.withOpacity(0.15),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.white.withOpacity(0.6),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// ADMIN PROFILE SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _AdminProfileSheet extends StatelessWidget {
  final String name, email, imageUrl, department;
  final VoidCallback onLogout;
  const _AdminProfileSheet({
    required this.name,
    required this.email,
    required this.imageUrl,
    required this.department,
    required this.onLogout,
  });

  String get _initials {
    final p = name.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF0D1B2E),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
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
        const SizedBox(height: 20),
        CircleAvatar(
          radius: 36,
          backgroundColor: const Color(0xFF2A1200),
          backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
          child: imageUrl.isEmpty
              ? Text(
                  _initials,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFFF6B35),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        Text(
          name,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          email,
          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5)),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFF6B35).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFFF6B35).withOpacity(0.3)),
          ),
          child: const Text(
            'Admin',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFFF6B35),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (department.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.account_balance_outlined,
                size: 16,
                color: Color(0xFFFF6B35),
              ),
              const SizedBox(width: 10),
              Text(
                department,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Divider(color: Colors.white.withOpacity(0.1)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: ElevatedButton.icon(
            onPressed: onLogout,
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
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV
// ─────────────────────────────────────────────────────────────────────────────
class _AdminBottomNav extends StatefulWidget {
  final VoidCallback onLogout;
  const _AdminBottomNav({required this.onLogout});
  @override
  State<_AdminBottomNav> createState() => _AdminBottomNavState();
}

class _AdminBottomNavState extends State<_AdminBottomNav> {
  int _sel = 0;
  @override
  Widget build(BuildContext context) {
    const items = [
      {
        'icon': Icons.dashboard_outlined,
        'active': Icons.dashboard,
        'label': 'Dashboard',
      },
      {'icon': Icons.people_outline, 'active': Icons.people, 'label': 'Users'},
      {'icon': Icons.work_outline, 'active': Icons.work, 'label': 'Jobs'},
      {
        'icon': Icons.person_outline,
        'active': Icons.person,
        'label': 'Profile',
      },
    ];
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.07))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(items.length, (i) {
          final active = _sel == i;
          return GestureDetector(
            onTap: () => setState(() => _sel = i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 64,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active
                        ? items[i]['active'] as IconData
                        : items[i]['icon'] as IconData,
                    color: active
                        ? const Color(0xFFFF6B35)
                        : Colors.white.withOpacity(0.35),
                    size: 22,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    items[i]['label'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      color: active
                          ? const Color(0xFFFF6B35)
                          : Colors.white.withOpacity(0.35),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}
