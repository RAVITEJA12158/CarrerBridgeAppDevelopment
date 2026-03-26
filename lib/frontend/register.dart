import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'homepage.dart';
import 'alumni_home.dart';
import 'admin_home.dart';

class registerPage extends StatefulWidget {
  final String initialRole;
  const registerPage({super.key, this.initialRole = 'student'});

  @override
  State<registerPage> createState() => _registerPageState();
}

class _registerPageState extends State<registerPage>
    with SingleTickerProviderStateMixin {
  bool obscureText = true;
  bool obscureConfirm = true;
  bool _isLoading = false;

  late String selectedRole;

  final List<String> roles = ['student', 'admin', 'alumni'];
  final List<IconData> roleIcons = [
    Icons.school,
    Icons.admin_panel_settings,
    Icons.people,
  ];

  // ── Common controllers ────────────────────────────────────────────────────
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  final phoneController = TextEditingController();

  // ── Student-specific ──────────────────────────────────────────────────────
  final rollController = TextEditingController();
  final regController = TextEditingController();
  final yearController = TextEditingController();
  String? selectedBranch;

  // ── Alumni-specific ───────────────────────────────────────────────────────
  final batchController = TextEditingController();
  final companyController = TextEditingController();
  final designationController = TextEditingController();

  // ── Admin-specific ────────────────────────────────────────────────────────
  final adminCodeController = TextEditingController();
  final departmentController = TextEditingController();

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    selectedRole = widget.initialRole.toLowerCase();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    phoneController.dispose();
    rollController.dispose();
    regController.dispose();
    yearController.dispose();
    batchController.dispose();
    companyController.dispose();
    designationController.dispose();
    adminCodeController.dispose();
    departmentController.dispose();
    super.dispose();
  }

  Future<void> register() async {
    // ── Secret admin access code — change this to your own secret ────────
    const String adminSecretCode = 'ADMIN@2025';

    // ── Validation ────────────────────────────────────────────────────────

    // Full name
    if (nameController.text.trim().isEmpty) {
      _showSnack("Please enter your full name");
      return;
    }
    if (nameController.text.trim().length < 3) {
      _showSnack("Name must be at least 3 characters");
      return;
    }

    // Email
    final String email = emailController.text.trim();
    if (email.isEmpty) {
      _showSnack("Please enter your email");
      return;
    }
    if (!RegExp(r'^[\w.+-]+@gmail\.com$').hasMatch(email)) {
      _showSnack("Email must be a valid @gmail.com address");
      return;
    }

    // Phone
    final String phone = phoneController.text.trim();
    if (phone.isEmpty) {
      _showSnack("Please enter your phone number");
      return;
    }
    if (!RegExp(r'^\+?[0-9]{10,13}$').hasMatch(phone)) {
      _showSnack("Enter a valid phone number (10–13 digits)");
      return;
    }

    // Password
    final String password = passwordController.text;
    if (password.trim().isEmpty) {
      _showSnack("Please enter a password");
      return;
    }
    if (password.length < 8) {
      _showSnack("Password must be at least 8 characters");
      return;
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      _showSnack("Password must contain at least one uppercase letter (A–Z)");
      return;
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      _showSnack("Password must contain at least one lowercase letter (a–z)");
      return;
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      _showSnack("Password must contain at least one number (0–9)");
      return;
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]').hasMatch(password)) {
      _showSnack(
        "Password must contain at least one special character (!@#\$...)",
      );
      return;
    }
    if (password != confirmPasswordController.text) {
      _showSnack("Passwords do not match");
      return;
    }

    // ── Student field validation ───────────────────────────────────────────
    if (selectedRole == 'student') {
      if (rollController.text.trim().isEmpty) {
        _showSnack("Please enter your Roll Number");
        return;
      }
      if (regController.text.trim().isEmpty) {
        _showSnack("Please enter your Registration Number");
        return;
      }
      if (selectedBranch == null || selectedBranch!.isEmpty) {
        _showSnack("Please select your Branch");
        return;
      }
      if (yearController.text.trim().isEmpty) {
        _showSnack("Please enter your Academic Year (e.g. 2021-2025)");
        return;
      }
      if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(yearController.text.trim())) {
        _showSnack("Academic Year format must be YYYY-YYYY (e.g. 2021-2025)");
        return;
      }
    }

    // ── Alumni field validation ────────────────────────────────────────────
    if (selectedRole == 'alumni') {
      if (batchController.text.trim().isEmpty) {
        _showSnack("Please enter your Batch / Passing Year");
        return;
      }
      if (!RegExp(r'^\d{4}-\d{4}$').hasMatch(batchController.text.trim())) {
        _showSnack("Batch format must be YYYY-YYYY (e.g. 2019-2023)");
        return;
      }
      if (companyController.text.trim().isEmpty) {
        _showSnack("Please enter your Current Company");
        return;
      }
      if (designationController.text.trim().isEmpty) {
        _showSnack("Please enter your Designation");
        return;
      }
    }

    // ── Admin access code check ───────────────────────────────────────────
    if (selectedRole == 'admin') {
      if (departmentController.text.trim().isEmpty) {
        _showSnack("Please enter your Department");
        return;
      }
      if (adminCodeController.text.trim().isEmpty) {
        _showSnack("Please enter the Admin Access Code");
        return;
      }
      if (adminCodeController.text.trim() != adminSecretCode) {
        _showSnack("Invalid Admin Access Code. Registration denied.");
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      // ── Step 1: Create Firebase Auth account ──────────────────────────
      debugPrint(
        "📝 Creating auth account for: ${emailController.text.trim()}",
      );

      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: emailController.text.trim(),
            password: passwordController.text.trim(),
          );

      final String uid = userCredential.user!.uid;
      debugPrint("✅ Auth account created. UID: $uid");

      // ── Step 2: Build Firestore document ──────────────────────────────
      Map<String, dynamic> userData = {
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': phoneController.text.trim(),
        'role': selectedRole.toLowerCase(),
        'imageUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Append role-specific fields
      if (selectedRole == 'student') {
        userData.addAll({
          'rollNo': rollController.text.trim(),
          'regNo': regController.text.trim(),
          'branch': selectedBranch ?? '',
          'year': yearController.text.trim(),
        });
      } else if (selectedRole == 'alumni') {
        userData.addAll({
          'batch': batchController.text.trim(),
          'company': companyController.text.trim(),
          'designation': designationController.text.trim(),
          'password': passwordController.text.trim(),
        });
      } else if (selectedRole == 'admin') {
        userData.addAll({
          'department': departmentController.text.trim(),
          'accessCode': adminCodeController.text.trim(),
          'password': passwordController.text.trim(),
        });
      }

      debugPrint("📦 Writing to Firestore: users/$uid");
      debugPrint("📦 Data: $userData");

      // ── Step 3: Save to Firestore ─────────────────────────────────────
      String collection;
      if (selectedRole == 'student') {
        collection = 'user';
      } else if (selectedRole == 'alumni') {
        collection = 'alumini';
      } else {
        collection = 'admin';
      }

      await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .set(userData);

      debugPrint("✅ Firestore write successful for UID: $uid");

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Registration Successful! 🎉")),
      );
      if (!mounted) return;
      Widget destination;
      if (selectedRole == 'admin') {
        destination = const AdminHomePage();
      } else if (selectedRole == 'alumni') {
        destination = const AlumniHomePage();
      } else {
        destination = const HomePage();
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => destination),
      );
    } on FirebaseAuthException catch (e) {
      debugPrint("❌ FirebaseAuthException: ${e.code} — ${e.message}");
      String message = "Registration failed";
      if (e.code == "email-already-in-use") {
        message = "Email already registered. Try logging in.";
      } else if (e.code == "weak-password") {
        message = "Password too weak — use at least 8 characters.";
      } else if (e.code == "invalid-email") {
        message = "Invalid email format.";
      } else {
        message = e.message ?? message;
      }
      if (!mounted) return;
      _showSnack(message);
    } catch (e) {
      debugPrint("❌ Unexpected error during registration: $e");
      if (!mounted) return;
      _showSnack("Something went wrong: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

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
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Back + Title ─────────────────────────────────
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.12),
                            ),
                          ),
                          child: const Icon(
                            Icons.arrow_back_ios_new,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Fill in your details to get started',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF7FA7C9),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // ── Role Selector ─────────────────────────────────
                  _sectionLabel('Registering as'),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: List.generate(3, (i) {
                        final bool active = selectedRole == roles[i];
                        return Expanded(
                          child: GestureDetector(
                            onTap: () =>
                                setState(() => selectedRole = roles[i]),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                              padding: const EdgeInsets.symmetric(vertical: 10),
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

                  const SizedBox(height: 24),

                  // ── Glass Form Card ───────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
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
                        _sectionLabel('Full Name'),
                        const SizedBox(height: 8),
                        _field(
                          nameController,
                          'Your full name',
                          Icons.person_outline,
                        ),

                        const SizedBox(height: 16),
                        _sectionLabel('Email Address'),
                        const SizedBox(height: 8),
                        _field(
                          emailController,
                          'you@gmail.com',
                          Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),

                        const SizedBox(height: 16),
                        _sectionLabel('Phone Number'),
                        const SizedBox(height: 8),
                        _field(
                          phoneController,
                          '+91 XXXXXXXXXX',
                          Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),

                        // ── Student fields ─────────────────────────
                        if (selectedRole == 'student') ...[
                          const SizedBox(height: 16),
                          _dividerLabel('Academic Details'),
                          const SizedBox(height: 16),
                          _sectionLabel('Roll Number'),
                          const SizedBox(height: 8),
                          _field(rollController, 'e.g. 21A91A0501', Icons.tag),
                          const SizedBox(height: 16),
                          _sectionLabel('Registration Number'),
                          const SizedBox(height: 8),
                          _field(
                            regController,
                            'e.g. 2100123456',
                            Icons.badge_outlined,
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('Branch'),
                          const SizedBox(height: 8),
                          _branchDropdown(),
                          const SizedBox(height: 16),
                          _sectionLabel('Academic Year'),
                          const SizedBox(height: 8),
                          _field(
                            yearController,
                            'e.g. 2021-2025',
                            Icons.calendar_today_outlined,
                          ),
                        ],

                        // ── Alumni fields ──────────────────────────
                        if (selectedRole == 'alumni') ...[
                          const SizedBox(height: 16),
                          _dividerLabel('Alumni Details'),
                          const SizedBox(height: 16),
                          _sectionLabel('Batch / Passing Year'),
                          const SizedBox(height: 8),
                          _field(
                            batchController,
                            'e.g. 2019-2023',
                            Icons.calendar_month_outlined,
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('Current Company'),
                          const SizedBox(height: 8),
                          _field(
                            companyController,
                            'e.g. Google',
                            Icons.business_outlined,
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('Designation'),
                          const SizedBox(height: 8),
                          _field(
                            designationController,
                            'e.g. Software Engineer',
                            Icons.work_outline,
                          ),
                        ],

                        // ── Admin fields ───────────────────────────
                        if (selectedRole == 'admin') ...[
                          const SizedBox(height: 16),
                          _dividerLabel('Admin Details'),
                          const SizedBox(height: 16),
                          _sectionLabel('Department'),
                          const SizedBox(height: 8),
                          _field(
                            departmentController,
                            'e.g. CSE Department',
                            Icons.account_balance_outlined,
                          ),
                          const SizedBox(height: 16),
                          _sectionLabel('Admin Access Code'),
                          const SizedBox(height: 8),
                          _field(
                            adminCodeController,
                            'Enter access code',
                            Icons.security_outlined,
                            obscure: true,
                          ),
                        ],

                        // ── Password fields ────────────────────────
                        const SizedBox(height: 16),
                        _dividerLabel('Security'),
                        const SizedBox(height: 16),
                        _sectionLabel('Password'),
                        const SizedBox(height: 4),
                        // Password hint
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'Min 8 chars · Uppercase · Lowercase · Number · Special char',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withOpacity(0.38),
                            ),
                          ),
                        ),
                        _passwordField(
                          passwordController,
                          'Create a password',
                          obscureText,
                          () => setState(() => obscureText = !obscureText),
                        ),
                        const SizedBox(height: 16),
                        _sectionLabel('Confirm Password'),
                        const SizedBox(height: 8),
                        _passwordField(
                          confirmPasswordController,
                          'Re-enter your password',
                          obscureConfirm,
                          () =>
                              setState(() => obscureConfirm = !obscureConfirm),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Submit Button ─────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : register,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E90FF),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: const Color(
                          0xFF1E90FF,
                        ).withOpacity(0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              'Create ${selectedRole[0].toUpperCase()}${selectedRole.substring(1)} Account',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Already have an account? Sign in',
                        style: TextStyle(
                          color: Color(0xFF7FA7C9),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF7FA7C9),
      letterSpacing: 0.4,
    ),
  );

  Widget _dividerLabel(String text) => Row(
    children: [
      Expanded(
        child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.4),
            letterSpacing: 0.5,
          ),
        ),
      ),
      Expanded(
        child: Divider(color: Colors.white.withOpacity(0.12), height: 1),
      ),
    ],
  );

  Widget _field(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
  }) => TextField(
    controller: ctrl,
    obscureText: obscure,
    keyboardType: keyboardType,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF1E90FF), size: 19),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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

  Widget _passwordField(
    TextEditingController ctrl,
    String hint,
    bool obscure,
    VoidCallback toggle,
  ) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 13),
      prefixIcon: const Icon(
        Icons.lock_outline,
        color: Color(0xFF1E90FF),
        size: 19,
      ),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: const Color(0xFF7FA7C9),
          size: 19,
        ),
        onPressed: toggle,
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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

  Widget _branchDropdown() => DropdownButtonFormField<String>(
    value: selectedBranch,
    dropdownColor: const Color(0xFF0D1B2E),
    style: const TextStyle(color: Colors.white, fontSize: 14),
    iconEnabledColor: const Color(0xFF7FA7C9),
    decoration: InputDecoration(
      prefixIcon: const Icon(
        Icons.school_outlined,
        color: Color(0xFF1E90FF),
        size: 19,
      ),
      hintText: 'Select your branch',
      hintStyle: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 13),
      filled: true,
      fillColor: Colors.white.withOpacity(0.06),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
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
    items: ["CSE", "ECE", "EEE", "MECH", "CIVIL", "BIO TECH", "MME"]
        .map(
          (b) => DropdownMenuItem(
            value: b,
            child: Text(
              b,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        )
        .toList(),
    onChanged: (v) => setState(() => selectedBranch = v),
  );
}
