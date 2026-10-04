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
  bool get isDriver => _currentUser?.isDriver ?? false;

  Future<void> checkAuthState(ApiService api) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final email = prefs.getString('email');
    if (token != null && email == null && prefs.getString('role') == 'driver') {
      try {
        final remoteUser = await api.getDriverCurrentUser(token);
        _currentUser = UserModel.fromJson({...remoteUser, 'token': token});
        await prefs.setString('name', _currentUser!.name);
        await prefs.setString('phone', _currentUser!.phone ?? '');
        if (_currentUser!.busNumber != null) {
          await prefs.setInt('busNumber', _currentUser!.busNumber!);
        }
      } catch (_) {
        _currentUser = null;
        for (final key in [
          'token',
          'phone',
          'busNumber',
          'name',
          'role',
          'userId',
        ]) {
          await prefs.remove(key);
        }
      }
      notifyListeners();
      return;
    }
    if (token != null && email == null) {
      for (final key in [
        'token',
        'phone',
        'busNumber',
        'name',
        'role',
        'userId',
        'hostelId',
      ]) {
        await prefs.remove(key);
      }
      notifyListeners();
      return;
    }
    final name = prefs.getString('name');
    final role = prefs.getString('role');
    final hostelId = prefs.getString('hostelId');
    final userId = prefs.getString('userId');

    if (token != null && email != null) {
      try {
        final remoteUser = await api.getCurrentUser(token);
        _currentUser = UserModel(
          id: (remoteUser['id'] ?? userId ?? '').toString(),
          name: (remoteUser['name'] ?? name ?? '').toString(),
          email: (remoteUser['email'] ?? email ?? '').toString(),
          role: (remoteUser['role'] ?? role ?? 'student').toString(),
          hostelId: remoteUser['hostelId']?.toString() ?? hostelId,
          mustChangePassword: remoteUser['mustChangePassword'] == true,
          token: token,
        );

        if (_currentUser!.email.isNotEmpty) {
          await prefs.setString('email', _currentUser!.email);
        }
        await prefs.setString('name', _currentUser!.name);
        await prefs.setString('role', _currentUser!.role);
        await prefs.setString('userId', _currentUser!.id);
        if (_currentUser!.hostelId != null &&
            _currentUser!.hostelId!.isNotEmpty) {
          await prefs.setString('hostelId', _currentUser!.hostelId!);
        }
      } catch (_) {
        _currentUser = null;
        for (final key in [
          'token',
          'email',
          'phone',
          'name',
          'role',
          'userId',
          'hostelId',
          'busNumber',
        ]) {
          await prefs.remove(key);
        }
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
      await prefs.remove('phone');
      await prefs.remove('busNumber');
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
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await api.driverLogin(phone, pin);
      final userJson = Map<String, dynamic>.from(data['user'] as Map);
      userJson['token'] = data['token'];
      _currentUser = UserModel.fromJson(userJson);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token'].toString());
      await prefs.remove('email');
      await prefs.remove('hostelId');
      await prefs.setString('name', _currentUser!.name);
      await prefs.setString('role', 'driver');
      await prefs.setString('phone', _currentUser!.phone ?? phone);
      await prefs.setString('userId', _currentUser!.id);
      if (_currentUser!.busNumber != null) {
        await prefs.setInt('busNumber', _currentUser!.busNumber!);
      }
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
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
      await prefs.remove('phone');
      await prefs.remove('busNumber');
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

  Future<bool> changePassword(String newPassword, ApiService api) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final token = _currentUser?.token;
      if (token == null || token.isEmpty) {
        throw Exception('Sign in again to change your password');
      }
      await api.changePassword(token, newPassword);
      _currentUser!.mustChangePassword = false;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void setError(String message) {
    _error = message;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> logout() async {
    final token = _currentUser?.token;
    _currentUser = null;
    if (token != null) {
      try {
        await ApiService().logout(token);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    for (final key in [
      'token',
      'email',
      'phone',
      'name',
      'role',
      'userId',
      'hostelId',
      'busNumber',
    ]) {
      await prefs.remove(key);
    }
    notifyListeners();
  }
}
