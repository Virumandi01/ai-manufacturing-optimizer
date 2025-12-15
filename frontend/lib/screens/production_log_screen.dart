// lib/screens/production_log_screen.dart (Updated with Dropdown)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';

class ProductionLogScreen extends StatefulWidget {
  const ProductionLogScreen({super.key});

  @override
  State<ProductionLogScreen> createState() => _ProductionLogScreenState();
}

class _ProductionLogScreenState extends State<ProductionLogScreen> {
  final _formKey = GlobalKey<FormState>();
  // We no longer need _taskIdController, we use this to hold the selected ID
  int? _selectedTaskId; 
  final TextEditingController _resourceController = TextEditingController();
  final TextEditingController _countController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Fetch tasks for the dropdown when the screen initializes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).fetchAllTasksForDropdown();
    });
  }
  
  Future<void> _submitLog() async {
    // Only validate the other fields since the dropdown handles its own validation
    if (_formKey.currentState!.validate() && _selectedTaskId != null) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      
      final String resourceUsed = _resourceController.text;
      final int productCount = int.tryParse(_countController.text) ?? 0;
      
      // Call the API function to save the production log
      final result = await apiService.logProduction(
        taskId: _selectedTaskId!,
        resourceUsed: resourceUsed,
        productCount: productCount,
      );
      
      // Display the result message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result), 
          backgroundColor: result.contains('success') ? Colors.green : Colors.red,
        ),
      );
      
      // Clear form on success
      if (result.contains('success')) {
        setState(() {
          _selectedTaskId = null; // Reset dropdown selection
        });
        _resourceController.clear();
        _countController.clear();
      }
    } else if (_selectedTaskId == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a Task ID."), 
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use a Consumer to rebuild when the task list is fetched
    return Consumer<ApiService>(
      builder: (context, apiService, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Production Log Tracker 📝'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Log Task Output and Resource Consumption', 
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 20),
                      
                      // --- Task ID Dropdown ---
                      DropdownButtonFormField<int>(
                        decoration: const InputDecoration(
                          labelText: 'Task Completed',
                          border: OutlineInputBorder(),
                        ),
                        hint: const Text('Select a Task from the Schedule'),
                        value: _selectedTaskId,
                        items: apiService.dropdownTasks.map((task) {
                          return DropdownMenuItem<int>(
                            value: task.id,
                            child: Text('ID ${task.id}: ${task.name}'),
                          );
                        }).toList(),
                        onChanged: (int? newValue) {
                          setState(() {
                            _selectedTaskId = newValue;
                          });
                        },
                        validator: (value) => value == null ? 'Please select a Task.' : null,
                      ),
                      const SizedBox(height: 15),

                      // Resource Used Input
                      TextFormField(
                        controller: _resourceController,
                        decoration: const InputDecoration(
                          labelText: 'Input Resource Used',
                          hintText: 'e.g., 50 kg Steel, 2 Liters Paint',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please specify the resource used.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 15),

                      // Product Count Input
                      TextFormField(
                        controller: _countController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'End Product Count (Output)',
                          hintText: 'e.g., 100 finished units',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || int.tryParse(value) == null || int.parse(value) < 0) {
                            return 'Please enter a valid non-negative number.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 30),

                      // Submit Button
                      ElevatedButton.icon(
                        onPressed: _submitLog,
                        icon: const Icon(Icons.send),
                        label: const Text('Submit Production Log'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
    );
  }
}