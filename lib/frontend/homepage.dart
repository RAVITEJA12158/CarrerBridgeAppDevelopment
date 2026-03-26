import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import './login.dart';
import './user_cache.dart';
import './job_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  String name     = "Loading...";
  String email    = "";
  String imageUrl = "";
  String role     = "student";

  late AnimationController _fadeController;
  late Animation<double>   _fadeAnim;

  // ── Jobs from Firestore ───────────────────────────────────────────────────
  List<Map<String, dynamic>> _jobs        = [];
  bool   _jobsLoading = true;
  Set<String> _savedJobIds = {};          // ← tracks saved job IDs locally
  Set<String> _pendingAlumniIds = {};     // ← tracks sent connection requests
  List<Map<String, dynamic>> _acceptedConnections = []; // ← accepted alumni contacts
  int _currentTab = 0;                   // ← 0=Home 1=Explore 2=Saved

  // ── Real-time stream subscriptions ───────────────────────────────────────
  StreamSubscription? _studentDocSub;       // listens to acceptedAlumni + savedJobs
  StreamSubscription? _pendingRequestsSub;  // listens to connectionRequests status

  // ── Alumni from Firestore ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _alumni      = [];
  bool   _alumniLoading = true;
  String? _alumniError;

  final List<Color> _alumniColors = [
    Color(0xFF1E90FF), Color(0xFF00C9A7),
    Color(0xFFFFA940), Color(0xFFFF6B8A),
    Color(0xFFA78BFA), Color(0xFF34D399),
  ];

  // Job card accent colours (cycle)
  final List<Color> _jobColors = [
    Color(0xFF1E90FF), Color(0xFF00C9A7),
    Color(0xFFFFA940), Color(0xFFFF6B8A),
    Color(0xFFA78BFA),
  ];

  final List<Map<String, dynamic>> _quickActions = [
    {'icon': Icons.search,           'label': 'Find Jobs', 'color': Color(0xFF1E90FF)},
    {'icon': Icons.bookmark_outline, 'label': 'Saved',     'color': Color(0xFF00C9A7)},
    {'icon': Icons.send_outlined,    'label': 'Applied',   'color': Color(0xFFFFA940)},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(
        parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    loadUserProfile();
    _loadJobs();
    loadAlumni();
    _loadSavedJobs();          // one-time load (student controls this)
    _startRealTimeListeners(); // ← real-time for connections + requests
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _studentDocSub?.cancel();
    _pendingRequestsSub?.cancel();
    super.dispose();
  }

  Future<void> loadUserProfile() async {
    try {
      // ✅ Uses cache — only hits Firestore on first load
      await UserCache.instance.load();
      if (!mounted) return;
      setState(() {
        name     = UserCache.instance.name.isNotEmpty
                       ? UserCache.instance.name : "User";
        email    = UserCache.instance.email;
        imageUrl = UserCache.instance.imageUrl;
        role     = UserCache.instance.role;
      });
    } catch (e) {
      debugPrint("Profile error: $e");
      setState(() => name = "User");
    }
  }

  // ── Fetch active jobs posted by Admin or Alumni ───────────────────────────
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
          'id'          : snap.docs[i].id,
          'title'       : d['title']          ?? '',
          'company'     : d['company']         ?? '',
          'location'    : d['location']        ?? '',
          'type'        : d['type']            ?? 'Full-time',
          'description' : d['description']     ?? '',
          'applyLink'   : d['applyLink']       ?? '',
          'postedBy'    : d['postedBy']        ?? '',
          'postedByRole': d['postedByRole']    ?? 'admin',
          'color'       : _jobColors[i % _jobColors.length],
        });
      }
      if (mounted) setState(() { _jobs = list; _jobsLoading = false; });
    } catch (e) {
      debugPrint("Jobs error: $e");
      if (mounted) setState(() => _jobsLoading = false);
    }
  }

  // ── Load saved job IDs for current student ────────────────────────────────
  // ── Real-time listeners ───────────────────────────────────────────────────
  // Replaces one-time _loadConnections() and _loadPendingRequests()
  // Updates UI automatically when:
  //   - alumni accepts/rejects a connection request
  //   - student's acceptedAlumni list changes
  void _startRealTimeListeners() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // 1. Listen to student's own doc for acceptedAlumni changes
    //    → fires instantly when alumni accepts and writes to this doc
    _studentDocSub = FirebaseFirestore.instance
        .collection('user')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      final List accepted = doc.data()?['acceptedAlumni'] ?? [];
      setState(() => _acceptedConnections =
          List<Map<String, dynamic>>.from(accepted));
      debugPrint('🔄 Connections updated: ${_acceptedConnections.length}');
    }, onError: (e) => debugPrint('Student doc stream error: $e'));

    // 2. Listen to connectionRequests for this student
    //    → fires when alumni accepts/rejects (status changes)
    //    → updates pending buttons in real time
    _pendingRequestsSub = FirebaseFirestore.instance
        .collection('connectionRequests')
        .where('studentId', isEqualTo: user.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      // Only keep 'pending' ones for the button state
      final pending = snap.docs
          .where((d) => d.data()['status'] == 'pending')
          .map((d) => d.data()['alumniId'] as String)
          .toSet();
      setState(() => _pendingAlumniIds = pending);
      debugPrint('🔄 Pending requests updated: ${_pendingAlumniIds.length}');
    }, onError: (e) => debugPrint('Requests stream error: $e'));
  }

  Future<void> _loadSavedJobs() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('user').doc(user.uid).get();
      if (doc.exists && mounted) {
        final List saved = doc.data()?['savedJobs'] ?? [];
        setState(() => _savedJobIds = Set<String>.from(saved));
      }
    } catch (e) { debugPrint('Load saved jobs error: $e'); }
  }

  // ── Toggle save/unsave a job ──────────────────────────────────────────────
  // ── Navigate to job detail page ──────────────────────────────────────────
  void _showJobDetail(Map<String, dynamic> job) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => JobDetailPage(
        job: job,
        isSaved: _savedJobIds.contains(job['id']),
        onSave: () => _toggleSaveJob(job['id']),
      ),
    ));
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
      await FirebaseFirestore.instance
          .collection('user').doc(user.uid).update({
        'savedJobs': isSaved
            ? FieldValue.arrayRemove([jobId])
            : FieldValue.arrayUnion([jobId]),
      });
    } catch (e) {
      // Revert on error
      setState(() {
        if (isSaved) _savedJobIds.add(jobId);
        else _savedJobIds.remove(jobId);
      });
      debugPrint('Toggle save error: $e');
    }
  }

  // ── Send connection request to alumni ─────────────────────────────────────
  // (_loadPendingRequests and _loadConnections replaced by _startRealTimeListeners)
  Future<void> _sendConnectRequest(Map<String, dynamic> alumni) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Load student's own details
    final studentDoc = await FirebaseFirestore.instance
        .collection('user').doc(user.uid).get();
    final studentName  = studentDoc.data()?['name']  ?? '';
    final studentEmail = studentDoc.data()?['email'] ?? '';

    try {
      await FirebaseFirestore.instance
          .collection('connectionRequests')
          .add({
        'studentId'   : user.uid,
        'studentName' : studentName,
        'studentEmail': studentEmail,
        'alumniId'    : alumni['uid'],
        'alumniName'  : alumni['name'],
        'status'      : 'pending',     // pending | accepted | rejected
        'createdAt'   : FieldValue.serverTimestamp(),
      });
      setState(() => _pendingAlumniIds.add(alumni['uid']));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              'Connection request sent to ${alumni['name']}! ✅')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send request: $e')));
    }
  }

  // ── Fetch Alumni ──────────────────────────────────────────────────────────
  Future<void> loadAlumni() async {
    try {
      setState(() { _alumniLoading = true; _alumniError = null; });
      final snap = await FirebaseFirestore.instance
          .collection('alumini')  // ← alumni stored in 'alumini' collection
          .get();
      final list = <Map<String, dynamic>>[];
      for (int i = 0; i < snap.docs.length; i++) {
        final d = snap.docs[i].data();
        final n = (d['name'] ?? 'Alumni') as String;
        final parts = n.trim().split(' ');
        final initials = parts.length >= 2
            ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
            : n.substring(0, n.length >= 2 ? 2 : 1).toUpperCase();
        list.add({
          'uid'        : snap.docs[i].id,   // ← needed for connection request
          'name'    : n,
          'company' : d['company']     ?? '',
          'designation': d['designation'] ?? '',
          'batch'   : d['batch']       ?? '',
          'imageUrl': d['imageUrl']    ?? '',
          'initials': initials,
          'color'   : _alumniColors[i % _alumniColors.length],
        });
      }
      if (mounted) setState(() { _alumni = list; _alumniLoading = false; });
    } catch (e) {
      debugPrint("Alumni error: $e");
      if (mounted) setState(() {
        _alumniLoading = false;
        _alumniError = "Could not load alumni data.";
      });
    }
  }

  Future<void> logout() async {
    UserCache.instance.clear(); // ← clear cache on logout
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const loginPage()), (_) => false);
  }

  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ProfileBottomSheet(
        name: name, email: email, imageUrl: imageUrl, role: role,
        onLogout: () { Navigator.pop(context); logout(); },
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
            child: CustomScrollView(slivers: [

          // ── App Bar ────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 130, floating: false, pinned: true,
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
                child: Row(crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Good morning 👋', style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withOpacity(0.5))),
                      const SizedBox(height: 2),
                      Text(name, style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800,
                          color: Colors.white, letterSpacing: 0.2)),
                    ],
                  )),
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.1)),
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 20),
                      onPressed: () {}, padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _showProfileSheet,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: const Color(0xFF1E90FF), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFF1E3A5F),
                        backgroundImage: imageUrl.isNotEmpty
                            ? NetworkImage(imageUrl) : null,
                        child: imageUrl.isEmpty
                            ? Text(name.isNotEmpty
                                ? name[0].toUpperCase() : 'U',
                                style: const TextStyle(
                                    color: Color(0xFF1E90FF),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16))
                            : null,
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),

          SliverToBoxAdapter(child: Padding(
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
                        color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 14),
                    Icon(Icons.search,
                        color: Colors.white.withOpacity(0.35), size: 20),
                    const SizedBox(width: 10),
                    Text('Search jobs, internships...',
                        style: TextStyle(fontSize: 14,
                            color: Colors.white.withOpacity(0.35))),
                  ]),
                ),

                const SizedBox(height: 28),

                // ── Quick Actions ──────────────────────────────
                const Text('Quick Actions', style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Colors.white)),
                const SizedBox(height: 14),
                Row(
                  children: _quickActions.map((a) => Expanded(
                    child: _QuickActionTile(
                        icon: a['icon'], label: a['label'],
                        color: a['color']),
                  )).toList(),
                ),

                const SizedBox(height: 30),

                // ── Jobs header ────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Latest Jobs', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                    GestureDetector(
                      onTap: _loadJobs,
                      child: const Text('Refresh', style: TextStyle(
                          fontSize: 13, color: Color(0xFF1E90FF),
                          fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ),
          )),

          // ── Jobs List ──────────────────────────────────────────
          _jobsLoading
              ? SliverToBoxAdapter(child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator(
                      color: Color(0xFF1E90FF), strokeWidth: 2))))
              : _jobs.isEmpty
                  ? SliverToBoxAdapter(child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 24, horizontal: 20),
                      child: Center(child: Column(children: [
                        Icon(Icons.work_off_outlined,
                            color: Colors.white.withOpacity(0.2),
                            size: 42),
                        const SizedBox(height: 10),
                        Text('No jobs posted yet.\nCheck back soon!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.35),
                                fontSize: 13, height: 1.5)),
                      ]))))
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) => GestureDetector(
                            onTap: () => _showJobDetail(_jobs[i]),
                            child: _JobCard(
                              job: _jobs[i],
                              isSaved: _savedJobIds.contains(_jobs[i]['id']),
                              onSave: () => _toggleSaveJob(_jobs[i]['id']),
                            ),
                          ),
                          childCount: _jobs.length,
                        ),
                      ),
                    ),

          // ── Alumni Section Header ──────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 30, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text('Alumni Network', style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700,
                      color: Colors.white)),
                  const SizedBox(height: 3),
                  Text(
                    _alumniLoading ? 'Loading...'
                        : '${_alumni.length} alumni registered',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF7FA7C9)),
                  ),
                ]),
                GestureDetector(
                  onTap: loadAlumni,
                  child: const Text('Refresh', style: TextStyle(
                      fontSize: 13, color: Color(0xFF1E90FF),
                      fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          )),

          // ── Alumni Cards ───────────────────────────────────────
          SliverToBoxAdapter(child: SizedBox(
            height: 168,
            child: _alumniLoading
                ? ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    itemCount: 3,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, __) => _AlumniCardSkeleton())
                : _alumniError != null
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.white.withOpacity(0.3),
                              size: 32),
                          const SizedBox(height: 8),
                          Text(_alumniError!, style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12)),
                          TextButton(onPressed: loadAlumni,
                              child: const Text('Retry',
                                  style: TextStyle(
                                      color: Color(0xFF1E90FF)))),
                        ]))
                    : _alumni.isEmpty
                        ? Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline,
                                  color: Colors.white.withOpacity(0.25),
                                  size: 36),
                              const SizedBox(height: 8),
                              Text('No alumni registered yet.',
                                  style: TextStyle(
                                      color: Colors.white.withOpacity(0.35),
                                      fontSize: 13)),
                            ]))
                        : ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                            itemCount: _alumni.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 12),
                            itemBuilder: (_, i) =>
                                _AlumniCard(
                                  alumni: _alumni[i],
                                  isPending: _pendingAlumniIds.contains(_alumni[i]['uid']),
                                  onConnect: () => _sendConnectRequest(_alumni[i]),
                                )),
          )),
          // ── My Connections ─────────────────────────────────────────
          // Shows alumni who accepted the student's connection request
          // with their email so the student can reach out directly
          if (_acceptedConnections.isNotEmpty) ...[
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('My Connections', style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: Colors.white)),
                    const SizedBox(height: 2),
                    Text('${_acceptedConnections.length} alumni connected',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF7FA7C9))),
                  ]),
                  GestureDetector(
                    onTap: () => setState(() {}), // real-time — just trigger rebuild
                    child: const Text('Refresh', style: TextStyle(
                        fontSize: 13, color: Color(0xFF1E90FF),
                        fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            )),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) => _ConnectionTile(
                      connection: _acceptedConnections[i]),
                  childCount: _acceptedConnections.length,
                ),
              ),
            ),
          ],

          // bottom padding — 32 base + system bottom inset (home indicator)
          SliverToBoxAdapter(
            child: Builder(
              builder: (ctx) => SizedBox(
                height: 32 + MediaQuery.of(ctx).padding.bottom,
              ),
            ),
          ),
        ]),
          ),   // end FadeTransition (Tab 0)

          // ── Tab 1: EXPLORE ────────────────────────────────────
          _ExploreTab(),

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
// JOB CARD
// ─────────────────────────────────────────────────────────────────────────────
class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final bool        isSaved;
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
          Row(children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: c.withOpacity(0.15),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: c.withOpacity(0.3)),
              ),
              child: Icon(Icons.business_center, color: c, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job['title'], style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: Colors.white)),
                const SizedBox(height: 3),
                Text(job['company'], style: TextStyle(
                    fontSize: 12, color: Colors.white.withOpacity(0.5))),
              ],
            )),
            // ── Save / Bookmark button ─────────────────────────
            GestureDetector(
              onTap: onSave,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 36, height: 36,
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
          ]),
          const SizedBox(height: 10),
          Row(children: [
            if (job['location'].toString().isNotEmpty) ...[
              Icon(Icons.location_on_outlined,
                  size: 12, color: Colors.white.withOpacity(0.4)),
              const SizedBox(width: 3),
              Flexible(child: Text(job['location'], style: TextStyle(
                  fontSize: 11, color: Colors.white.withOpacity(0.4)))),
              const SizedBox(width: 10),
            ],
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(job['type'], style: TextStyle(
                  fontSize: 10, color: c, fontWeight: FontWeight.w600)),
            ),
            if (job['postedByRole'].toString().toLowerCase() == 'alumni') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C9A7).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('Alumni Referral', style: TextStyle(
                    fontSize: 9, color: Color(0xFF00C9A7),
                    fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
          // Apply link if present
          if (job['applyLink'] != null &&
              job['applyLink'].toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {},
              child: Row(children: [
                const Icon(Icons.open_in_new,
                    size: 12, color: Color(0xFF1E90FF)),
                const SizedBox(width: 4),
                const Text('Apply Now', style: TextStyle(
                    fontSize: 11, color: Color(0xFF1E90FF),
                    fontWeight: FontWeight.w600)),
              ]),
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
  final bool         isPending;   // true if request already sent
  final VoidCallback onConnect;   // called when Connect tapped

  const _AlumniCard({
    required this.alumni,
    required this.isPending,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    final Color  c           = alumni['color'] as Color;
    final String imageUrl    = alumni['imageUrl']    ?? '';
    final String company     = alumni['company']     ?? '';
    final String designation = alumni['designation'] ?? '';
    final String batch       = alumni['batch']       ?? '';
    final String subtitle    =
        (designation.isNotEmpty && company.isNotEmpty)
            ? '$designation @ $company'
            : designation.isNotEmpty ? designation
            : company.isNotEmpty    ? company
            : 'Alumni';

    return Container(
      width: 158,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.09)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        // Avatar
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(shape: BoxShape.circle,
              color: c.withOpacity(0.15),
              border: Border.all(color: c.withOpacity(0.4), width: 1.5)),
          child: imageUrl.isNotEmpty
              ? ClipOval(child: Image.network(imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                      child: Text(alumni['initials'], style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700, color: c)))))
              : Center(child: Text(alumni['initials'], style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: c))),
        ),
        const SizedBox(height: 8),

        // Name
        Text(alumni['name'], textAlign: TextAlign.center,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12,
                fontWeight: FontWeight.w700, color: Colors.white)),
        const SizedBox(height: 3),

        // Role @ Company
        Text(subtitle, textAlign: TextAlign.center, maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10,
                color: Colors.white.withOpacity(0.5), height: 1.3)),
        const SizedBox(height: 6),

        // Batch badge
        if (batch.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6)),
            child: Text(batch, style: TextStyle(
                fontSize: 9, color: c, fontWeight: FontWeight.w600)),
          ),

        const SizedBox(height: 8),

        // ── Connect button ───────────────────────────────────
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
                  color: isPending
                      ? Colors.white.withOpacity(0.35)
                      : c,
                ),
                const SizedBox(width: 4),
                Text(
                  isPending ? 'Pending' : 'Connect',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPending
                        ? Colors.white.withOpacity(0.35)
                        : c,
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Skeleton ──────────────────────────────────────────────────────────────────
class _AlumniCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 148, padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.07))),
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      _s(52, 52, circular: true), const SizedBox(height: 10),
      _s(80, 10), const SizedBox(height: 6),
      _s(100, 8), const SizedBox(height: 4),
      _s(60, 8), const SizedBox(height: 8),
      _s(50, 16, radius: 6),
    ]),
  );

  Widget _s(double w, double h,
      {bool circular = false, double radius = 4}) =>
      Container(
        width: w, height: h,
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            borderRadius: circular
                ? BorderRadius.circular(w)
                : BorderRadius.circular(radius)));
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileBottomSheet extends StatelessWidget {
  final String name, email, imageUrl, role;
  final VoidCallback onLogout;
  const _ProfileBottomSheet({required this.name, required this.email,
      required this.imageUrl, required this.role, required this.onLogout});
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFF0D1B2E),
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 40, height: 4,
          decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(2))),
      const SizedBox(height: 24),
      Container(
        decoration: BoxDecoration(shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF1E90FF), width: 2.5),
            boxShadow: [BoxShadow(
                color: const Color(0xFF1E90FF).withOpacity(0.3),
                blurRadius: 20, spreadRadius: 2)]),
        child: CircleAvatar(radius: 38,
            backgroundColor: const Color(0xFF1E3A5F),
            backgroundImage: imageUrl.isNotEmpty
                ? NetworkImage(imageUrl) : null,
            child: imageUrl.isEmpty
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E90FF))) : null),
      ),
      const SizedBox(height: 14),
      Text(name, style: const TextStyle(fontSize: 20,
          fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 4),
      Text(email, style: TextStyle(
          fontSize: 13, color: Colors.white.withOpacity(0.5))),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF1E90FF).withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: const Color(0xFF1E90FF).withOpacity(0.3)),
        ),
        child: Text(role, style: const TextStyle(fontSize: 12,
            color: Color(0xFF1E90FF), fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 24),
      Divider(color: Colors.white.withOpacity(0.1)),
      const SizedBox(height: 8),
      _MenuItem(icon: Icons.person_outline,  label: 'Edit Profile', onTap: () {}),
      _MenuItem(icon: Icons.settings_outlined, label: 'Settings',  onTap: () {}),
      _MenuItem(icon: Icons.info_outline,    label: 'About Us',    onTap: () {}),
      _MenuItem(icon: Icons.help_outline,    label: 'Help & Support', onTap: () {}),
      const SizedBox(height: 8),
      Divider(color: Colors.white.withOpacity(0.1)),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Logout', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF3B5C).withOpacity(0.15),
            foregroundColor: const Color(0xFFFF3B5C), elevation: 0,
            side: const BorderSide(color: Color(0xFFFF3B5C), width: 1),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
    ]),
  );
}

class _MenuItem extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _MenuItem({required this.icon, required this.label,
      required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap, contentPadding: EdgeInsets.zero,
    leading: Container(width: 38, height: 38,
        decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 18)),
    title: Text(label, style: const TextStyle(fontSize: 14,
        fontWeight: FontWeight.w500, color: Colors.white)),
    trailing: Icon(Icons.chevron_right,
        color: Colors.white.withOpacity(0.3), size: 18),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUPPORTING WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _QuickActionTile extends StatelessWidget {
  final IconData icon; final String label; final Color color;
  const _QuickActionTile(
      {required this.icon, required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 64, height: 64,
          decoration: BoxDecoration(color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withOpacity(0.25))),
          child: Icon(icon, color: color, size: 26)),
      const SizedBox(height: 8),
      Text(label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12,
              color: Colors.white.withOpacity(0.65),
              fontWeight: FontWeight.w500)),
    ]);
}

// ─────────────────────────────────────────────────────────────────────────────
// CONNECTION TILE — shows accepted alumni contact with email
// ─────────────────────────────────────────────────────────────────────────────
class _ConnectionTile extends StatelessWidget {
  final Map<String, dynamic> connection;
  const _ConnectionTile({required this.connection});

  @override
  Widget build(BuildContext context) {
    final String alumniName  = connection['alumniName']  ?? 'Alumni';
    final String alumniEmail = connection['alumniEmail'] ?? '';
    final parts    = alumniName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : alumniName.substring(0, alumniName.length >= 2 ? 2 : 1).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF00C9A7).withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: const Color(0xFF00C9A7).withOpacity(0.25)),
      ),
      child: Row(children: [
        // Avatar
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00C9A7).withOpacity(0.15),
            border: Border.all(
                color: const Color(0xFF00C9A7).withOpacity(0.4),
                width: 1.5),
          ),
          child: Center(child: Text(initials, style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700,
              color: Color(0xFF00C9A7)))),
        ),
        const SizedBox(width: 12),

        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(alumniName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
              const SizedBox(width: 8),
              // Connected badge
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C9A7).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text('Connected ✓', style: TextStyle(
                    fontSize: 9, color: Color(0xFF00C9A7),
                    fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 5),

            // ── Email — tap to copy ─────────────────────────
            GestureDetector(
              onTap: () {
                if (alumniEmail.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: alumniEmail));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('📋 Copied: $alumniEmail'),
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
              child: Row(children: [
                const Icon(Icons.email_outlined,
                    size: 13, color: Color(0xFF1E90FF)),
                const SizedBox(width: 5),
                Flexible(child: Text(
                  alumniEmail.isNotEmpty ? alumniEmail : 'Email not available',
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
                )),
                if (alumniEmail.isNotEmpty) ...[
                  const SizedBox(width: 5),
                  const Icon(Icons.copy, size: 11,
                      color: Color(0xFF1E90FF)),
                ],
              ]),
            ),
          ],
        )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPLORE TAB
// ─────────────────────────────────────────────────────────────────────────────
class _ExploreTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search, size: 48,
            color: Colors.white.withOpacity(0.15)),
        const SizedBox(height: 12),
        Text('Explore coming soon',
            style: TextStyle(fontSize: 15,
                color: Colors.white.withOpacity(0.3))),
      ]),
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
    // Filter only saved jobs from the loaded jobs list
    final savedJobs = allJobs
        .where((j) => savedJobIds.contains(j['id']))
        .toList();

    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Saved Jobs', style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800,
                color: Colors.white)),
            const SizedBox(height: 4),
            Text('${savedJobs.length} job${savedJobs.length == 1 ? '' : 's'} saved',
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF7FA7C9))),
          ]),
        ),

        Expanded(
          child: savedJobs.isEmpty
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.bookmark_outline,
                        size: 52,
                        color: Colors.white.withOpacity(0.15)),
                    const SizedBox(height: 14),
                    Text('No saved jobs yet',
                        style: TextStyle(fontSize: 16,
                            color: Colors.white.withOpacity(0.3))),
                    const SizedBox(height: 6),
                    Text('Tap the bookmark icon on any job to save it',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12,
                            color: Colors.white.withOpacity(0.2))),
                  ],
                ))
              : ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                      20, 0, 20,
                      20 + MediaQuery.of(context).padding.bottom),
                  itemCount: savedJobs.length,
                  itemBuilder: (_, i) => _SavedJobCard(
                    job: savedJobs[i],
                    onUnsave: () => onUnsave(savedJobs[i]['id']),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SAVED JOB CARD — same as job card but unsave button instead of save
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
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: c.withOpacity(0.15),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: c.withOpacity(0.3)),
            ),
            child: Icon(Icons.business_center, color: c, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(job['title'], style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700,
                  color: Colors.white)),
              const SizedBox(height: 3),
              Text(job['company'], style: TextStyle(
                  fontSize: 12, color: Colors.white.withOpacity(0.5))),
            ],
          )),
          // Unsave button
          GestureDetector(
            onTap: onUnsave,
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF1E90FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF1E90FF).withOpacity(0.4)),
              ),
              child: const Icon(Icons.bookmark,
                  color: Color(0xFF1E90FF), size: 18),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          if (job['location'].toString().isNotEmpty) ...[
            Icon(Icons.location_on_outlined,
                size: 12, color: Colors.white.withOpacity(0.4)),
            const SizedBox(width: 3),
            Flexible(child: Text(job['location'], style: TextStyle(
                fontSize: 11, color: Colors.white.withOpacity(0.4)))),
            const SizedBox(width: 10),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(job['type'], style: TextStyle(
                fontSize: 10, color: c, fontWeight: FontWeight.w600)),
          ),
        ]),
        if (job['applyLink'] != null &&
            job['applyLink'].toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.open_in_new, size: 12,
                color: Color(0xFF1E90FF)),
            const SizedBox(width: 4),
            const Text('Apply Now', style: TextStyle(
                fontSize: 11, color: Color(0xFF1E90FF),
                fontWeight: FontWeight.w600)),
          ]),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM NAV — stateless, controlled by parent HomePage
// ─────────────────────────────────────────────────────────────────────────────
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabChanged;
  const _BottomNav({required this.currentIndex, required this.onTabChanged});

  static const _items = [
    {'icon': Icons.home_outlined,    'active': Icons.home,     'label': 'Home'},
    {'icon': Icons.search,           'active': Icons.search,   'label': 'Explore'},
    {'icon': Icons.bookmark_outline, 'active': Icons.bookmark, 'label': 'Saved'},
  ];

  @override
  Widget build(BuildContext context) => Container(
    height: 70,
    decoration: BoxDecoration(
        color: const Color(0xFF0D1B2E),
        border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.07)))),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: List.generate(_items.length, (i) {
          final active = currentIndex == i;
          return GestureDetector(
            onTap: () => onTabChanged(i),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(width: 64, child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(active
                    ? _items[i]['active'] as IconData
                    : _items[i]['icon'] as IconData,
                    color: active
                        ? const Color(0xFF1E90FF)
                        : Colors.white.withOpacity(0.35),
                    size: 22),
                const SizedBox(height: 4),
                Text(_items[i]['label'] as String,
                    style: TextStyle(fontSize: 10,
                        fontWeight: active
                            ? FontWeight.w700 : FontWeight.w400,
                        color: active
                            ? const Color(0xFF1E90FF)
                            : Colors.white.withOpacity(0.35))),
              ],
            )),
          );
        })),
  );
}  // end _BottomNav