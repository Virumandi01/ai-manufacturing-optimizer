// lib/screens/machine_management_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class MachineManagementScreen extends StatefulWidget {
  const MachineManagementScreen({super.key});

  @override
  State<MachineManagementScreen> createState() => _MachineManagementScreenState();
}

class _MachineManagementScreenState extends State<MachineManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController(text: '1');
  
  @override
  void initState() {
    super.initState();
    // Load existing machines when the screen is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).fetchMachines();
    });
  }

  Future<void> _submitMachine() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      final String name = _nameController.text;
      final int capacity = int.tryParse(_capacityController.text) ?? 1;
      
      // Call the API function to save the machine
      final result = await apiService.addMachine(name, capacity);
      
      // Display the result message
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result), 
          backgroundColor: result.contains('success') ? Colors.green : Colors.red,
        ),
      );
      
      // Clear form and reload list on success
      if (result.contains('success')) {
        _nameController.clear();
        _capacityController.text = '1';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Production Machines 🏭'),
      ),
      body: Consumer<ApiService>(
        builder: (context, apiService, child) {
          // The main Column that holds the form and the list
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- 1. Add New Machine Form (Scrollable Form) ---
              SingleChildScrollView( // Only the top form needs scrolling
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min, // Use minimum space required
                        children: [
                          const Text('Add New Machine', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 15),

                          // Name Input
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Machine Name (e.g., CNC Router)',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a machine name.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 15),

                          // Capacity Input
                          TextFormField(
                            controller: _capacityController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Capacity (Default: 1)',
                              hintText: 'e.g., 2 for a dual-spindle machine',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || int.tryParse(value) == null || int.parse(value) <= 0) {
                                return 'Please enter a valid positive number for capacity.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Submit Button
                          ElevatedButton.icon(
                            onPressed: _submitMachine,
                            icon: const Icon(Icons.add),
                            label: const Text('Save New Machine', style: TextStyle(fontSize: 16)),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 10),
                    Text('Current Machines in Database:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Divider(),
                  ],
                ),
              ),

              // --- 2. Display Existing Machines List (CRITICAL: Needs Expanded) ---
              Expanded( // This Expanded widget is essential to fix the layout error
                child: apiService.machines.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: Text('No machines found. Add one above!'),
                        ),
                      )
                    : ListView.builder(
                        itemCount: apiService.machines.length,
                        itemBuilder: (context, index) {
                          final machine = apiService.machines[index];
                          
                          // --- START Dismissible Widget for Swipe-to-Delete ---
                          return Dismissible(
                            key: Key(machine.machineId.toString()),
                            direction: DismissDirection.endToStart, 
                            background: Container(
                              color: Colors.red,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.symmetric(horizontal: 20.0),
                              child: const Icon(Icons.delete_forever, color: Colors.white),
                            ),
                            confirmDismiss: (direction) async {
                              return await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    title: const Text("Confirm Machine Deletion"),
                                    content: Text("Are you sure you want to delete Machine: ${machine.name}? This cannot be undone."),
                                    actions: <Widget>[
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(false), 
                                        child: const Text("Cancel"),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(true), 
                                        child: const Text("Delete", style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                            onDismissed: (direction) async {
                              final result = await apiService.deleteMachine(machine.machineId);

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result),
                                  backgroundColor: result.contains('successfully') ? Colors.green : Colors.red,
                                ),
                              );
                            },
                            // The actual list item content
                            child: Card(
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  child: Text(machine.machineId.toString()),
                                ),
                                title: Text(machine.name),
                                subtitle: Text('Capacity: ${machine.capacity}'),
                              ),
                            ),
                          );
                          // --- END Dismissible Widget ---
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}