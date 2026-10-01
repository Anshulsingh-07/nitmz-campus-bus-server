import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = false;
  String? _error;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _currentUser != null;
  bool get isAdmin => _currentUser?.isAdmin ?? false;
  bool get isDriver => _currentUser?.role == 'driver';

  Future<void> checkAuthState(ApiService api) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final email = prefs.getString('email');
    final phone = prefs.getString('phone');
    final name = prefs.getString('name');
    final role = prefs.getString('role');
    final hostelId = prefs.getString('hostelId');
    final userId = prefs.getString('userId');

    if (token != null && (email != null || phone != null)) {
      try {
        final remoteUser = await api.getCurrentUser(token);
        _currentUser = UserModel(
          id: (remoteUser['id'] ?? userId ?? '').toString(),
          name: (remoteUser['name'] ?? name ?? '').toString(),
          email: (remoteUser['email'] ?? email ?? '').toString(),
          role: (remoteUser['role'] ?? role ?? 'student').toString(),
          hostelId: remoteUser['hostelId']?.toString() ?? hostelId,
          phone: remoteUser['phone']?.toString() ?? phone,
          busNumber: (remoteUser['busNumber'] as num?)?.toInt() ?? prefs.getInt('busNumber'),
          token: token,
        );

        if (_currentUser!.email.isNotEmpty) await prefs.setString('email', _currentUser!.email);
        if (_currentUser!.phone != null) await prefs.setString('phone', _currentUser!.phone!);
        await prefs.setString('name', _currentUser!.name);
        await prefs.setString('role', _currentUser!.role);
        await prefs.setString('userId', _currentUser!.id);
        if (_currentUser!.hostelId != null &&
            _currentUser!.hostelId!.isNotEmpty) {
          await prefs.setString('hostelId', _currentUser!.hostelId!);
        }
      } catch (_) {
        _currentUser = null;
        for (final key in ['token','email','phone','name','role','userId','hostelId','busNumber']) { await prefs.remove(key); }
      }

      notifyListeners();
    }
  }

  Future<bool> login(String email, String password, ApiService api) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await api.login(email, password);
      final userJson = data['user'] as Map<String, dynamic>;
      userJson['token'] = data['token'];
      _currentUser = UserModel.fromJson(userJson);
      _currentUser!.token = data['token'];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('email', _currentUser!.email);
      await prefs.setString('name', _currentUser!.name);
      await prefs.setString('role', _currentUser!.role);
      await prefs.setString('userId', _currentUser!.id);
      if (_currentUser!.hostelId != null) {
        await prefs.setString('hostelId', _currentUser!.hostelId!);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> driverLogin(String phone, String pin, ApiService api) async {
    _isLoading = true; _error = null; notifyListeners();
    try {
      final data = await api.driverLogin(phone, pin);
      final user = Map<String, dynamic>.from(data['user'] as Map)..['token'] = data['token'];
      _currentUser = UserModel.fromJson(user)..token = data['token'] as String;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', _currentUser!.token!);
      await prefs.remove('email');
      await prefs.remove('hostelId');
      await prefs.setString('userId', _currentUser!.id);
      await prefs.setString('role', 'driver');
      await prefs.setString('name', _currentUser!.name);
      await prefs.setString('phone', phone);
      await prefs.setInt('busNumber', _currentUser!.busNumber!);
      _isLoading = false; notifyListeners(); return true;
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      _error = message.contains('pending_approval')
          ? 'Your account is awaiting caretaker approval.'
          : message.contains('rejected')
          ? 'Your registration was rejected. Contact the caretaker for details.'
          : message;
      _isLoading = false; notifyListeners(); return false;
    }
  }

  Future<String?> driverRegister(String name, String phone, String pin, int busNumber, ApiService api) async {
    _isLoading = true; _error = null; notifyListeners();
    try { final result = await api.driverRegister(name, phone, pin, busNumber); _isLoading = false; notifyListeners(); return result['status']?.toString(); }
    catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false; notifyListeners(); return null;
    }
  }

  Future<bool> register(
    String name,
    String email,
    String password,
    String hostelId,
    ApiService api,
  ) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final data = await api.register(name, email, password, hostelId);
      final userJson = data['user'] as Map<String, dynamic>;
      userJson['token'] = data['token'];
      _currentUser = UserModel.fromJson(userJson);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('email', _currentUser!.email);
      await prefs.setString('name', _currentUser!.name);
      await prefs.setString('role', _currentUser!.role);
      await prefs.setString('userId', _currentUser!.id);
      if (_currentUser!.hostelId != null) {
        await prefs.setString('hostelId', _currentUser!.hostelId!);
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void setError(String message) { _error = message; notifyListeners(); }
  void clearError() { _error = null; notifyListeners(); }

  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in ['token','email','phone','name','role','userId','hostelId','busNumber']) { await prefs.remove(key); }
    notifyListeners();
  }
}
