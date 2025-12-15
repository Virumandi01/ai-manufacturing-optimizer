// lib/screens/task_creation_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../models/task.dart'; // NEW: Import the Task model
import '../models/machine.dart'; // NEW: Import the Machine model

class TaskCreationScreen extends StatefulWidget {
  const TaskCreationScreen({super.key});

  @override
  State<TaskCreationScreen> createState() => _TaskCreationScreenState();
}

class _TaskCreationScreenState extends State<TaskCreationScreen> {
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  
  String? _selectedMachine;
  List<Task> _existingTasks = []; // Existing precedence list
  Task? _selectedPredecessorTask; 

  @override
  void initState() {
    super.initState();
    // Fetch data immediately when the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // 1. Fetch the list of machines (for the dropdown)
      Provider.of<ApiService>(context, listen: false).fetchMachines(); 
      // 2. Fetch existing tasks (for the precedence dropdown)
      _fetchExistingTasks();
    });
  }
  
  // --- MISSING METHOD ADDED HERE ---
  Future<void> _fetchExistingTasks() async {
    // Only fetch if context is valid
    if (!mounted) return;
    
    final apiService = Provider.of<ApiService>(context, listen: false);
    
    // Ensure schedule is fetched
    await apiService.fetchSchedule(); 
    
    // Update state with tasks that are currently available to be predecessors
    if (mounted) {
        setState(() {
            // Only use tasks that have an ID and are not completed
            _existingTasks = apiService.tasks
                .where((t) => t.status != 'Completed')
                .toList();
        });
    }
  }

  // --- Submission Logic ---
  Future<void> _submitTask() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final apiService = Provider.of<ApiService>(context, listen: false);
      final double duration = double.tryParse(_durationController.text) ?? 0.0;
      
      if (duration <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Duration must be greater than zero.'), backgroundColor: Colors.red),
        );
        return;
      }
      
      // 1. ADD THE NEW TASK
      final result = await apiService.addTask(
        _nameController.text, 
        duration, 
        _selectedMachine!, // ! is safe because validation checked for null
      );
      
      String finalMessage = result;
      final predecessor = _selectedPredecessorTask; 

      // If task creation was successful AND a predecessor was selected...
      if (result.contains('successfully') && predecessor != null) {
        
        // We must refetch the schedule to get the taskId of the task we just created.
        await apiService.fetchSchedule(); 
        
        // Find the newly created task (successor)
        final successorTask = apiService.tasks.lastWhere(
          (t) => t.name == _nameController.text && t.status == 'Pending',
          orElse: () => apiService.tasks.last 
        );
        
        // --- CRITICAL CHECK: Get the guaranteed non-null IDs ---
        final int? predecessorId = predecessor.taskId;
        final int? successorId = successorTask.taskId;
        
        if (predecessorId != null && successorId != null) {
          final precedenceResult = await apiService.addPrecedence(
            predecessorId, 
            successorId,
          );
          finalMessage += "\n$precedenceResult";
        } else {
            // Optional: Log an error if IDs are missing, even after saving.
            finalMessage += "\nError: Could not determine Task IDs for precedence.";
        }
      }
      
      // Display the result message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(finalMessage), 
          backgroundColor: finalMessage.contains('successfully') ? Colors.green : Colors.red,
        ),
      );
      
      // Optionally navigate back to the schedule screen
      if (finalMessage.contains('successfully')) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // WRAP THE UI IN A CONSUMER TO LISTEN FOR MACHINE DATA CHANGES
    return Consumer<ApiService>(
      builder: (context, apiService, child) {
        // Check if machines are loading or empty
        if (apiService.machines.isEmpty) {
          // If tasks are also empty, show a loading spinner, otherwise show the form with no machine options
          if (apiService.tasks.isEmpty) {
              return Scaffold(
                  appBar: AppBar(title: const Text('Add New Manufacturing Task ➕')),
                  body: const Center(child: CircularProgressIndicator()),
              );
          }
        }
        
        return Scaffold(
          appBar: AppBar(
            title: const Text('Add New Manufacturing Task ➕'),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // 1. Task Name Input
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Task Name (e.g., Polish Surface)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a task name.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),

                  // 2. Duration Input
                  TextFormField(
                    controller: _durationController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Duration (Hours)',
                      hintText: 'e.g., 1.5 or 3',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || double.tryParse(value) == null) {
                        return 'Please enter a valid number for duration.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 15),

                  // 3. Precedence (Optional)
                  DropdownButtonFormField<Task>(
                    decoration: InputDecoration(
                      labelText: _existingTasks.isEmpty 
                          ? 'No existing tasks (Optional)'
                          : 'Must Follow Task (Optional)',
                      border: const OutlineInputBorder(),
                    ),
                    value: _selectedPredecessorTask,
                    hint: const Text('Select a task that must finish first'),
                    items: _existingTasks.map((Task task) {
                      return DropdownMenuItem<Task>(
                        value: task,
                        child: Text('Task ${task.taskId}: ${task.name}'),
                      );
                    }).toList(),
                    onChanged: (Task? newValue) {
                      setState(() {
                        _selectedPredecessorTask = newValue;
                      });
                    },
                  ),
                  const SizedBox(height: 15),

                  // 4. MACHINE SELECTION DROPDOWN (DYNAMICALLY POPULATED)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Required Machine',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedMachine,
                    hint: const Text('Select an available machine'),
                    // Use the dynamically fetched list of machines
                    items: apiService.machines.map((Machine machine) {
                      return DropdownMenuItem<String>(
                        value: machine.name, // Use the name for the API call
                        child: Text('${machine.name} (Capacity: ${machine.capacity})'),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedMachine = newValue;
                      });
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a machine.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),

                  // 5. Submit Button
                  ElevatedButton.icon(
                    onPressed: _submitTask,
                    icon: const Icon(Icons.send),
                    label: const Text('Add Task & Prepare for Scheduling', style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}