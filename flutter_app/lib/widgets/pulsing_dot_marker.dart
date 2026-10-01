import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Google Maps circle overlay used as a compact, tappable bus marker.
class PulsingDotMarker {
  static Set<Circle> build({required String id, required LatLng position, required bool running, required bool expanded, required VoidCallback onTap}) {
    final circles = <Circle>{
      Circle(circleId: CircleId('${id}_hit'), center: position, radius: 105, fillColor: Colors.transparent, strokeColor: Colors.transparent, onTap: onTap),
      Circle(circleId: CircleId('${id}_dot'), center: position, radius: 22, fillColor: running ? const Color(0xFF2563EB) : const Color(0xFF94A3B8), strokeColor: Colors.white, strokeWidth: 2, onTap: onTap),
    };
    if (running) circles.add(Circle(circleId: CircleId('${id}_pulse'), center: position, radius: expanded ? 58 : 36, fillColor: const Color(0x142563EB), strokeColor: const Color(0x772563EB).withValues(alpha: expanded ? .62 : .28), strokeWidth: 2, onTap: onTap));
    return circles;
  }
}
