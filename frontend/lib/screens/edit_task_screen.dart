// lib/screens/edit_task_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task.dart';
import '../services/api_service.dart';
import '../models/machine.dart';

class EditTaskScreen extends StatefulWidget {
  final Task task;

  const EditTaskScreen({super.key, required this.task});

  @override
  State<EditTaskScreen> createState() => _EditTaskScreenState();
}

class _EditTaskScreenState extends State<EditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _durationController;
  late String? _selectedMachine;

  @override
  void initState() {
    super.initState();
    // Initialize controllers with current task data
    _nameController = TextEditingController(text: widget.task.taskName);
    _durationController = TextEditingController(text: widget.task.durationHours.toString());
    _selectedMachine = widget.task.machineName;
    
    // Fetch machines dynamically for the dropdown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).fetchMachines();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _submitEdit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      final double duration = double.parse(_durationController.text);
      
      // Call the API method to send the PATCH request
      final resultMessage = await apiService.editTaskDetails(
        widget.task.taskId,
        name: _nameController.text,
        durationHours: duration,
        machineName: _selectedMachine,
      );
      
      // Display the result in a SnackBar
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultMessage),
          backgroundColor: resultMessage.contains('successfully') ? Colors.green : Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      
      // If successful, navigate back
      if (resultMessage.contains('successfully')) {
        Navigator.pop(context); 
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Task ${widget.task.taskId}: ${widget.task.taskName} ✏️'),
      ),
      body: Consumer<ApiService>(
        builder: (context, apiService, child) {
          
          // Show loading indicator if machines are still fetching
          if (apiService.machines.isEmpty && apiService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // Current Status Display Card
                  Card(
                    color: Colors.yellow.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Text(
                        'Current Status: ${widget.task.status}. Changing details will reset status to PENDING. Optimizer must be rerun!',
                        style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Task Name Input
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(labelText: 'Task Name', border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter a task name.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),

                  // Duration Input
                  TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Duration (Hours)', border: OutlineInputBorder()),
                    validator: (value) {
                      if (value == null || double.tryParse(value) == null) return 'Enter a valid number.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),

                  // Machine Selection Dropdown (Dynamically loaded)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Required Machine', border: OutlineInputBorder()),
                    value: _selectedMachine,
                    hint: const Text('Select an available machine'),
                    items: apiService.machines.map((Machine machine) {
                      return DropdownMenuItem<String>(
                        value: machine.name,
                        child: Text('${machine.name} (Capacity: ${machine.capacity})'),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedMachine = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) return 'Please select a machine.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),

                  // Submit Button
                  ElevatedButton.icon(
                    onPressed: _submitEdit,
                    icon: const Icon(Icons.save),
                    label: const Text('Save Changes & Re-optimize', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}