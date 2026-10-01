import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../auth/login_screen.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  StreamSubscription<Position>? _subscription;
  Timer? _uiTimer;
  Position? _lastPosition;
  DateTime? _lastSentAt;
  Position? _lastSentPosition;
  bool _sharing = false;
  bool _connected = true;
  String? _message;
  int _queueSize = 0;
  bool _flushingQueue = false;
  DateTime? _retryAfter;
  Duration _retryDelay = const Duration(seconds: 2);
  static const _queueKey = 'driver_location_queue';
  static const _tripKey = 'driver_trip_active';

  @override
  void initState() {
    super.initState();
    _restoreTrip();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _retryQueuedLocations();
    });
  }

  Future<void> _restoreTrip() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_tripKey) == true && mounted) {
      final resume = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Resume location sharing?'),
          content: const Text(
            'Your previous trip was interrupted. Resume sharing this phone’s location for your assigned bus?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('End trip'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Resume'),
            ),
          ],
        ),
      );
      if (resume == true) {
        await _startTrip(confirm: false);
      } else {
        await prefs.setBool(_tripKey, false);
      }
    }
    await _readQueue();
    if (_queueSize > 0) _retryQueuedLocations();
  }

  Future<void> _readQueue() async {
    final p = await SharedPreferences.getInstance();
    if (mounted)
      setState(() => _queueSize = (p.getStringList(_queueKey) ?? []).length);
  }

  Future<bool> _requestPermissions() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(
        () =>
            _message = 'Location services are off. Turn them on and try again.',
      );
      await Geolocator.openLocationSettings();
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied)
      permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(
        () => _message = permission == LocationPermission.deniedForever
            ? 'Location access is blocked. Open settings and allow location.'
            : 'Location permission is needed to share the bus location.',
      );
      if (permission == LocationPermission.deniedForever)
        await openAppSettings();
      return false;
    }
    final background = await Permission.locationAlways.request();
    if (!background.isGranted) {
      setState(
        () => _message =
            'Allow background location so sharing continues when the screen is off.',
      );
      await openAppSettings();
      return false;
    }
    if (await Permission.notification.isDenied)
      await Permission.notification.request();
    return true;
  }

  Future<void> _startTrip({bool confirm = true}) async {
    if (confirm) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Start sharing?'),
          content: const Text(
            'Your phone’s location will be shared with campus bus tracker while this trip is active.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Start trip'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('driver_battery_tip_seen') != true && mounted) {
      final openSettings = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Keep location sharing active'),
          content: const Text(
            'Some phone makers pause GPS in the background. You can allow unrestricted battery use so trips continue when the screen is off.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Battery settings'),
            ),
          ],
        ),
      );
      await prefs.setBool('driver_battery_tip_seen', true);
      if (openSettings == true)
        await Permission.ignoreBatteryOptimizations.request();
    }
    if (!await _requestPermissions()) return;
    await prefs.setBool(_tripKey, true);
    await WakelockPlus.enable();
    final LocationSettings settings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            foregroundNotificationConfig: ForegroundNotificationConfig(
              notificationTitle: 'Campus Bus Tracker',
              notificationText:
                  'Sharing Bus ${context.read<AuthService>().currentUser?.busNumber ?? ''} location',
              enableWakeLock: false,
              setOngoing: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
          );
    setState(() {
      _sharing = true;
      _message = null;
    });
    _subscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        _lastPosition = position;
        _publish(position);
        if (mounted) setState(() {});
      },
      onError: (_) {
        if (mounted)
          setState(
            () => _message =
                'GPS updates stopped. Check location settings and restart the trip.',
          );
      },
    );
  }

  Future<void> _retryQueuedLocations() async {
    if (_flushingQueue ||
        _queueSize == 0 ||
        (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)))
      return;
    final token = context.read<AuthService>().currentUser?.token;
    if (token == null) return;
    try {
      await _flushQueue(token);
      _retryAfter = null;
      _retryDelay = const Duration(seconds: 2);
      _connected = true;
      if (mounted) setState(() {});
    } catch (e) {
      if (e.toString().contains('SESSION_EXPIRED')) {
        if (mounted)
          setState(
            () => _message =
                'Session expired. Sign in again to send queued locations.',
          );
        await _stopStream();
        return;
      }
      _connected = false;
      _retryAfter = DateTime.now().add(_retryDelay);
      _retryDelay = Duration(
        seconds: (_retryDelay.inSeconds * 2).clamp(2, 60).toInt(),
      );
      if (mounted) setState(() {});
    }
  }

  Future<void> _publish(Position position) async {
    if (position.accuracy > 50) return;
    final now = DateTime.now();
    final last = _lastSentPosition;
    final moved = last == null
        ? true
        : Geolocator.distanceBetween(
                last.latitude,
                last.longitude,
                position.latitude,
                position.longitude,
              ) >=
              5;
    if (_lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(seconds: 3))
      return;
    if (!moved &&
        _lastSentAt != null &&
        now.difference(_lastSentAt!) < const Duration(seconds: 15))
      return;
    final auth = context.read<AuthService>();
    final user = auth.currentUser;
    final token = user?.token;
    final bus = user?.busNumber;
    if (token == null || bus == null) {
      setState(() => _message = 'Please sign in again to continue sharing.');
      return;
    }
    final payload = {
      'busNumber': bus,
      'lat': position.latitude,
      'lng': position.longitude,
      'speed': position.speed * 3.6,
      'heading': position.heading,
      'accuracy': position.accuracy,
      'status': position.speed * 3.6 < 1.5 ? 'idle' : 'running',
      'timestamp': now.toUtc().toIso8601String(),
    };
    try {
      while (_flushingQueue) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (!_connected && _retryAfter != null && now.isBefore(_retryAfter!)) {
        await _enqueue(payload);
        return;
      }
      await _flushQueue(token);
      if (_lastSentAt != null &&
          DateTime.now().difference(_lastSentAt!) <
              const Duration(seconds: 3)) {
        await _enqueue(payload);
        return;
      }
      await context.read<ApiService>().publishDriverLocation(token, payload);
      _lastSentAt = DateTime.now();
      _lastSentPosition = position;
      _connected = true;
      _retryAfter = null;
      _retryDelay = const Duration(seconds: 2);
      _message = null;
    } catch (e) {
      if (e.toString().contains('SESSION_EXPIRED')) {
        await _enqueue(payload);
        setState(
          () => _message = 'Session expired. Sign in again to resume sharing.',
        );
        await _stopStream();
        return;
      }
      _connected = false;
      _retryAfter = DateTime.now().add(_retryDelay);
      _retryDelay = Duration(
        seconds: (_retryDelay.inSeconds * 2).clamp(2, 60).toInt(),
      );
      await _enqueue(payload);
    }
    if (mounted) setState(() {});
  }

  Future<void> _enqueue(Map<String, dynamic> payload) async {
    final p = await SharedPreferences.getInstance();
    final queue = p.getStringList(_queueKey) ?? [];
    queue.add(jsonEncode(payload));
    while (queue.length > 200) {
      queue.removeAt(0);
    }
    await p.setStringList(_queueKey, queue);
    await _readQueue();
  }

  Future<void> _flushQueue(String token) async {
    if (_flushingQueue) {
      while (_flushingQueue) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _flushQueue(token);
    }
    _flushingQueue = true;
    try {
      final p = await SharedPreferences.getInstance();
      final queue = p.getStringList(_queueKey) ?? [];
      while (queue.isNotEmpty) {
        if (_lastSentAt != null) {
          final wait =
              const Duration(seconds: 3) -
              DateTime.now().difference(_lastSentAt!);
          if (wait > Duration.zero) await Future.delayed(wait);
        }
        await context.read<ApiService>().publishDriverLocation(
          token,
          Map<String, dynamic>.from(jsonDecode(queue.first)),
        );
        _lastSentAt = DateTime.now();
        queue.removeAt(0);
        await p.setStringList(_queueKey, queue);
      }
      await _readQueue();
    } finally {
      _flushingQueue = false;
    }
  }

  Future<void> _stopStream() async {
    await _subscription?.cancel();
    _subscription = null;
    await WakelockPlus.disable();
    if (mounted) setState(() => _sharing = false);
  }

  Future<void> _endTrip() async {
    final pos = _lastSentPosition ?? _lastPosition;
    final auth = context.read<AuthService>();
    final bus = auth.currentUser?.busNumber;
    final token = auth.currentUser?.token;
    if (pos != null && token != null && bus != null && pos.accuracy <= 50) {
      final finalFix = {
        'busNumber': bus,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed': 0,
        'heading': pos.heading,
        'accuracy': pos.accuracy,
        'status': 'idle',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      };
      try {
        await _flushQueue(token);
        if (_lastSentAt != null) {
          final wait =
              const Duration(seconds: 3) -
              DateTime.now().difference(_lastSentAt!);
          if (wait > Duration.zero) await Future.delayed(wait);
        }
        await context.read<ApiService>().publishDriverLocation(token, finalFix);
      } catch (_) {
        await _enqueue(finalFix);
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_tripKey, false);
    await _stopStream();
  }

  Future<void> _logout() async {
    await _endTrip();
    final auth = context.read<AuthService>();
    try {
      if (auth.currentUser?.token case final token?)
        await context.read<ApiService>().logout(token);
    } catch (_) {}
    await auth.logout();
    if (mounted)
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _uiTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthService>().currentUser;
    final accuracy = _lastPosition?.accuracy;
    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),
      appBar: AppBar(
        title: const Text('Driver trip'),
        actions: [
          IconButton(
            onPressed: _logout,
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.directions_bus)),
              title: Text(
                'Bus ${user?.busNumber ?? '—'}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(user?.name ?? 'Driver'),
              trailing: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    _sharing ? Icons.location_on : Icons.location_off,
                    size: 42,
                    color: _sharing ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _sharing ? 'Sharing location' : 'Trip not started',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _lastSentAt == null
                        ? 'Waiting for first GPS fix'
                        : 'Last sent ${DateTime.now().difference(_lastSentAt!).inSeconds}s ago',
                  ),
                  if (accuracy != null)
                    Text(
                      'GPS accuracy ±${accuracy.toStringAsFixed(0)}m · ${accuracy <= 20
                          ? 'Good'
                          : accuracy <= 50
                          ? 'Fair'
                          : 'Poor'}',
                    ),
                  Text(
                    _lastPosition == null
                        ? 'Speed —'
                        : 'Speed ${(_lastPosition!.speed * 3.6).toStringAsFixed(0)} km/h',
                  ),
                  Text(
                    'Connection: ${_connected ? 'Online' : 'Offline'} · queued fixes: $_queueSize',
                  ),
                ],
              ),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(_message!, style: const TextStyle(color: Colors.red)),
                  if (_message!.contains('Session expired'))
                    TextButton(
                      onPressed: () async {
                        await context.read<AuthService>().logout();
                        if (mounted)
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                      },
                      child: const Text('Sign in again'),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: _sharing ? _endTrip : _startTrip,
              icon: Icon(_sharing ? Icons.stop : Icons.play_arrow),
              label: Text(_sharing ? 'End Trip' : 'Start Trip'),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => showDialog(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Battery settings'),
                content: const Text(
                  'Some phones stop background GPS to save battery. Set Campus Bus Tracker to unrestricted battery use in system settings.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Later'),
                  ),
                  FilledButton(
                    onPressed: () async {
                      Navigator.pop(c);
                      await Permission.ignoreBatteryOptimizations.request();
                    },
                    child: const Text('Open settings'),
                  ),
                ],
              ),
            ),
            icon: const Icon(Icons.battery_saver),
            label: const Text('Battery optimization help'),
          ),
        ],
      ),
    );
  }
}
