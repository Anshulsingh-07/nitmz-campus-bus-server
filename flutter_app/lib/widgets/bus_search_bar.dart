import 'package:flutter/material.dart';

class BusSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool connected, refreshing;
  final Widget? suggestions;
  final ValueChanged<String> onChanged, onSubmitted;
  final VoidCallback onMenu, onRefresh;
  const BusSearchBar({super.key, required this.controller, required this.focusNode, required this.connected, required this.refreshing, required this.suggestions, required this.onChanged, required this.onSubmitted, required this.onMenu, required this.onRefresh});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(children: [
      Material(elevation: 5, color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(18), child: Row(children: [
        IconButton(tooltip: 'Bus list', onPressed: onMenu, icon: const Icon(Icons.menu)),
        const Icon(Icons.search, color: Color(0xFF64748B)),
        Expanded(child: TextField(controller: controller, focusNode: focusNode, onChanged: onChanged, onSubmitted: onSubmitted, decoration: const InputDecoration(hintText: 'Search bus or stop', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 12)))),
        if (controller.text.isNotEmpty) IconButton(tooltip: 'Clear', onPressed: () { controller.clear(); onChanged(''); }, icon: const Icon(Icons.close)),
        if (connected) const Padding(padding: EdgeInsets.only(right: 2), child: Chip(avatar: Icon(Icons.circle, size: 9, color: Color(0xFF16A34A)), label: Text('Live'))),
        IconButton(tooltip: 'Refresh buses', onPressed: refreshing ? null : onRefresh, icon: refreshing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.refresh)),
        const SizedBox(width: 6),
      ])),
      if (suggestions != null) suggestions!,
    ]);
  }
}
