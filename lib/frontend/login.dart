import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'register.dart';
import 'homepage.dart'; // Student home
import 'alumni_home.dart'; // Alumni home
import 'admin_home.dart'; // Admin home

class loginPage extends StatefulWidget {
  final String initialRole;
  const loginPage({super.key, this.initialRole = 'student'});

  @override
  State<loginPage> createState() => _loginPageState();
}

class _loginPageState extends State<loginPage>
    with SingleTickerProviderStateMixin {
  bool obscureText = true;
  bool obscureCode = true; // for admin access code field
  late int selectedRole;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final adminCodeController = TextEditingController(); // admin login code
  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final List<String> roles = ['student', 'admin', 'alumni'];
  final List<IconData> roleIcons = [
    Icons.school,
    Icons.admin_panel_settings,
    Icons.people,
  ];

  @override
  void initState() {
    super.initState();
    selectedRole = roles.indexOf(widget.initialRole);
    if (selectedRole == -1) selectedRole = 0;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    emailController.dispose();
    passwordController.dispose();
    adminCodeController.dispose();
    super.dispose();
  }

  // ── Forgot Password ──────────────────────────────────────────────────────
  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      // Pre-fill with whatever is already typed in the email field
      text: emailController.text.trim(),
    );
    bool _sending = false;

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.6),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: const Color(0xFF0D1B2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
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
                        Icons.lock_reset_outlined,
                        color: Color(0xFF1E90FF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Reset Password',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          'We\'ll send a reset link to your email',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF7FA7C9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Email field
                const Text(
                  'Email Address',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7FA7C9),
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: resetEmailController,
                  keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'you@example.com',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.28),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      color: Color(0xFF1E90FF),
                      size: 19,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: Colors.white.withOpacity(0.1),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Color(0xFF1E90FF),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Buttons
                Row(
                  children: [
                    // Cancel
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF7FA7C9),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Send Reset Link
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _sending
                            ? null
                            : () async {
                                final resetEmail = resetEmailController.text
                                    .trim();
                                if (resetEmail.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Please enter your email'),
                                    ),
                                  );
                                  return;
                                }
                                setDialogState(() => _sending = true);
                                try {
                                  await FirebaseAuth.instance
                                      .sendPasswordResetEmail(
                                        email: resetEmail,
                                      );
                                  if (!mounted) return;
                                  Navigator.pop(ctx);
                                  // ── Success dialog ──────────────────────
                                  showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      backgroundColor: const Color(0xFF0D1B2E),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(24),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(28),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 64,
                                              height: 64,
                                              decoration: BoxDecoration(
                                                color: const Color(
                                                  0xFF00C9A7,
                                                ).withOpacity(0.15),
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFF00C9A7,
                                                  ).withOpacity(0.4),
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.mark_email_read_outlined,
                                                color: Color(0xFF00C9A7),
                                                size: 30,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            const Text(
                                              'Email Sent!',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              'A password reset link has been sent to $resetEmail.\n\nCheck your inbox and follow the link.',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.white.withOpacity(
                                                  0.6,
                                                ),
                                                height: 1.6,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFF1E90FF,
                                                  ),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 13,
                                                      ),
                                                  shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                ),
                                                child: const Text(
                                                  'OK',
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
                                  );
                                } on FirebaseAuthException catch (e) {
                                  setDialogState(() => _sending = false);
                                  String msg = 'Failed to send reset email.';
                                  if (e.code == 'user-not-found') {
                                    msg = 'No account found with this email.';
                                  } else if (e.code == 'invalid-email') {
                                    msg = 'Invalid email format.';
                                  }
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(
                                    context,
                                  ).showSnackBar(SnackBar(content: Text(msg)));
                                } catch (e) {
                                  setDialogState(() => _sending = false);
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error: $e')),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E90FF),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          disabledBackgroundColor: const Color(
                            0xFF1E90FF,
                          ).withOpacity(0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Send Link',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
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
      ),
    );
  }

  Future<void> loginUser() async {
    if (emailController.text.trim().isEmpty ||
        passwordController.text.trim().isEmpty) {
      _showSnack("Please enter email and password");
      return;
    }

    // ── Admin access code pre-check ─────────────────────────────────────
    const String adminSecretCode = 'ADMIN@2025'; // must match register.dart
    if (roles[selectedRole] == 'admin') {
      if (adminCodeController.text.trim().isEmpty) {
        _showSnack("Please enter the Admin Access Code.");
        return;
      }
      if (adminCodeController.text.trim() != adminSecretCode) {
        _showSnack("Invalid Admin Access Code.");
        return;
      }
    }

    try {
      // Step 1 — Firebase Auth sign in
      final UserCredential cred = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );
      if (!mounted) return;

      // Step 2 — Read from correct collection based on selected tab
      // student → 'user' | alumni → 'alumini' | admin → 'admin'
      final String selectedRoleName = roles[selectedRole];
      String collectionName;
      if (selectedRoleName == 'student') {
        collectionName = 'user';
      } else if (selectedRoleName == 'alumni') {
        collectionName = 'alumini';
      } else {
        collectionName = 'admin';
      }

      final doc = await FirebaseFirestore.instance
          .collection(collectionName)
          .doc(cred.user!.uid)
          .get();
      if (!mounted) return;

      // Step 3 — If doc doesn't exist in that collection, wrong role selected
      if (!doc.exists) {
        await FirebaseAuth.instance.signOut();
        _showSnack(
          "No ${selectedRoleName[0].toUpperCase()}${selectedRoleName.substring(1)} account found. "
          "Please check your role or register.",
        );
        return;
      }

      // Step 4 — Route to the correct home page based on role
      if (!mounted) return;
      Widget destination;
      // selectedRoleName is already verified — doc exists in that collection
      switch (selectedRoleName) {
        case 'admin':
          destination = const AdminHomePage();
          break;
        case 'alumni':
          destination = const AlumniHomePage();
          break;
        default: // 'Student'
          destination = const HomePage();
      }

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => destination),
        (_) => false,
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = "No account found with this email.";
          break;
        case 'wrong-password':
        case 'invalid-credential':
          message = "Incorrect password. Please try again.";
          break;
        case 'invalid-email':
          message = "Invalid email format.";
          break;
        case 'too-many-requests':
          message = "Too many attempts. Try again later.";
          break;
        default:
          message = e.message ?? "Login failed.";
      }
      if (!mounted) return;
      _showSnack(message);
    } catch (e) {
      debugPrint("Login error: $e");
      if (!mounted) return;
      _showSnack("Something went wrong: ${e.toString()}");
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E27), Color(0xFF0D2137), Color(0xFF0A3D62)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // ── Logo ──────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E90FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF1E90FF).withOpacity(0.4),
                            ),
                          ),
                          child: const Icon(
                            Icons.work_outline,
                            color: Color(0xFF1E90FF),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'CareerBridge',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Student Job & Internship Finder',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF7FA7C9),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 40),
                    const Text(
                      'Welcome back 👋',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in to explore opportunities',
                      style: TextStyle(fontSize: 15, color: Color(0xFF7FA7C9)),
                    ),

                    const SizedBox(height: 32),

                    // ── Role Selector ─────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.1),
                        ),
                      ),
                      child: Row(
                        children: List.generate(3, (i) {
                          final active = selectedRole == i;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => selectedRole = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? const Color(0xFF1E90FF)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: active
                                      ? [
                                          BoxShadow(
                                            color: const Color(
                                              0xFF1E90FF,
                                            ).withOpacity(0.4),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      roleIcons[i],
                                      size: 14,
                                      color: active
                                          ? Colors.white
                                          : const Color(0xFF7FA7C9),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      roles[i][0].toUpperCase() +
                                          roles[i].substring(1),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: active
                                            ? Colors.white
                                            : const Color(0xFF7FA7C9),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // ── Glass Card ────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 30,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Email Address',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7FA7C9),
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: emailController,
                            hint: 'you@example.com',
                            icon: Icons.email_outlined,
                            obscure: false,
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Password',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF7FA7C9),
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildTextField(
                            controller: passwordController,
                            hint: '••••••••',
                            icon: Icons.lock_outline,
                            obscure: obscureText,
                            isPassword: true,
                          ),
                          // ── Admin Access Code field ───────────────
                          if (roles[selectedRole] == 'admin') ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Admin Access Code',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7FA7C9),
                                letterSpacing: 0.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildTextField(
                              controller: adminCodeController,
                              hint: 'Enter access code',
                              icon: Icons.security_outlined,
                              obscure: obscureCode,
                              isPassword: true,
                              onToggle: () =>
                                  setState(() => obscureCode = !obscureCode),
                            ),
                          ],
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: _showForgotPasswordDialog,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                              ),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(
                                  color: Color(0xFF1E90FF),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: loginUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1E90FF),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'Sign In as ${roles[selectedRole][0].toUpperCase()}${roles[selectedRole].substring(1)}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // ── Register Row ──────────────────────────────
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(
                              color: Color(0xFF7FA7C9),
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => registerPage(
                                  initialRole: roles[selectedRole],
                                ),
                              ),
                            ),
                            child: const Text(
                              'Register now',
                              style: TextStyle(
                                color: Color(0xFF1E90FF),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                    Center(
                      child: Text(
                        '© 2025 CareerBridge. All rights reserved.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withOpacity(0.25),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool obscure,
    bool isPassword = false,
    VoidCallback? onToggle, // ← custom toggle for each password field
  }) => TextField(
    controller: controller,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white, fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
      prefixIcon: Icon(icon, color: const Color(0xFF1E90FF), size: 20),
      suffixIcon: isPassword
          ? IconButton(
              icon: Icon(
                obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: const Color(0xFF7FA7C9),
                size: 20,
              ),
              onPressed:
                  onToggle ?? () => setState(() => obscureText = !obscureText),
            )
          : null,
      filled: true,
      fillColor: Colors.white.withOpacity(0.07),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
        borderSide: const BorderSide(color: Color(0xFF1E90FF), width: 1.5),
      ),
    ),
  );
}
