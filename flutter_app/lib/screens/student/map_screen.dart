import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/bus_location.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../services/bus_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();

  List<BusLocation> _fleet = [];
  double _mapZoom = 15;

  bool _isLoading = true;
  bool _isConnected = false;
  bool _followSelectedBus = true;
  String? _error;

  String? _selectedBusKey;
  DateTime? _lastUpdate;
  Timer? _pollTimer;

  static const LatLng _defaultCenter = LatLng(23.7271, 92.7176);
  static const Map<String, LatLng> _knownHostelCoordinates = {
    'BH1': LatLng(23.7286, 92.7187),
    'BH2': LatLng(23.7282, 92.7185),
    'BH3': LatLng(23.7279, 92.7182),
    'BH4': LatLng(23.7275, 92.7180),
    'GH1': LatLng(23.7273, 92.7175),
    'GH2': LatLng(23.7270, 92.7173),
  };
  static const LatLng _mbseCenter = LatLng(23.7573, 92.7288);
  static const double _minZoom = 5;
  static const double _maxZoom = 19;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _syncFleet();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _syncFleet());
  }

  Future<void> _syncFleet() async {
    if (!mounted) return;

    final api = context.read<ApiService>();
    final auth = context.read<AuthService>();
    final busService = context.read<BusService>();

    try {
      // Source 1: App backend buses (protected endpoint)
      final busesData = await api.getBuses(
        hostel: auth.isAdmin ? null : auth.currentUser?.hostelId,
        token: auth.currentUser?.token,
      );

      var fleet = busesData
          .whereType<Map<String, dynamic>>()
          .map(_fromBusJson)
          .toList();

      // Source 2: Latest ESP32 telemetry (public endpoint)
      final latest = await ApiService.fetchLatestLocation();
      if (latest != null) {
        fleet = _mergeLatestTelemetry(fleet, latest);
      }

      if (fleet.isEmpty) {
        // Last fallback to locally loaded service buses.
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

      final selectedKey = _selectedBusKey ?? (fleet.isNotEmpty ? _busKey(fleet.first.busId) : null);
      final selectedBus = _findByKey(fleet, selectedKey);
      if (_followSelectedBus && selectedBus != null) {
        _mapController.move(LatLng(selectedBus.lat, selectedBus.lng), _mapZoom);
      }

      if (!mounted) return;
      setState(() {
        _fleet = fleet;
        _selectedBusKey = selectedKey;
        _isLoading = false;
        _isConnected = latest != null;
        _error = null;
        _lastUpdate = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isConnected = false;
        _error = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  BusLocation _fromBusJson(Map<String, dynamic> bus) {
    final number = bus['busNumber']?.toString() ?? 'Unknown';
    return BusLocation(
      busId: 'Bus $number',
      deviceId: (bus['deviceId'] ?? 'device-$number').toString(),
      assignedHostel: (bus['assignedHostel'] ?? bus['assigned_hostel'] ?? '').toString(),
      lat: ((bus['latitude'] ?? bus['lat'] ?? 23.7271) as num).toDouble(),
      lng: ((bus['longitude'] ?? bus['lng'] ?? 92.7176) as num).toDouble(),
      speed: ((bus['speed'] ?? 0) as num).toDouble(),
      accuracy: ((bus['accuracy'] ?? bus['hdop'] ?? 1.0) as num).toDouble(),
      status: (bus['status'] ?? 'idle').toString(),
      timestamp: DateTime.now(),
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

  Color _statusColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized == 'running' || normalized == 'active' || normalized == 'moving') {
      return const Color(0xFF16A34A);
    }
    if (normalized == 'maintenance') {
      return const Color(0xFFDC2626);
    }
    return const Color(0xFFF59E0B);
  }

  LatLng? _getHostelCoordinates(String hostel) {
    return _knownHostelCoordinates[hostel];
  }

  double _distanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    final lat1 = a.latitude * (3.141592653589793 / 180);
    final lat2 = b.latitude * (3.141592653589793 / 180);
    final dLat = lat2 - lat1;
    final dLng = (b.longitude - a.longitude) * (3.141592653589793 / 180);
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * r * asin(sqrt(h));
  }

  LatLng _resolveDestination(BusLocation bus) {
    final hostelCoords = _getHostelCoordinates(bus.assignedHostel);
    if (hostelCoords == null) return _mbseCenter;
    final distanceToHostel = _distanceKm(LatLng(bus.lat, bus.lng), hostelCoords);
    final distanceToMBSE = _distanceKm(LatLng(bus.lat, bus.lng), _mbseCenter);
    if (distanceToMBSE <= distanceToHostel) {
      return _mbseCenter;
    }
    return hostelCoords;
  }

  String _routeLabel(BusLocation bus) {
    if (bus.assignedHostel.isEmpty) return 'Hostel ↔ MBSE';
    return 'Hostel ↔ ${bus.assignedHostel}';
  }

  @override
  Widget build(BuildContext context) {
    final selected = _findByKey(_fleet, _selectedBusKey);
    final center = selected != null ? LatLng(selected.lat, selected.lng) : _defaultCenter;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 15,
              onPositionChanged: (position, _) {
                _mapZoom = position.zoom.clamp(_minZoom, _maxZoom);
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.nitmz.campus_bus_tracker',
              ),
              if (selected != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        LatLng(selected.lat, selected.lng),
                        _resolveDestination(selected),
                      ],
                      color: Colors.blueAccent.withValues(alpha: 0.95),
                      strokeWidth: 7,
                      borderColor: Colors.white.withValues(alpha: 0.85),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              if (selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _resolveDestination(selected),
                      width: 140,
                      height: 56,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Text(
                              _routeLabel(selected),
                              style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              MarkerLayer(
                markers: _fleet.map((bus) {
                  final key = _busKey(bus.busId);
                  final isSelected = _selectedBusKey == key;
                  final markerColor = _statusColor(bus.status);

                  return Marker(
                    point: LatLng(bus.lat, bus.lng),
                    width: isSelected ? 40 : 34,
                    height: isSelected ? 40 : 34,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBusKey = key;
                        });
                        _mapController.move(LatLng(bus.lat, bus.lng), _mapZoom);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: markerColor,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 12,
                              color: markerColor.withValues(alpha: 0.45),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _busKey(bus.busId),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          Positioned(
            left: 12,
            top: 14,
            right: 12,
            child: _buildTopBar(),
          ),

          Positioned(
            left: 12,
            top: 72,
            width: 220,
            bottom: 16,
            child: _buildFleetPanel(),
          ),

          Positioned(
            right: 12,
            top: 72,
            width: 212,
            child: _buildDiagnosticsCard(selected),
          ),

          Positioned(
            right: 12,
            bottom: 150,
            child: _buildZoomControls(),
          ),

          // Compass
          Positioned(
            right: 12,
            bottom: 110,
            child: _buildCompass(),
          ),

          // Location button similar to Google Maps
          Positioned(
            right: 12,
            bottom: 18,
            child: _buildLocationButton(),
          ),

          if (_isLoading)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    // Google Maps-like search bar
    return Material(
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 48,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  // Placeholder: keep existing behavior unchanged — no navigation added
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: const [
                      Icon(Icons.search, color: Color(0xFF6B7280)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search here',
                          style: TextStyle(color: Color(0xFF6B7280)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(Icons.mic, color: Color(0xFF6B7280)),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Status chip + refresh in compact form
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_isConnected ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2)),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isConnected ? 'Live' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _isConnected ? const Color(0xFF166534) : const Color(0xFF991B1B),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: IconButton(
              onPressed: _syncFleet,
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetPanel() {
    final selected = _findByKey(_fleet, _selectedBusKey);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Campus Fleet', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
              ),
            ),
          if (selected != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${selected.busId} - Active', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _routeLabel(selected),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${selected.status.toUpperCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: _statusColor(selected.status),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: _fleet.length,
              itemBuilder: (context, index) {
                final bus = _fleet[index];
                final key = _busKey(bus.busId);
                final isSelected = _selectedBusKey == key;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isSelected ? const Color(0xFF111827) : const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        setState(() {
                          _selectedBusKey = key;
                        });
                        _mapController.move(LatLng(bus.lat, bus.lng), _mapZoom);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _statusColor(bus.status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${bus.busId} • ${bus.speed.toStringAsFixed(1)} km/h',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : const Color(0xFF111827),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _followSelectedBus = !_followSelectedBus;
                    });
                  },
                  icon: Icon(_followSelectedBus ? Icons.my_location : Icons.location_searching),
                  label: Text(_followSelectedBus ? 'Follow' : 'Free Pan'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsCard(BusLocation? selected) {
    final trackingEndpoint = ApiService.trackingLatestEndpoint;
    final raw = selected == null
        ? '{}'
        : jsonEncode({
            'busId': selected.busId,
            'deviceId': selected.deviceId,
            'lat': selected.lat,
            'lng': selected.lng,
            'speed': selected.speed,
            'accuracy': selected.accuracy,
            'status': selected.status,
          });

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC).withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Color(0x22000000), blurRadius: 8),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Live Diagnostics', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _diagRow('Route', selected == null ? 'N/A' : _routeLabel(selected)),
          _diagRow('Status', selected?.status.toUpperCase() ?? 'N/A'),
          _diagRow('Speed', selected == null ? 'N/A' : '${selected.speed.toStringAsFixed(1)} km/h'),
          _diagRow('Latitude', selected == null ? 'N/A' : selected.lat.toStringAsFixed(6)),
          _diagRow('Longitude', selected == null ? 'N/A' : selected.lng.toStringAsFixed(6)),
          _diagRow('HDOP', selected == null ? 'N/A' : selected.accuracy.toStringAsFixed(2)),
          _diagRow('Updated', _lastUpdate == null ? 'N/A' : _lastUpdate!.toLocal().toString().split('.').first),
          const SizedBox(height: 8),
          Text(
            'Endpoint: $trackingEndpoint',
            style: const TextStyle(fontSize: 10, color: Color(0xFF374151)),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              raw,
              style: const TextStyle(
                color: Color(0xFF86EFAC),
                fontFamily: 'monospace',
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildZoomControls() {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Zoom in',
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => _changeZoom(1),
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              tooltip: 'Zoom out',
              icon: const Icon(Icons.remove, size: 20),
              onPressed: () => _changeZoom(-1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    return Material(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          // no-op for now; purely visual compass
        },
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          child: const Icon(Icons.explore, size: 20, color: Color(0xFF374151)),
        ),
      ),
    );
  }

  Widget _buildLocationButton() {
    return Material(
      elevation: 6,
      shape: const CircleBorder(),
      color: Colors.white,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          final selected = _findByKey(_fleet, _selectedBusKey);
          final target = selected != null ? LatLng(selected.lat, selected.lng) : _defaultCenter;
          _mapController.move(target, _mapZoom);
        },
        child: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          child: const Icon(Icons.my_location, color: Color(0xFF2563EB)),
        ),
      ),
    );
  }

  void _changeZoom(double delta) {
    final selected = _findByKey(_fleet, _selectedBusKey);
    final targetCenter = selected != null ? LatLng(selected.lat, selected.lng) : _mapController.camera.center;
    final nextZoom = (_mapZoom + delta).clamp(_minZoom, _maxZoom);
    _mapZoom = nextZoom;
    _mapController.move(targetCenter, nextZoom);
  }
}
