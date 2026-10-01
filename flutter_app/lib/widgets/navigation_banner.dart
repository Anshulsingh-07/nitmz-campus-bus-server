import 'package:flutter/material.dart';
import '../services/maneuver_builder.dart';

class NavigationBanner extends StatelessWidget {
  final Maneuver? maneuver;
  final String distance;
  final bool rerouting;
  const NavigationBanner({super.key, required this.maneuver, required this.distance, this.rerouting = false});
  @override
  Widget build(BuildContext context) => Material(color: const Color(0xFF14532D), elevation: 8, borderRadius: BorderRadius.circular(18), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    Icon(_icon(maneuver?.kind), color: Colors.white, size: 38), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${maneuver?.instruction ?? 'Continue'} towards ${maneuver?.roadName ?? 'campus road'}', maxLines: 2, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      Text(distance, style: const TextStyle(color: Colors.white70)),
      if (rerouting) const Text('Rerouting…', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    ])),
  ])));
  IconData _icon(ManeuverKind? kind) => switch(kind) { ManeuverKind.left => Icons.turn_left, ManeuverKind.right => Icons.turn_right, ManeuverKind.uTurn => Icons.u_turn_left, ManeuverKind.arrived => Icons.place, _ => Icons.straight };
}
