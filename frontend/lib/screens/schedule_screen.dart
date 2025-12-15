// lib/screens/schedule_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:ai_scheduler_app/screens/gantt_chart_widget.dart';
import 'package:ai_scheduler_app/screens/task_creation_screen.dart'; // Import for the Add Task button
import 'package:ai_scheduler_app/screens/machine_management_screen.dart';
import 'package:ai_scheduler_app/screens/edit_task_screen.dart'; // IMPORTANT: Added this required import

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> with SingleTickerProviderStateMixin<ScheduleScreen> {

  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    // INITIALIZE THE CONTROLLER HERE
    _tabController = TabController(length: 2, vsync: this); 
    
    // Existing data fetch logic:
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ApiService>(context, listen: false).fetchSchedule();
    });
  }

  @override
  void dispose() {
    // DISPOSE THE CONTROLLER HERE
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _runOptimizer() async {
    // --- STEP 1: PROMPT USER FOR START TIME ---
    DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 7)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Start Date for Schedule',
    );

    if (pickedDate == null) return; // User canceled date selection

    // Show time picker after date is selected
    TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now()),
      helpText: 'Select Start Time (e.g., 9:00 AM)',
    );

    if (pickedTime == null) return; // User canceled time selection

    // Combine date and time
    final DateTime scheduleStartTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    
    // Convert to ISO 8601 UTC string for API transmission
    final String startTimeIso = scheduleStartTime.toUtc().toIso8601String();
    
    // --- STEP 2: RUN OPTIMIZER ---
    final apiService = Provider.of<ApiService>(context, listen: false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Running optimization... this may take a moment.'), duration: Duration(seconds: 2))
    );

    final result = await apiService.runOptimization(startTime: startTimeIso);

    // --- STEP 3: SHOW RESULTS ---
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result),
        backgroundColor: result.contains('successful') ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // --- Helper method to navigate to the Add Task screen ---
  void _navigateToAddTask() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TaskCreationScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Production Schedule Command Center ⚙️'),
        actions: [
          // Button for Machine Management
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const MachineManagementScreen()),
              );
            },
          ),
          // Button to navigate to Task Creation (for Manager)
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: _navigateToAddTask,
          ),
          // Existing Refresh Button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              Provider.of<ApiService>(context, listen: false).fetchSchedule();
            },
          ),
        ],
        // ADD THE TAB BAR TO THE BOTTOM OF THE APP BAR
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'List View', icon: Icon(Icons.list)),
            Tab(text: 'Gantt Chart', icon: Icon(Icons.timeline)),
          ],
        ),
      ),
      
      // Floating Action Button should remain here

      floatingActionButton: FloatingActionButton.extended(
        onPressed: _runOptimizer,
        label: const Text('Run Optimizer'),
        icon: const Icon(Icons.psychology_alt),
        backgroundColor: Colors.blue.shade700,
      ),
      
      // REPLACE THE body: Consumer with this new TabBarView structure
      body: Consumer<ApiService>(
        builder: (context, apiService, child) {
          
          // --- START EXISTING CHECKS ---
          if (apiService.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (apiService.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Error: ${apiService.errorMessage}',
                  style: const TextStyle(color: Colors.red, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (apiService.tasks.isEmpty) {
            return const Center(
              child: Text(
                'No tasks scheduled. Use the + button to add tasks.',
                style: TextStyle(fontSize: 16),
              ),
            );
          }
          // --- END EXISTING CHECKS ---

          // NEW: TabBarView to switch between List and Chart
          return TabBarView(
            controller: _tabController,
            children: [
              // 1. LIST VIEW (The main task list)
              ListView.builder(
                padding: const EdgeInsets.all(8.0),
                itemCount: apiService.tasks.length,
                itemBuilder: (context, index) {
                  final task = apiService.tasks[index];
                  final DateFormat formatter = DateFormat('MMM d, HH:mm:ss');
  
                  // Replace the Card with the Dismissible widget for the Delete action
                  return Dismissible(
                    key: Key(task.taskId.toString()), // Unique key for the task
                    direction: DismissDirection.endToStart, // Only swipe from right-to-left
                    
                    // Background color/icon shown during the swipe
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                      child: const Icon(Icons.delete_forever, color: Colors.white),
                    ),
                    
                    // Action when the card is dismissed (swiped away)
                    confirmDismiss: (direction) async {
                      // Show confirmation dialog before deleting
                      return await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return AlertDialog(
                            title: const Text("Confirm Deletion"),
                            content: Text("Are you sure you want to delete Task ${task.taskId}: ${task.taskName}?"),
                            actions: <Widget>[
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(false), // Cancel
                                child: const Text("Cancel"),
                              ),
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(true), // Confirm
                                child: const Text("Delete", style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    
                    // Action after confirmation
                    onDismissed: (direction) async {
                      final apiService = Provider.of<ApiService>(context, listen: false); 
                      
                      // FIX: Use the local non-nullable variable for clarity
                      final id = task.taskId; 

                      // ignore: unnecessary_non_null_in_if_null, unused_local_variable
                      if (id != null) { 
                        final result = await apiService.deleteTask(id); // Use 'id' directly
                        
                        if (!mounted) return; 
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(result), 
                            backgroundColor: result.contains('successfully') ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    },
                    
                    // The actual card content (ListTile remains the same)
                    child: Card(
                      elevation: 4,
                      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      child: ListTile(
                        // NEW: Added onTap to navigate to EditTaskScreen
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => EditTaskScreen(task: task),
                            ),
                          );
                        },
                        leading: CircleAvatar(
                          backgroundColor: task.status == 'Scheduled' ? Colors.green : (task.status == 'Completed' ? Colors.blueGrey : Colors.grey),
                          child: Text(task.taskId.toString()),
                        ),
                        title: Text(
                          '${task.taskName} (Job #${task.jobId})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Machine: ${task.machineName}\n'
                
                      'Duration: ${task.durationHours} hrs\n'
                          'Start: ${task.startTime != null ? formatter.format(task.startTime!.toLocal()) : 'N/A'}\n'
                          'End: ${task.endTime != null ? formatter.format(task.endTime!.toLocal()) : 'N/A'}',
                        ),
                        
                        // Trailing button for Status Update remains here
                        trailing: IconButton(
                          icon: Icon(
                            task.status == 'Completed' ? Icons.check_circle : Icons.play_circle_fill,
                            color: task.status == 'Completed' ? Colors.green.shade700 : Colors.orange.shade700,
                          ),
                          onPressed: task.status == 'Completed' 
                              ? null // Disable if already completed
                              : () async {
                                  // FIX: Fetch apiService here for context
                                  final apiService = Provider.of<ApiService>(context, listen: false); 
                                  
                                  // Action: Mark task as Completed
                                  const newStatus = 'Completed';
                                  
                                  // CRITICAL FIX: Correct the suppression comment format
                                  // ignore: unnecessary_non_null_assertion
                                  final result = await apiService.updateTaskStatus(task.taskId, newStatus);
                                  
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(result), 
                                      backgroundColor: result.contains('RUN OPTIMIZER') ? Colors.red.shade700 : Colors.green,
                                      duration: const Duration(seconds: 4),
                                    ),
                                  );
                                },
                        ),
                      ),
                    ),
                  );
                }
              ),
              
              // 2. GANTT CHART VIEW (Call the new widget)
              GanttChartWidget(tasks: apiService.tasks),
            ],
          );
        },
      ),
    );
  }
}