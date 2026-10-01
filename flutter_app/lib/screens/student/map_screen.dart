import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../controllers/navigation_controller.dart';
import '../../services/maneuver_builder.dart';
import '../../widgets/route_preview_card.dart';
import '../../widgets/route_preview_sheet.dart';
import '../../widgets/navigation_banner.dart';
import '../../widgets/navigation_bottom_bar.dart';
import '../../widgets/bus_bottom_sheet.dart';
import '../../widgets/bus_search_bar.dart';
import '../../widgets/pulsing_dot_marker.dart';
import '../../services/campus_routing_service.dart';

import '../../models/bus_location.dart';
import '../../models/models.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/bus_service.dart';

enum MapLayer {
  street,
  dark,
  satellite,
  terrain,
}

class MapScreen extends StatefulWidget {
  final BusModel? selectedBus;

  const MapScreen({super.key, this.selectedBus});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with TickerProviderStateMixin {
  final Completer<GoogleMapController> _mapController =
      Completer<GoogleMapController>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<BusLocation> _fleet = [];
  double _mapZoom = 15;

  bool _isLoading = true;
  bool _isConnected = false;
  bool _isRefreshing = false;
  bool _followSelectedBus = true;
  bool _isFleetPanelOpen = false;
  String? _error;

  String? _selectedBusKey;
  String? _lastAutoCameraBusKey;
  DateTime? _lastUpdate;
  Timer? _pollTimer;
  LatLng? _lastFollowedPosition;
  final double _followMoveThresholdKm = 0.03; // ~30m
  // Routing state
  LatLng? _lastRouteOrigin; // origin used for last route fetch
  List<LatLng> _currentRoute = [];
  Set<Polyline> _routePolylines = {};
  Timer? _etaTimer;
  String _routeEtaText = '';
  double _routeRemainingKm = 0.0;
  // Marker animation state
  final Map<String, LatLng> _animatedPositions = {};
  final Map<String, AnimationController> _markerControllers = {};

  static const LatLng _defaultCenter = LatLng(23.7500, 92.7250);
  static final LatLngBounds _campusBounds = LatLngBounds(
    southwest: const LatLng(23.730, 92.700),
    northeast: const LatLng(23.810, 92.750),
  );

  static const Map<String, LatLng> _knownHostelCoordinates = {
    'BH1': LatLng(23.792917, 92.727789),
    'BH2': LatLng(23.794311, 92.728146),
    'BH3': LatLng(23.767378, 92.737712),
    'BH4': LatLng(23.769835, 92.737959),
    'GH1': LatLng(23.775578, 92.731044),
    'GH2': LatLng(23.784357, 92.728380),
    'MBSE': LatLng(23.749966, 92.722865),
    'Block 8': LatLng(23.751949, 92.727348),
  };

  static const LatLng _mbseCenter = LatLng(23.749966, 92.722865);
  static const double _campusMinLat = 23.730;
  static const double _campusMaxLat = 23.810;
  static const double _campusMinLng = 92.700;
  static const double _campusMaxLng = 92.750;
  static const double _minZoom = 13;
  static const double _maxZoom = 18;

  static const Map<String, Map<String, dynamic>> _stopDefinitions = {
    'BH1': {'label': 'BH1', 'lat': 23.792917, 'lng': 92.727789, 'type': 'boys'},
    'BH2': {'label': 'BH2', 'lat': 23.794311, 'lng': 92.728146, 'type': 'boys'},
    'BH3': {'label': 'BH3', 'lat': 23.767378, 'lng': 92.737712, 'type': 'boys'},
    'BH4': {'label': 'BH4', 'lat': 23.769835, 'lng': 92.737959, 'type': 'boys'},
    'GH1': {'label': 'GH1', 'lat': 23.775578, 'lng': 92.731044, 'type': 'girls'},
    'GH2': {'label': 'GH2', 'lat': 23.784357, 'lng': 92.728380, 'type': 'girls'},
    'MBSE': {'label': 'MBSE', 'lat': 23.749966, 'lng': 92.722865, 'type': 'academic'},
    'Block 8': {'label': 'Block 8', 'lat': 23.751949, 'lng': 92.727348, 'type': 'academic'},
  };

  static const String _darkMapStyle = '''[
    {"featureType":"all","elementType":"geometry","stylers":[{"color":"#1f2937"}]},
    {"featureType":"all","elementType":"labels.text.fill","stylers":[{"color":"#f3f4f6"}]},
    {"featureType":"all","elementType":"labels.text.stroke","stylers":[{"color":"#111827"},{"lightness":-25}]},
    {"featureType":"road","elementType":"geometry","stylers":[{"color":"#374151"}]},
    {"featureType":"road","elementType":"labels.icon","stylers":[{"visibility":"off"}]},
    {"featureType":"transit","elementType":"geometry","stylers":[{"color":"#4b5563"}]},
    {"featureType":"water","elementType":"geometry","stylers":[{"color":"#0f172a"}]},
    {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#111827"}]},
    {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#111827"}]}
  ]''';

  MapLayer _selectedMapLayer = MapLayer.street;
  final Map<String, LatLng> _lastBusPositions = {};
  final Map<String, DateTime> _lastBusSeenAt = {};
  final Map<String, int> _lastBusSpeedWindow = {};
  final CampusRoutingService _campusRouting = CampusRoutingService();
  final NavigationController _navigation = NavigationController();
  final FlutterTts _tts = FlutterTts();
  List<Maneuver> _maneuvers = [];
  int _maneuverIndex = 0;
  int _lastAnnouncedManeuver = -1;
  bool _poorGpsAccuracy = false;
  double _userHeading = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  Timer? _searchDebounce;
  List<String> _suggestions = [];
  StreamSubscription<Position>? _userPositionSubscription;
  LatLng? _userPosition;
  bool _trackingUser = false;
  bool _routeLoading = false;
  LatLng? _lastRouteBusPosition;
  LatLng? _lastOsrmOrigin;
  LatLng? _lastOsrmDestination;
  Timer? _routeUpdateTimer;
  double _userAccuracyMeters = 0;
  bool _cameraCommandActive = false;
  bool _isRerouting = false;
  Timer? _pulseTimer;
  bool _pulseExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedBus != null) {
      _selectedBusKey = _busKey('Bus ${widget.selectedBus!.busNumber}');
    }
    _navigation.addListener(_onNavigationChanged);
    _configureTts();
    _bootstrap();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 650), (_) {
      if (mounted && _fleet.any(_running)) setState(() => _pulseExpanded = !_pulseExpanded);
    });
    // ETA updater: cheap, runs every 1s (no network)
    _etaTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateEta());
  }

  void _onNavigationChanged() { if (mounted) setState(() {}); }

  Future<void> _configureTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _etaTimer?.cancel();
    _searchDebounce?.cancel();
    _routeUpdateTimer?.cancel();
    _pulseTimer?.cancel();
    _userPositionSubscription?.cancel();
    _navigation.removeListener(_onNavigationChanged);
    _navigation.dispose();
    _tts.stop();
    WakelockPlus.disable();
    _searchController.dispose();
    _searchFocusNode.dispose();
    // dispose any running animation controllers
    for (final c in _markerControllers.values) {
      c.stop();
      c.dispose();
    }
    super.dispose();
  }

  void _animateMarker(String key, LatLng from, LatLng to) {
    // stop existing
    final existing = _markerControllers[key];
    existing?.stop();
    existing?.dispose();

    final controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _markerControllers[key] = controller;

    controller.addListener(() {
      final t = controller.value;
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;
      _animatedPositions[key] = LatLng(lat, lng);
      // lightweight update — only markers change visually
      setState(() {});
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
        _animatedPositions[key] = to;
        controller.dispose();
        _markerControllers.remove(key);
      }
    });
    controller.forward();
  }

  Future<void> _bootstrap() async {
    await _syncFleet();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncFleet());
  }

  Future<void> _syncFleet({bool silent = false, bool showToast = false}) async {
    if (!mounted) return;

    final api = context.read<ApiService>();
    final auth = context.read<AuthService>();
    final busService = context.read<BusService>();

    try {
      if (!silent) {
        setState(() => _isLoading = true);
      }
      if (showToast) {
        setState(() => _isRefreshing = true);
      }

      final busesData = await api.getBuses(
        hostel: auth.isAdmin ? null : auth.currentUser?.hostelId,
        token: auth.currentUser?.token,
      );

      var fleet = busesData
          .whereType<Map<String, dynamic>>()
          .map(_fromBusJson)
          .toList();

      final latest = await ApiService.fetchLatestLocation();
      if (latest != null) {
        fleet = _mergeLatestTelemetry(fleet, latest);
      }

      if (fleet.isEmpty) {
        fleet = busService.buses.map((b) {
          return BusLocation(
            busId: 'Bus ${b.busNumber}',
            deviceId: 'device-${b.busNumber}',
            lat: b.latitude,
            lng: b.longitude,
            speed: b.speed,
            accuracy: 1.0,
            status: b.status,
            timestamp: DateTime.now(),
          );
        }).toList();
      }

      final selectedKey = _selectedBusKey ??
          (widget.selectedBus != null
              ? _busKey('Bus ${widget.selectedBus!.busNumber}')
              : (fleet.isNotEmpty ? _busKey(fleet.first.busId) : null));

      final selectedBus = _findByKey(fleet, selectedKey);
        if (_followSelectedBus && selectedBus != null) {
          final shouldRecenter = _lastAutoCameraBusKey != selectedKey;
          final newPos = LatLng(selectedBus.lat, selectedBus.lng);
          final lastPos = _lastFollowedPosition;
          // Recenter if the selected bus changed, or it moved more than threshold
          final movedEnough = lastPos == null ? true : _distanceKm(lastPos, newPos) >= _followMoveThresholdKm;
          if (shouldRecenter || movedEnough) {
            _lastAutoCameraBusKey = selectedKey;
            _lastFollowedPosition = newPos;
            // use immediate move for frequent updates to avoid animation buffering
            await _moveCameraTo(newPos, zoom: _mapZoom);
          }
        } else {
          _lastAutoCameraBusKey = null;
          _lastFollowedPosition = null;
        }

      for (final bus in fleet) {
        final key = _busKey(bus.busId);
        final current = LatLng(bus.lat, bus.lng);
        final prev = _lastBusPositions[key];
        if (prev != null) {
          final moved = _distanceKm(prev, current) > 0.001;
          if (moved) {
            // animate marker from prev -> current (cheap, local)
            _animateMarker(key, prev, current);
            _lastBusPositions[key] = current;
            _lastBusSeenAt[key] = bus.timestamp;
          }
        } else {
          // initialize animated position
          _animatedPositions[key] = current;
          _lastBusPositions[key] = current;
          _lastBusSeenAt[key] = bus.timestamp;
        }
        _lastBusSpeedWindow[key] = bus.speed.round();
      }

      if (!mounted) return;
      setState(() {
        _fleet = fleet;
        _selectedBusKey = selectedKey;
        _isLoading = false;
        _isRefreshing = false;
        _isConnected = latest != null;
        _error = null;
        _lastUpdate = DateTime.now();
      });

      if (showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bus data refreshed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _isConnected = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });

      if (showToast || true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Refresh failed: ${_error ?? 'Unable to load bus data'}'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  BusLocation _fromBusJson(Map<String, dynamic> bus) {
    final number = bus['busNumber']?.toString() ?? 'Unknown';
    final rawTimestamp = bus['lastUpdated'] ?? bus['received_at'] ?? bus['timestamp'];
    final busTimestamp = rawTimestamp == null
        ? (bus.containsKey('lastUpdated') ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.now())
        : (DateTime.tryParse(rawTimestamp.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0));
    return BusLocation(
      busId: 'Bus $number',
      deviceId: (bus['deviceId'] ?? 'device-$number').toString(),
      assignedHostel: (bus['assignedHostel'] ?? bus['assigned_hostel'] ?? '').toString(),
      lat: ((bus['latitude'] ?? bus['lat'] ?? 23.7271) as num).toDouble(),
      lng: ((bus['longitude'] ?? bus['lng'] ?? 92.7176) as num).toDouble(),
      speed: ((bus['speed'] ?? 0) as num).toDouble(),
      accuracy: ((bus['accuracy'] ?? bus['hdop'] ?? 1.0) as num).toDouble(),
      status: (bus['status'] ?? 'idle').toString(),
      timestamp: busTimestamp,
    );
  }

  List<BusLocation> _mergeLatestTelemetry(List<BusLocation> fleet, BusLocation latest) {
    final latestKey = _busKey(latest.busId);
    final index = fleet.indexWhere((bus) => _busKey(bus.busId) == latestKey);

    if (index == -1) {
      return [...fleet, latest];
    }

    final previous = fleet[index];
    final next = List<BusLocation>.from(fleet);
    next[index] = BusLocation(
      busId: latest.busId,
      deviceId: latest.deviceId,
      assignedHostel: previous.assignedHostel,
      lat: latest.lat,
      lng: latest.lng,
      speed: latest.speed,
      accuracy: latest.accuracy,
      status: latest.status,
      timestamp: latest.timestamp,
    );
    return next;
  }

  String _busKey(String busId) {
    final digits = busId.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? busId : digits;
  }

  BusLocation? _findByKey(List<BusLocation> fleet, String? key) {
    if (key == null) return null;
    for (final bus in fleet) {
      if (_busKey(bus.busId) == key) return bus;
    }
    return null;
  }

  void _toggleFleetPanel() {
    setState(() {
      _isFleetPanelOpen = !_isFleetPanelOpen;
    });
  }

  LatLng _clampToCampus(LatLng point) {
    return LatLng(
      point.latitude.clamp(_campusMinLat, _campusMaxLat),
      point.longitude.clamp(_campusMinLng, _campusMaxLng),
    );
  }

  double _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * pi / 180;
    final lat2 = to.latitude * pi / 180;
    final dLon = (to.longitude - from.longitude) * pi / 180;

    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    final angle = atan2(y, x) * 180 / pi;
    return (angle + 360) % 360;
  }

  LatLng? _getHostelCoordinates(String hostel) {
    return _knownHostelCoordinates[hostel];
  }

  double _distanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final lat1 = a.latitude * (pi / 180);
    final lat2 = b.latitude * (pi / 180);
    final dLat = lat2 - lat1;
    final dLng = (b.longitude - a.longitude) * (pi / 180);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(h));
  }

  String _routeLabel(BusLocation bus) {
    if (bus.assignedHostel.isEmpty) return 'Hostel ↔ MBSE';
    return 'Hostel ↔ ${bus.assignedHostel}';
  }

  MapType get _mapType {
    switch (_selectedMapLayer) {
      case MapLayer.street:
        return MapType.normal;
      case MapLayer.dark:
        return MapType.normal;
      case MapLayer.satellite:
        return MapType.hybrid;
      case MapLayer.terrain:
        return MapType.terrain;
    }
  }

  Future<void> _applyMapStyle() async {
    return;
  }

  Future<void> _moveCameraTo(LatLng target, {double? zoom, bool animate = true}) async {
    if (!_mapController.isCompleted) return;
    final controller = await _mapController.future;
    final finalZoom = zoom ?? _mapZoom;
    final update = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: _clampToCampus(target),
        zoom: finalZoom,
      ),
    );
    if (animate) {
      await controller.animateCamera(update);
    } else {
      // use immediate move to avoid animation buffering during frequent updates
      await controller.moveCamera(update);
    }
  }

  void _handleSearchQuery(String text) {
    final query = text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
    if (query.isEmpty) return;
    final bus = _fleet.where((item) {
      final id = item.busId.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      final number = _busKey(item.busId).toLowerCase();
      final cleaned = query.replaceFirst('bus', '');
      return id.contains(query) || number.contains(cleaned);
    }).firstOrNull;
    if (bus != null) { _chooseBus(bus); return; }
    final stop = _stopDefinitions.keys.where((item) =>
        item.toLowerCase().replaceAll(RegExp(r'\s+'), '') == query).firstOrNull;
    if (stop != null) { _chooseStop(stop); return; }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No bus or stop found for "$text"')));
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    try {
      await _syncFleet(silent: true, showToast: true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refresh failed. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
   
  Future<void> _onMapCreated(GoogleMapController controller) async {
    _mapController.complete(controller);
    await _applyMapStyle();
    final selected = _findByKey(_fleet, _selectedBusKey);
    if (selected != null) {
      await _moveCameraTo(LatLng(selected.lat, selected.lng), zoom: _mapZoom);
    }
  }

  void _buildRoutePolylines() {
    // create two polylines for glow + main line
    final glow = Polyline(
      polylineId: const PolylineId('route_glow'),
      points: _currentRoute,
      color: _navigation.mode == MapMode.navigating ? const Color(0x4422D3EE) : const Color(0xFFF8FAFC),
      width: 10,
      startCap: Cap.roundCap, endCap: Cap.roundCap, jointType: JointType.round,
      geodesic: true,
    );

    final main = Polyline(
      polylineId: const PolylineId('route_main'),
      points: _currentRoute,
      color: _navigation.mode == MapMode.navigating ? const Color(0xFF22D3EE) : const Color(0xFF4F46E5),
      width: 7,
      startCap: Cap.roundCap, endCap: Cap.roundCap, jointType: JointType.round,
      geodesic: true,
    );

    _routePolylines = {glow, main};
    // update map polylines with minimal setState (only polylines)
    setState(() {});
  }

  // Cheap: update ETA and remaining distance every 1s without network
  void _updateEta() {
    if (_currentRoute.isEmpty) {
      _routeEtaText = '';
      _routeRemainingKm = 0.0;
      if (mounted && _trackingUser) { setState(() {}); _updateNavigationProgress(); }
      return;
    }
    final bus = _findByKey(_fleet, _selectedBusKey);
    if (bus == null) return;
    if (!_trackingUser) _trimRouteToCurrentPosition(LatLng(bus.lat, bus.lng));
    double km = 0.0;
    for (var i = 0; i < _currentRoute.length - 1; i++) {
      km += _distanceKm(_currentRoute[i], _currentRoute[i + 1]);
    }
    _routeRemainingKm = km;
    final estimateSpeed = switch (_navigation.travelMode) { RouteTravelMode.walk => 5.0, RouteTravelMode.bike => 15.0, RouteTravelMode.drive => 25.0 };
    _routeEtaText = '${(km / estimateSpeed * 60).round()} min';
    _navigation.setSummary(_routeEtaText, '${(km * 1000).round()} m');
    if (mounted && _trackingUser) { setState(() {}); _updateNavigationProgress(); }
  }

  // cheap: trim the current route to the point nearest to `pos` and drop earlier points
  void _trimRouteToCurrentPosition(LatLng pos) {
    if (_currentRoute.isEmpty) return;
    int bestIdx = 0;
    double bestDist = double.infinity;
    for (var i = 0; i < _currentRoute.length; i++) {
      final d = _distanceKm(pos, _currentRoute[i]);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
      }
    }
    if (bestIdx > 0) {
      _currentRoute = _currentRoute.sublist(bestIdx);
      _buildRoutePolylines();
    }
  }

  bool _isStale(BusLocation bus) => DateTime.now().difference(bus.timestamp) > const Duration(seconds: 120);

  bool _running(BusLocation bus) => !_isStale(bus) && (bus.speed > 2 ||
      const {'running', 'active', 'moving'}.contains(bus.status.toLowerCase()));

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final query = value.toLowerCase().replaceAll(RegExp(r'\s+'), '');
      setState(() {
        _suggestions = query.isEmpty ? [] : [
          ..._fleet.where((bus) {
            final id = bus.busId.toLowerCase().replaceAll(RegExp(r'\s+'), '');
            final number = _busKey(bus.busId).toLowerCase();
            final cleaned = query.replaceFirst('bus', '');
            return id.contains(query) || number.contains(cleaned);
          }).map((bus) => 'bus:${bus.busId}'),
          ..._stopDefinitions.keys.where((stop) =>
              stop.toLowerCase().replaceAll(RegExp(r'\s+'), '').contains(query))
              .map((stop) => 'stop:$stop'),
        ].take(8).toList();
      });
    });
  }

  Future<void> _chooseBus(BusLocation bus) async {
    setState(() {
      _selectedBusKey = _busKey(bus.busId);
      _suggestions = [];
      _followSelectedBus = false;
    });
    _searchController.text = bus.busId;
    _searchFocusNode.unfocus();
    await _moveCameraTo(LatLng(bus.lat, bus.lng), zoom: 16);
    if (mounted) _showBusDetails(bus);
  }

  void _chooseStop(String name) {
    final stop = _stopDefinitions[name]!;
    final point = LatLng((stop['lat'] as num).toDouble(), (stop['lng'] as num).toDouble());
    setState(() {
      _selectedBusKey = null;
      _suggestions = [];
    });
    _searchController.text = name;
    _searchFocusNode.unfocus();
    _moveCameraTo(point, zoom: 16);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Row(children: [
          const Icon(Icons.place, color: Color(0xFF2563EB)),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: Theme.of(context).textTheme.titleMedium)),
          FilledButton(onPressed: () {
            Navigator.pop(context);
            if (_fleet.isEmpty) return;
            final bus = _fleet.reduce((a, b) => _distanceKm(point, LatLng(a.lat, a.lng)) < _distanceKm(point, LatLng(b.lat, b.lng)) ? a : b);
            _chooseBus(bus);
          }, child: const Text('Find buses')),
        ]),
      )),
    );
  }

  void _showBusDetails(BusLocation bus) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: .34, minChildSize: .20, maxChildSize: .85,
        snap: true, snapSizes: const [.20, .45, .85],
        builder: (context, controller) {
          final running = _running(bus);
          final number = int.tryParse(_busKey(bus.busId));
          final busModel = context.read<BusService>().buses.where((item) => item.busNumber == number).firstOrNull;
          return BusBottomSheet(
            scrollController: controller, bus: bus, route: _routeLabel(bus),
            updated: _lastUpdate == null ? 'just now' : _timeAgo(_lastUpdate!),
            running: running, nextStop: running && bus.assignedHostel.isNotEmpty ? '${bus.assignedHostel} · ${_nextStopEta(bus)}' : '',
            schedule: busModel?.schedule == null ? '' : '${busModel!.schedule!.fromHostelTime} from hostel · ${busModel.schedule!.fromMBSETime} from MBSE',
            driverName: busModel?.driver?.name ?? '', driverPhone: busModel?.driver?.phone,
            showAdvanced: context.read<AuthService>().isAdmin, tracking: _trackingUser,
            onCall: busModel?.driver == null ? null : () => _callDriver(busModel!.driver!.phone),
            onDirections: () { Navigator.of(context).pop(); _openRoutePreview(bus); },
            onStop: () { _stopUserTracking(); _navigation.browse(); },
          );
        },
      ),
    );
  }

  Future<void> _openRoutePreview(BusLocation bus) async {
    setState(() {
      _selectedBusKey = _busKey(bus.busId);
      _isFleetPanelOpen = false;
      _suggestions = [];
    });
    _navigation.showPreview();
    await _startTracking(bus);
    if (!mounted) return;
    if (_userPosition == null) { _navigation.browse(); return; }
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: .36, minChildSize: .25, maxChildSize: .72,
        snap: true, snapSizes: const [.25, .5, .72],
        builder: (context, controller) {
          final selected = _findByKey(_fleet, _selectedBusKey);
          return SingleChildScrollView(controller: controller, child: RoutePreviewSheet(
            controller: _navigation,
            busName: selected?.busId ?? bus.busId,
            eta: _routeEtaText.isEmpty ? 'Calculating…' : _routeEtaText,
            distance: '${(_routeRemainingKm * 1000).round()} m',
            busEta: _nextStopEta(bus),
            speed: (selected?.speed ?? bus.speed).toStringAsFixed(0),
            onStart: () { Navigator.of(sheetContext).pop(); _enterNavigation(); },
            onClose: () { Navigator.of(sheetContext).pop(); _navigation.browse(); _stopUserTracking(); },
            onShare: _shareEta,
          ));
        },
      ),
    );
  }

  Future<void> _enterNavigation() async {
    _navigation.start();
    await WakelockPlus.enable();
    final user = _userPosition;
    if (user != null && _mapController.isCompleted) {
      await _animateNavigationCamera(user);
    }
    _updateNavigationProgress();
  }

  Future<void> _endNavigation() async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('End navigation?'), content: const Text('You can start a new route at any time.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep navigating')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('End'))],
    ));
    if (confirmed != true || !mounted) return;
    await _stopUserTracking();
    _navigation.browse();
    await WakelockPlus.disable();
  }

  Future<void> _shareEta() async {
    final bus = _findByKey(_fleet, _selectedBusKey);
    final text = '${bus?.busId ?? 'Campus bus'} · ${_routeEtaText.isEmpty ? 'ETA unavailable' : '$_routeEtaText away'}';
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _reportIssue() async {
    final controller = TextEditingController();
    final report = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Report a bus issue'),
      content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'Describe a delay or issue')),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Send'))],
    ));
    controller.dispose();
    if (report != null && report.trim().isNotEmpty && mounted) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('bus_issue_reports') ?? <String>[];
      saved.add('${DateTime.now().toIso8601String()}|${_selectedBusKey ?? 'bus'}|${report.trim()}');
      await prefs.setStringList('bus_issue_reports', saved);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks. Your report has been saved for review.')));
    }
  }

  void _updateNavigationProgress() {
    if (_navigation.mode != MapMode.navigating || _userPosition == null || _maneuvers.isEmpty) return;
    final maneuver = _maneuvers[_maneuverIndex.clamp(0, _maneuvers.length - 1)];
    final meters = _distanceKm(_userPosition!, maneuver.point) * 1000;
    if (meters <= 25) {
      _navigation.arrive();
      if (!_navigation.muted) _tts.speak('You have arrived');
    } else if (meters <= 200 && _lastAnnouncedManeuver != _maneuverIndex) {
      if (!_navigation.muted) _tts.speak('In ${meters.round()} meters, ${maneuver.instruction.toLowerCase()} onto ${maneuver.roadName}');
      _lastAnnouncedManeuver = _maneuverIndex;
      if (_maneuverIndex < _maneuvers.length - 1) _maneuverIndex++;
    }
    if (_navigation.following && _mapController.isCompleted) {
      _animateNavigationCamera(_userPosition!);
    }
  }

  Future<void> _startTracking(BusLocation bus) async {
    final accepted = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Track a route to this bus?'),
      content: const Text('Your location is used to show a route from you to the selected bus.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))],
    ));
    if (accepted != true || !mounted) return;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (context) => AlertDialog(
        title: const Text('Location permission needed'),
        content: const Text('Enable location access in Settings to track a route to the bus.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(onPressed: () { Navigator.pop(context); openAppSettings(); }, child: const Text('Open settings'))],
      ));
      return;
    }
    if (permission == LocationPermission.denied) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission was not granted.')));
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Turn on location services to start tracking.'),
        action: SnackBarAction(label: 'Settings', onPressed: Geolocator.openLocationSettings),
      ));
      return;
    }
    await _userPositionSubscription?.cancel();
    setState(() { _trackingUser = true; _routeLoading = true; });
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final latest = _findByKey(_fleet, _selectedBusKey);
      if (_trackingUser && latest != null) _updateUserRoute(latest);
    });
    _userPositionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 3),
    ).listen((position) {
      _userPosition = LatLng(position.latitude, position.longitude);
      _userAccuracyMeters = position.accuracy;
      _poorGpsAccuracy = position.accuracy > 50;
      _userHeading = position.heading;
      _updateUserRoute(bus);
      _updateNavigationProgress();
    });
    try {
      final position = await Geolocator.getCurrentPosition();
      _userPosition = LatLng(position.latitude, position.longitude);
      _userAccuracyMeters = position.accuracy;
      _poorGpsAccuracy = position.accuracy > 50;
      _userHeading = position.heading;
      await _updateUserRoute(bus);
      _updateNavigationProgress();
    } catch (_) {
      if (mounted) setState(() => _routeLoading = false);
    }
  }

  Future<void> _updateUserRoute(BusLocation bus) async {
    final origin = _userPosition;
    if (origin == null || !mounted) return;
    final destination = LatLng(bus.lat, bus.lng);
    final previous = _lastRouteOrigin;
    final previousBus = _lastRouteBusPosition;
    if (_navigation.mode == MapMode.navigating && _currentRoute.isNotEmpty && _distanceToRouteMeters(origin, _currentRoute) > 40) {
      _isRerouting = true;
      if (mounted) setState(() {});
    }
    if (previous != null && previousBus != null &&
        _distanceKm(previous, origin) < .005 && _distanceKm(previousBus, destination) < .005) return;
    _lastRouteOrigin = origin;
    _lastRouteBusPosition = destination;
    var points = await _campusRouting.route(origin, destination, allowFallback: false);
    final fallbackOrigin = _lastOsrmOrigin;
    final fallbackDestination = _lastOsrmDestination;
    final movedForFallback = fallbackOrigin == null || fallbackDestination == null ||
        _distanceKm(fallbackOrigin, origin) > .06 || _distanceKm(fallbackDestination, destination) > .06;
    if (points.isEmpty && movedForFallback) {
      _lastOsrmOrigin = origin;
      _lastOsrmDestination = destination;
      points = await _campusRouting.route(origin, destination);
    }
    if (!mounted) return;
    _currentRoute = points;
    _isRerouting = false;
    _maneuvers = buildManeuvers(points);
    _maneuverIndex = 0;
    _lastAnnouncedManeuver = -1;
    _routeLoading = false;
    _buildRoutePolylines();
    double km = 0;
    for (var i = 0; i + 1 < points.length; i++) km += _distanceKm(points[i], points[i + 1]);
    _routeRemainingKm = km;
    final minutes = bus.speed > 1 ? km / bus.speed * 60 : km / 20 * 60;
    _routeEtaText = '${minutes.round()} min';
    if (_mapController.isCompleted && _navigation.mode != MapMode.navigating) {
      final map = await _mapController.future;
      await map.animateCamera(CameraUpdate.newLatLngBounds(LatLngBounds(
        southwest: LatLng(min(origin.latitude, destination.latitude), min(origin.longitude, destination.longitude)),
        northeast: LatLng(max(origin.latitude, destination.latitude), max(origin.longitude, destination.longitude)),
      ), 100));
    }
  }

  Future<void> _stopUserTracking() async {
    await _userPositionSubscription?.cancel();
    _userPositionSubscription = null;
    _routeUpdateTimer?.cancel();
    _routeUpdateTimer = null;
    if (!mounted) return;
    setState(() {
      _trackingUser = false;
      _userPosition = null;
      _currentRoute = [];
      _routePolylines = {};
      _lastRouteOrigin = null;
      _lastRouteBusPosition = null;
    });
  }

  Widget _statusChip(String text, bool running) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: (running ? const Color(0xFF16A34A) : const Color(0xFF64748B)).withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: TextStyle(color: running ? const Color(0xFF15803D) : const Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
  );

  String _timeAgo(DateTime time) {
    final seconds = DateTime.now().difference(time).inSeconds;
    if (seconds < 5) return 'just now';
    if (seconds < 60) return '${seconds}s ago';
    return '${seconds ~/ 60}m ago';
  }

  String _nextStopEta(BusLocation bus) {
    final target = _getHostelCoordinates(bus.assignedHostel);
    if (target == null) return 'timing unavailable';
    final km = _distanceKm(LatLng(bus.lat, bus.lng), target);
    final speed = bus.speed > 1 ? bus.speed : 20.0;
    return '${(km / speed * 60).ceil()} min';
  }

  Future<void> _callDriver(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (phone.isEmpty || !await launchUrl(uri)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver contact is unavailable.')));
    }
  }

  void _changeZoom(double delta) {
    final selected = _findByKey(_fleet, _selectedBusKey);
    final target = selected == null ? _defaultCenter : LatLng(selected.lat, selected.lng);
    _mapZoom = (_mapZoom + delta).clamp(_minZoom, _maxZoom);
    _moveCameraTo(target, zoom: _mapZoom);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _findByKey(_fleet, _selectedBusKey);
    final selectedKey = _selectedBusKey;
    final markers = <Marker>{};
    final circles = <Circle>{};
    if (_userPosition != null) {
      circles.add(Circle(circleId: const CircleId('user_accuracy'), center: _userPosition!, radius: _userAccuracyMeters,
        fillColor: const Color(0x332563EB), strokeColor: const Color(0x662563EB), strokeWidth: 1));
    }
    for (final entry in _stopDefinitions.entries) {
      final data = entry.value;
      markers.add(Marker(
        markerId: MarkerId('stop_${entry.key}'),
        position: LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble()),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        onTap: () => _chooseStop(entry.key),
        infoWindow: InfoWindow(title: entry.key),
      ));
    }
    for (final bus in _fleet) {
      final key = _busKey(bus.busId);
      final point = _animatedPositions[key] ?? LatLng(bus.lat, bus.lng);
      final isSelected = selectedKey == key;
      if (isSelected) {
        final previous = _lastBusPositions[key] ?? point;
        markers.add(Marker(
          markerId: MarkerId('bus_$key'), position: point,
          rotation: _bearingBetween(previous, LatLng(bus.lat, bus.lng)),
          icon: _isStale(bus) ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(_navigation.mode == MapMode.routePreview ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure),
          anchor: const Offset(.5, .5), onTap: () => _showBusDetails(bus),
          infoWindow: InfoWindow(title: bus.busId),
        ));
      } else {
        circles.addAll(PulsingDotMarker.build(id: 'bus_$key', position: point, running: _running(bus), expanded: _pulseExpanded, onTap: () => _chooseBus(bus)));
      }
    }
    if (_userPosition != null) {
      markers.add(Marker(markerId: const MarkerId('user'), position: _userPosition!, rotation: _userHeading, flat: true, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), zIndexInt: 10));
    }
    if (_navigation.mode == MapMode.routePreview && _currentRoute.length > 1) {
      final midpoint = _currentRoute[_currentRoute.length ~/ 2];
      markers.add(Marker(markerId: const MarkerId('route_eta'), position: midpoint, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure), infoWindow: InfoWindow(title: _routeEtaText)));
    }
    final theme = Theme.of(context);
    return Scaffold(
      key: _scaffoldKey,
      body: Stack(children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: selected == null ? _defaultCenter : LatLng(selected.lat, selected.lng), zoom: _mapZoom),
          mapType: _mapType,
          style: (_navigation.mode == MapMode.navigating || _selectedMapLayer == MapLayer.dark || Theme.of(context).brightness == Brightness.dark || DateTime.now().hour >= 18) ? _darkMapStyle : null,
          markers: markers,
          circles: circles,
          polylines: {..._routePolylines},
          minMaxZoomPreference: const MinMaxZoomPreference(_minZoom, _maxZoom),
          cameraTargetBounds: CameraTargetBounds(_campusBounds),
          rotateGesturesEnabled: true, tiltGesturesEnabled: false,
          onMapCreated: _onMapCreated,
          onCameraMove: (position) => _mapZoom = position.zoom.clamp(_minZoom, _maxZoom),
          onCameraMoveStarted: () { if (_navigation.mode == MapMode.navigating && !_cameraCommandActive) _navigation.setFollowing(false); },
          onTap: (_) { _searchFocusNode.unfocus(); setState(() => _suggestions = []); },
        ),
        if (_navigation.mode == MapMode.browse) Positioned(left: 12, right: 12, top: MediaQuery.paddingOf(context).top + 8, child: BusSearchBar(
          controller: _searchController, focusNode: _searchFocusNode,
          connected: _isConnected, refreshing: _isRefreshing,
          onChanged: _onSearchChanged, onSubmitted: _handleSearchQuery,
          onMenu: _toggleFleetPanel, onRefresh: _handleRefresh,
          suggestions: _suggestionDropdown(),
        )),
        if (_navigation.mode == MapMode.routePreview && selected != null && _userPosition != null) Positioned(left: 12, right: 12, top: MediaQuery.paddingOf(context).top + 8, child: RoutePreviewCard(
          origin: 'Your location', destination: selected.busId, onChangeDestination: _showSearch,
          onSwap: null, onMore: _showLayerChooser,
        )),
        if (_navigation.mode == MapMode.navigating) Positioned(left: 12, right: 12, top: MediaQuery.paddingOf(context).top + 8, child: NavigationBanner(
          maneuver: _maneuvers.isEmpty ? null : _maneuvers[_maneuverIndex.clamp(0, _maneuvers.length - 1)],
          distance: _poorGpsAccuracy ? 'Weak GPS · accuracy ${_userAccuracyMeters.round()} m' : _nextTurnDistance(), rerouting: _isRerouting,
        )),
        if (_navigation.mode != MapMode.navigating && _isFleetPanelOpen) Positioned.fill(child: GestureDetector(onTap: _toggleFleetPanel, child: Container(color: Colors.black26))),
        if (_navigation.mode != MapMode.navigating) AnimatedPositioned(duration: const Duration(milliseconds: 220), left: _isFleetPanelOpen ? 0 : -330, top: 0, bottom: 0, width: 320,
          child: Material(color: theme.colorScheme.surface, elevation: 12, child: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(leading: const Icon(Icons.directions_bus), title: const Text('Campus buses', style: TextStyle(fontWeight: FontWeight.bold)), trailing: IconButton(onPressed: _toggleFleetPanel, icon: const Icon(Icons.close))),
            Expanded(child: _isLoading && _fleet.isEmpty ? const Center(child: CircularProgressIndicator()) : _fleet.isEmpty ? const Center(child: Text('No buses running right now')) : ListView.builder(itemCount: _fleet.length, itemBuilder: (context, index) {
              final bus = _fleet[index]; final running = _running(bus);
              return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5), child: ListTile(leading: const CircleAvatar(child: Icon(Icons.directions_bus)), title: Text(bus.busId, style: const TextStyle(fontWeight: FontWeight.w700)), subtitle: Text('${_routeLabel(bus)}\n${running ? 'Moving at ${bus.speed.toStringAsFixed(0)} km/h' : 'Parked'}'), isThreeLine: true, trailing: _statusChip(running ? 'Running' : 'Idle', running), onTap: () { _toggleFleetPanel(); _chooseBus(bus); }));
            })),
          ])))),
        if (_navigation.mode != MapMode.navigating) Positioned(right: 12, bottom: 20, child: Column(children: [
          FloatingActionButton.small(heroTag: 'layer', onPressed: _showLayerChooser, child: const Icon(Icons.layers_outlined)),
          const SizedBox(height: 10), FloatingActionButton.small(heroTag: 'compass', onPressed: () => _moveCameraTo(_defaultCenter, zoom: _mapZoom), child: const Icon(Icons.explore_outlined)),
          const SizedBox(height: 10), FloatingActionButton.small(heroTag: 'zoom_in', onPressed: () => _changeZoom(1), child: const Icon(Icons.add)),
          const SizedBox(height: 10), FloatingActionButton.small(heroTag: 'zoom_out', onPressed: () => _changeZoom(-1), child: const Icon(Icons.remove)),
          const SizedBox(height: 10), FloatingActionButton(heroTag: 'my_location', onPressed: () { final target = selected == null ? _defaultCenter : LatLng(selected.lat, selected.lng); _moveCameraTo(target, zoom: 16); }, child: const Icon(Icons.my_location)),
        ])),
        if (_navigation.mode == MapMode.routePreview) Positioned(right: 16, top: MediaQuery.paddingOf(context).top + 70, child: FloatingActionButton.small(heroTag: 'preview_layers', onPressed: _showLayerChooser, child: const Icon(Icons.layers_outlined))),
        if (_navigation.mode == MapMode.navigating) Positioned(right: 12, top: MediaQuery.sizeOf(context).height * .32, child: Column(children: [
          _navControl(Icons.explore, 'Reset north', () { _userHeading = 0; _recenterUser(); }),
          _navControl(Icons.search, 'Search', _showSearch),
          _navControl(_navigation.muted ? Icons.volume_off : Icons.volume_up, 'Toggle voice', () => _navigation.toggleMute()),
          _navControl(Icons.map_outlined, 'Route overview', _fitRoute),
        ])),
        if (_navigation.mode == MapMode.navigating && !_navigation.following) Positioned(left: 16, bottom: 110, child: FilledButton.icon(onPressed: _recenterUser, icon: const Icon(Icons.my_location), label: const Text('Re-centre'))),
        if (_navigation.mode == MapMode.navigating) Positioned(right: 18, bottom: 112, child: ActionChip(label: const Text('Report'), onPressed: _reportIssue)),
        if (_navigation.mode == MapMode.navigating) Positioned(left: 0, right: 0, bottom: 0, child: NavigationBottomBar(
          eta: _routeEtaText.isEmpty ? '--' : _routeEtaText, distance: '${(_routeRemainingKm * 1000).round()} m',
          arrival: _arrivalClock(), onEnd: _endNavigation, onShare: _shareEta,
        )),
        if (_navigation.mode == MapMode.arrived) Positioned(left: 20, right: 20, bottom: 100, child: Card(child: ListTile(leading: const Icon(Icons.check_circle, color: Colors.green), title: const Text('Arrived'), trailing: TextButton(onPressed: _endNavigation, child: const Text('Done'))))),
        if (!_isConnected && !_isLoading) Positioned(left: 12, right: 76, bottom: 20, child: Material(color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(12), child: Text('Connection lost · showing last known locations', style: TextStyle(color: theme.colorScheme.onErrorContainer))))),
        if (_isLoading && _fleet.isEmpty) Positioned(top: MediaQuery.paddingOf(context).top + 68, left: 24, right: 24, child: ClipRRect(borderRadius: BorderRadius.circular(8), child: const LinearProgressIndicator(minHeight: 3))),
        if (!_isLoading && _fleet.isEmpty) Positioned(top: MediaQuery.paddingOf(context).top + 72, left: 28, right: 28, child: Card(child: const Padding(padding: EdgeInsets.all(14), child: Text('No buses running right now', textAlign: TextAlign.center)))),
        if (_trackingUser && _routeEtaText.isNotEmpty) Positioned(top: MediaQuery.paddingOf(context).top + 76, left: 18, child: Chip(avatar: const Icon(Icons.route), label: Text('${_routeRemainingKm.toStringAsFixed(1)} km · $_routeEtaText'))),
      ]),
    );
  }

  Widget? _suggestionDropdown() {
    if (_suggestions.isEmpty) return null;
    return Material(elevation: 8, color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16), child: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: _suggestions.map((suggestion) {
        final isBus = suggestion.startsWith('bus:');
        final name = suggestion.substring(suggestion.indexOf(':') + 1);
        final bus = isBus ? _fleet.cast<BusLocation?>().firstWhere((item) => item?.busId == name, orElse: () => null) : null;
        return ListTile(leading: Icon(isBus ? Icons.directions_bus : Icons.place), title: Text(isBus ? '$name · ${bus != null && _running(bus) ? 'Running · ${bus.speed.toStringAsFixed(0)} km/h' : 'Parked'}' : name),
          onTap: () => isBus ? (bus == null ? null : _chooseBus(bus)) : _chooseStop(name));
      }).toList()),
    ));
  }

  double _distanceToRouteMeters(LatLng point, List<LatLng> path) {
    var minDistance = double.infinity;
    for (final routePoint in path) {
      minDistance = min(minDistance, _distanceKm(point, routePoint) * 1000);
    }
    return minDistance;
  }

  String _nextTurnDistance() {
    if (_userPosition == null || _maneuvers.isEmpty) return '';
    final maneuver = _maneuvers[_maneuverIndex.clamp(0, _maneuvers.length - 1)];
    final meters = (_distanceKm(_userPosition!, maneuver.point) * 1000).round();
    return meters < 1000 ? '${meters} m' : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Widget _navControl(IconData icon, String tooltip, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 10), child: Material(color: const Color(0xCC111827), shape: const CircleBorder(), child: IconButton(tooltip: tooltip, onPressed: onTap, color: Colors.white, icon: Icon(icon))));

  void _showSearch() {
    _navigation.browse();
    _searchFocusNode.requestFocus();
  }

  Future<void> _animateNavigationCamera(LatLng target) async {
    if (!_mapController.isCompleted) return;
    final map = await _mapController.future;
    _cameraCommandActive = true;
    try {
      await map.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: target, zoom: 18, tilt: 55, bearing: _userHeading)));
    } finally {
      _cameraCommandActive = false;
    }
  }

  void _recenterUser() {
    _navigation.setFollowing(true);
    final user = _userPosition;
    if (user == null || !_mapController.isCompleted) return;
    _animateNavigationCamera(user);
  }

  void _fitRoute() {
    if (_currentRoute.length < 2 || !_mapController.isCompleted) return;
    final points = _currentRoute;
    final bounds = LatLngBounds(
      southwest: LatLng(points.map((p) => p.latitude).reduce(min), points.map((p) => p.longitude).reduce(min)),
      northeast: LatLng(points.map((p) => p.latitude).reduce(max), points.map((p) => p.longitude).reduce(max)),
    );
    _mapController.future.then((map) => map.animateCamera(CameraUpdate.newLatLngBounds(bounds, 90)));
  }

  String _arrivalClock() => TimeOfDay.fromDateTime(DateTime.now().add(Duration(minutes: int.tryParse(_routeEtaText.split(' ').first) ?? 0))).format(context);

  Future<void> _showLayerChooser() => showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (context) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const ListTile(title: Text('Map type')),
    for (final layer in MapLayer.values) ListTile(title: Text(switch (layer) { MapLayer.street => 'Default', MapLayer.dark => 'Dark', MapLayer.satellite => 'Satellite', MapLayer.terrain => 'Terrain' }), trailing: _selectedMapLayer == layer ? const Icon(Icons.check, color: Color(0xFF2563EB)) : null,
      onTap: () { setState(() => _selectedMapLayer = layer); Navigator.pop(context); }),
  ])));

}
