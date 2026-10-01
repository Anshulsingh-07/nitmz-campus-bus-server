import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

class PendingDriversScreen extends StatefulWidget {
  const PendingDriversScreen({super.key});
  @override
  State<PendingDriversScreen> createState() => _PendingDriversScreenState();
}

class _PendingDriversScreenState extends State<PendingDriversScreen> {
  late Future<List<dynamic>> _pending;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _pending = context.read<ApiService>().getManagedDrivers(
      context.read<AuthService>().currentUser?.token ?? '',
    );
  }

  Future<void> _reassign(Map<String, dynamic> driver) async {
    final controller = TextEditingController(
      text: driver['busNumber'].toString(),
    );
    final selected = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Reassign bus'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Bus number'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, int.tryParse(controller.text)),
            child: const Text('Reassign'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (selected == null) return;
    try {
      await context.read<ApiService>().reviewDriver(
        context.read<AuthService>().currentUser!.token!,
        driver['id'].toString(),
        'reassign',
        busNumber: selected,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              driver['accountStatus'] == 'approved'
                  ? 'Bus assignment updated'
                  : 'Bus reassigned and driver approved',
            ),
          ),
        );
        setState(_load);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _confirmRemove(Map<String, dynamic> driver) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove driver?'),
        content: Text(
          '${driver['name']} will lose access to Bus ${driver['busNumber']}. This bus can then be assigned to another driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes == true) await _act(driver, 'remove');
  }

  Future<void> _act(Map<String, dynamic> driver, String action) async {
    try {
      await context.read<ApiService>().reviewDriver(
        context.read<AuthService>().currentUser!.token!,
        driver['id'].toString(),
        action,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'approve'
                  ? 'Driver approved'
                  : action == 'remove'
                  ? 'Driver removed and bus unassigned'
                  : 'Driver rejected',
            ),
          ),
        );
        setState(_load);
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pending Drivers')),
    body: RefreshIndicator(
      onRefresh: () async => setState(_load),
      child: FutureBuilder<List<dynamic>>(
        future: _pending,
        builder: (context, s) {
          if (s.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (s.hasError)
            return ListView(
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Could not load requests: ${s.error}'),
                  ),
                ),
              ],
            );
          final drivers = (s.data ?? []).where((d) => d is Map && d['accountStatus'] != 'approved').toList();
          if (drivers.isEmpty) {
            return const Center(
              child: Text('No pending driver requests'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: drivers.length,
            itemBuilder: (context, i) {
              final d = Map<String, dynamic>.from(drivers[i] as Map);
              return Card(
                child: ListTile(
                  isThreeLine: true,
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(d['name']?.toString() ?? 'Driver'),
                  subtitle: Text(
                    '${d['phone']} · Bus ${d['busNumber']}\nRequested ${d['createdAt'] ?? 'just now'}',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: 'Reject',
                        onPressed: () => _act(d, 'reject'),
                        icon: const Icon(Icons.close, color: Colors.red),
                      ),
                      IconButton(
                        tooltip: 'Approve',
                        onPressed: () => _act(d, 'approve'),
                        icon: const Icon(Icons.check, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    ),
  );
}
