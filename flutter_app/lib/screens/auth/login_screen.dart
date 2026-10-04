import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../student/student_home.dart';
import '../admin/admin_home.dart';
import '../driver/driver_home.dart';
import 'password_change_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isAdmin = false;
  bool _driverMode = false;
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _isRegister = false;
  bool _isResettingPassword = false;
  final _nameCtrl = TextEditingController();
  String _selectedHostel = 'BH1';
  late AnimationController _animCtrl;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleRole(bool isAdmin) {
    setState(() {
      _driverMode = false;
      _isAdmin = isAdmin;
      _emailCtrl.clear();
      _passCtrl.clear();
    });
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    if (_driverMode) {
      final enteredPhone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      final phone = enteredPhone.length > 10
          ? enteredPhone.substring(enteredPhone.length - 10)
          : enteredPhone;
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone) ||
          !RegExp(r'^\d{6}$').hasMatch(_pinCtrl.text)) {
        auth.setError('Enter a valid 10-digit mobile number and 6-digit PIN');
        return;
      }
      final success = await auth.driverLogin(phone, _pinCtrl.text, api);
      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
        );
      }
      return;
    }
    if (_isRegister) {
      final success = await auth.register(
        _nameCtrl.text.trim(),
        _emailCtrl.text.trim(),
        _passCtrl.text,
        _selectedHostel,
        api,
      );
      if (success && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const StudentHome()),
        );
      }
      return;
    }

    final success = await auth.login(
      _emailCtrl.text.trim(),
      _passCtrl.text,
      api,
    );
    if (success && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => auth.currentUser?.mustChangePassword == true
              ? const PasswordChangeScreen()
              : auth.isAdmin
              ? const AdminHome()
              : const StudentHome(),
        ),
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your college email first.')),
      );
      return;
    }
    setState(() => _isResettingPassword = true);
    try {
      final message = await context.read<ApiService>().forgotPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResettingPassword = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        height: size.height,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D47A1), Color(0xFF1565C0), Color(0xFFE3F2FD)],
            stops: [0, 0.45, 1],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 40),
                // Header
                const Icon(
                  Icons.directions_bus_rounded,
                  size: 60,
                  color: Colors.white,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Campus Bus Tracker',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'NIT Mizoram',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 32),

                // Role Toggle
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _roleBtn('Student', false)),
                      Expanded(child: _roleBtn('Caretaker', true)),
                      Expanded(child: _driverRoleBtn()),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Card
                SlideTransition(
                  position: _slideAnim,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _driverMode
                                  ? Icons.directions_bus
                                  : _isAdmin
                                  ? Icons.admin_panel_settings
                                  : Icons.school,
                              color: const Color(0xFF1565C0),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _driverMode
                                  ? 'Driver Login'
                                  : _isRegister
                                  ? 'Create Account'
                                  : (_isAdmin
                                        ? 'Caretaker Login'
                                        : 'Student Login'),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        if (_driverMode) ...[
                          _buildField(
                            'Mobile Number',
                            Icons.phone,
                            _phoneCtrl,
                            inputType: TextInputType.phone,
                          ),
                          const SizedBox(height: 14),
                          _buildPinField(),
                          const SizedBox(height: 14),
                        ] else ...[
                          if (_isRegister) ...[
                            _buildField('Full Name', Icons.person, _nameCtrl),
                            const SizedBox(height: 14),
                          ],
                          _buildField(
                            'Email Address',
                            Icons.email,
                            _emailCtrl,
                            inputType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 14),
                          _buildPasswordField(),
                          const SizedBox(height: 14),
                          if (!_isRegister)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isResettingPassword
                                    ? null
                                    : _forgotPassword,
                                child: _isResettingPassword
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Forgot password?'),
                              ),
                            ),
                          if (_isRegister) _buildHostelDropdown(),
                          if (_isRegister) const SizedBox(height: 14),
                        ],

                        const SizedBox(height: 20),

                        if (auth.error != null)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Text(
                              auth.error!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        if (auth.error != null) const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _handleLogin,
                            child: auth.isLoading
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    _driverMode
                                        ? 'Driver Login'
                                        : (_isRegister ? 'Register' : 'Login'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (!_isAdmin && !_driverMode)
                          Center(
                            child: TextButton(
                              onPressed: () => setState(() {
                                _isRegister = !_isRegister;
                              }),
                              child: Text(
                                _isRegister
                                    ? 'Already have an account? Login'
                                    : "Don't have an account? Register",
                                style: const TextStyle(
                                  color: Color(0xFF1565C0),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // Bottom info
                Text(
                  ' Developed By : Anshul Singh and Dilip Sahu',
                  style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleBtn(String label, bool isAdmin) {
    final selected = !_driverMode && _isAdmin == isAdmin;
    return GestureDetector(
      onTap: () => _toggleRole(isAdmin),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isAdmin ? Icons.admin_panel_settings : Icons.school,
              size: 18,
              color: selected ? const Color(0xFF1565C0) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF1565C0) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _driverRoleBtn() {
    final selected = _driverMode;
    return GestureDetector(
      onTap: () => setState(() {
        _driverMode = true;
        _isRegister = false;
        context.read<AuthService>().clearError();
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.directions_bus,
              size: 18,
              color: selected ? const Color(0xFF1565C0) : Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              'Driver',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? const Color(0xFF1565C0) : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    String label,
    IconData icon,
    TextEditingController ctrl, {
    TextInputType inputType = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF1565C0), size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildPasswordField() {
    return TextField(
      controller: _passCtrl,
      obscureText: _obscurePass,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock, color: Color(0xFF1565C0), size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePass ? Icons.visibility_off : Icons.visibility,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePass = !_obscurePass),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF1565C0), width: 2),
        ),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildPinField() {
    return TextField(
      controller: _pinCtrl,
      keyboardType: TextInputType.number,
      maxLength: 6,
      obscureText: _obscurePass,
      decoration: InputDecoration(
        labelText: '6-digit PIN',
        counterText: '',
        prefixIcon: const Icon(Icons.lock, color: Color(0xFF1565C0), size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePass ? Icons.visibility_off : Icons.visibility,
            size: 20,
          ),
          onPressed: () => setState(() => _obscurePass = !_obscurePass),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
      ),
    );
  }

  Widget _buildHostelDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedHostel,
      decoration: InputDecoration(
        labelText: 'Select Hostel',
        prefixIcon: const Icon(Icons.home, color: Color(0xFF1565C0), size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
      ),
      items: HostelModel.allHostels
          .map(
            (h) => DropdownMenuItem(
              value: h.id,
              child: Text('${h.name} - ${h.fullName}'),
            ),
          )
          .toList(),
      onChanged: (v) => setState(() => _selectedHostel = v!),
    );
  }
}
