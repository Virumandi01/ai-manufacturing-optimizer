// lib/screens/resource_management_screen.dart (New, polished UI)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class ResourceManagementScreen extends StatefulWidget {
  const ResourceManagementScreen({super.key});

  @override
  State<ResourceManagementScreen> createState() => _ResourceManagementScreenState();
}

class _ResourceManagementScreenState extends State<ResourceManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController(text: '1');

  @override
  void initState() {
    super.initState();
    // Fetch machines immediately upon entering the screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).fetchMachines();
    });
  }

  Future<void> _submitMachine() async {
    if (_formKey.currentState!.validate()) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final String name = _nameController.text;
      final int capacity = int.tryParse(_capacityController.text) ?? 1;

      final result = await apiService.addMachine(name, capacity);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: result.contains('success') ? Colors.green : Colors.red,
        ),
      );

      if (result.contains('success')) {
        _nameController.clear();
        _capacityController.text = '1';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ApiService>(
      builder: (context, apiService, child) {
        // We use a Column to hold the fixed-height form and the expanded list
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- 1. Add New Machine Form (Scrollable Form Area) ---
            SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 6, // Higher elevation for the form
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Add New Production Resource',
                          style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 15),

                        // Name Input
                        TextFormField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Machine Name',
                            prefixIcon: Icon(Icons.precision_manufacturing),
                          ),
                          validator: (value) => (value == null || value.isEmpty) ? 'Please enter a name.' : null,
                        ),
                        const SizedBox(height: 15),

                        // Capacity Input
                        TextFormField(
                          controller: _capacityController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Capacity',
                            prefixIcon: Icon(Icons.storage),
                          ),
                          validator: (value) => (int.tryParse(value ?? '') == null || int.parse(value!) <= 0) ? 'Enter valid capacity.' : null,
                        ),
                        const SizedBox(height: 20),

                        // Submit Button
                        ElevatedButton.icon(
                          onPressed: _submitMachine,
                          icon: const Icon(Icons.add_circle),
                          label: const Text('Save New Resource'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Divider and Title
            const Padding(
              padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Existing Production Resources:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Divider(),
                ],
              ),
            ),

            // --- 2. Display Existing Machines List (CRITICAL: Needs Expanded) ---
            Expanded(
              child: apiService.machines.isEmpty
                  ? const Center(child: Text('No machines found. Add one above!'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      itemCount: apiService.machines.length,
                      itemBuilder: (context, index) {
                        final machine = apiService.machines[index];
                        
                        // Modern Card Design for Machine List Item
                        return Dismissible(
                          key: Key(machine.machineId.toString()),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20.0),
                            decoration: BoxDecoration(
                              color: Colors.red.shade700,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: const Icon(Icons.delete_forever, color: Colors.white, size: 30),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (BuildContext context) => AlertDialog(
                                title: const Text("Confirm Deletion"),
                                content: Text("Are you sure you want to delete ${machine.name}?"),
                                actions: <Widget>[
                                  TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
                                  TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text("Delete", style: TextStyle(color: Colors.red.shade700))),
                                ],
                              ),
                            );
                          },
                          onDismissed: (direction) async {
                            final result = await apiService.deleteMachine(machine.machineId);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(result),
                              backgroundColor: result.contains('success') ? Colors.green : Colors.red,
                            ));
                          },
                          child: Card(
                            elevation: 4,
                            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                                foregroundColor: Theme.of(context).colorScheme.primary,
                                child: Text(machine.machineId.toString()),
                              ),
                              title: Text(machine.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Capacity: ${machine.capacity} | ID: ${machine.machineId}'),
                              trailing: Icon(Icons.check_circle, color: Colors.teal.shade400),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}