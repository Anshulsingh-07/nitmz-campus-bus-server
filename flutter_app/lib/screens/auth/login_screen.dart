import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/api_service.dart';
import '../../models/models.dart';
import '../student/student_home.dart';
import '../admin/admin_home.dart';
import '../driver/driver_home.dart';

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
  bool _obscurePass = true;
  bool _isRegister = false;
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _driverMode = false;
  int? _busNumber;
  Future<List<dynamic>>? _availableBuses;
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
    _emailCtrl.text = 'student@nitmz.ac.in';
    _passCtrl.text = 'student123';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggleRole(bool isAdmin) {
    setState(() {
      _isAdmin = isAdmin;
      _emailCtrl.text = isAdmin
          ? 'caretaker-bh1@nitmz.ac.in'
          : 'student@nitmz.ac.in';
      _passCtrl.text = isAdmin ? 'caretaker123' : 'student123';
    });
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthService>();
    final api = context.read<ApiService>();
    if (_driverMode) {
      final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
      if (!RegExp(r'^[6-9]\d{9}$').hasMatch(phone)) { auth.setError('Enter a valid 10-digit Indian mobile number'); return; }
      if (!RegExp(r'^\d{6}$').hasMatch(_pinCtrl.text)) { auth.setError('PIN must contain 6 digits'); return; }
      if (_isRegister) {
        if (_nameCtrl.text.trim().isEmpty || _pinCtrl.text != _confirmPinCtrl.text || _busNumber == null) { auth.setError('Enter your name, matching PINs, and choose a bus'); return; }
        final result = await auth.driverRegister(_nameCtrl.text.trim(), phone, _pinCtrl.text, _busNumber!, api);
        if (result == 'pending' && mounted) {
          setState(() { _isRegister = false; });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Registration submitted. A caretaker will review and approve your account. You\'ll be notified once approved.',
              ),
            ),
          );
        }
      } else {
        final success = await auth.driverLogin(phone, _pinCtrl.text, api);
        if (success && mounted) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriverHomeScreen()));
        } else if (mounted && auth.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(auth.error!)),
          );
        }
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
          builder: (_) =>
              auth.isAdmin ? const AdminHome() : const StudentHome(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (_driverMode) return _buildDriverBody(auth);
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

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 32),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(child: _roleBtn('Student / Staff', false)),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() {
                              _driverMode = true;
                              _isRegister = false;
                              _isAdmin = false;
                              _availableBuses = context
                                  .read<ApiService>()
                                  .getAvailableDriverBuses();
                            }),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Center(
                                child: Text(
                                  'Driver',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
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
                              _isAdmin
                                  ? Icons.admin_panel_settings
                                  : Icons.school,
                              color: const Color(0xFF1565C0),
                              size: 28,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _isRegister
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
                        if (_isRegister) _buildHostelDropdown(),
                        if (_isRegister) const SizedBox(height: 14),

                        // Demo hint
                        if (!_isRegister)
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _isAdmin
                                        ? 'caretaker-bh1@nitmz.ac.in / caretaker123'
                                        : 'student@nitmz.ac.in / student123',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                                    _isRegister ? 'Register' : 'Login',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (!_isAdmin)
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

  Widget _buildDriverBody(AuthService auth) {
    return Scaffold(backgroundColor: const Color(0xFFF6F6F6), appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Driver access'), leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() { _driverMode = false; _isRegister = false; }))), body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Card(elevation: 2, child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Icon(Icons.directions_bus, size: 40, color: Colors.black), const SizedBox(height: 12), Text(_isRegister ? 'Create driver account' : 'Driver login', textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 20), if (_isRegister) TextField(controller: _nameCtrl, textCapitalization: TextCapitalization.words, autofillHints: const [AutofillHints.name], decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())), if (_isRegister) const SizedBox(height: 12), TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, autofillHints: const [AutofillHints.telephoneNumber], maxLength: 10, decoration: const InputDecoration(prefixText: '+91 ', labelText: 'Mobile number', border: OutlineInputBorder())), const SizedBox(height: 8), TextField(controller: _pinCtrl, keyboardType: TextInputType.number, obscureText: _obscurePass, maxLength: 6, autofillHints: [_isRegister ? AutofillHints.newPassword : AutofillHints.password], decoration: InputDecoration(labelText: '6-digit PIN', border: const OutlineInputBorder(), suffixIcon: IconButton(onPressed: () => setState(() => _obscurePass = !_obscurePass), icon: Icon(_obscurePass ? Icons.visibility_off : Icons.visibility)))), if (_isRegister) ...[const SizedBox(height: 8), TextField(controller: _confirmPinCtrl, keyboardType: TextInputType.number, obscureText: _obscurePass, maxLength: 6, decoration: const InputDecoration(labelText: 'Confirm PIN', border: OutlineInputBorder())), const SizedBox(height: 8), FutureBuilder<List<dynamic>>(future: _availableBuses ??= context.read<ApiService>().getAvailableDriverBuses(), builder: (context, snapshot) { final buses = snapshot.data ?? []; return DropdownButtonFormField<int>(value: _busNumber, decoration: const InputDecoration(labelText: 'Available bus', border: OutlineInputBorder()), items: buses.map((b) => DropdownMenuItem<int>(value: (b['busNumber'] as num).toInt(), child: Text('Bus ${b['busNumber']} · ${b['route'] ?? 'Campus route'}'))).toList(), onChanged: (v) => setState(() => _busNumber = v), hint: Text(snapshot.hasError ? 'Could not load buses' : 'Choose an unassigned bus')); })], if (auth.error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Text(auth.error!, style: const TextStyle(color: Colors.red))), const SizedBox(height: 8), SizedBox(height: 50, child: FilledButton(onPressed: auth.isLoading ? null : _handleLogin, style: FilledButton.styleFrom(backgroundColor: Colors.black), child: auth.isLoading ? const SizedBox(width: 22,height: 22,child: CircularProgressIndicator(color: Colors.white,strokeWidth: 2)) : Text(_isRegister ? 'Register' : 'Login'))), TextButton(onPressed: auth.isLoading ? null : () => setState(() { _isRegister = !_isRegister; auth.clearError(); }), child: Text(_isRegister ? 'Already registered? Login' : 'Register as a driver'))]))))))));
  }

  Widget _roleBtn(String label, bool isAdmin) {
    final selected = _isAdmin == isAdmin;
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
