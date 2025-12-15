// lib/services/api_service.dart

import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/task.dart';
import '../models/machine.dart'; // added if eeror        delete

// IMPORTANT: Use the correct base URL. 
// If using Android Emulator, change to respected code
const String _host = // Here you need to add your host id ;
// use n gork for mobile usahe of the app with laptop as server.
const String _baseUrl = '$_host/api'; // Used for fetching and optimization

class DropdownTask {
  final int id;
  final String name;

  DropdownTask({required this.id, required this.name});

  factory DropdownTask.fromJson(Map<String, dynamic> json) {
    return DropdownTask(
      id: json['task_id'],
      name: json['name'],
    );
  }
}

class ApiService with ChangeNotifier {
  List<Task> _tasks = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Task> get tasks => _tasks;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  List<Machine> _machines = []; // NEW STATE VARIABLE
  List<Machine> get machines => _machines; // NEW GETTER

  List<DropdownTask> _dropdownTasks = [];
List<DropdownTask> get dropdownTasks => _dropdownTasks;


// --- 13. FETCH ALL TASKS (GET /api/tasks) ---
Future<String> fetchAllTasksForDropdown() async {
  const url = '$_baseUrl/tasks';

  try {
    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final List<dynamic> jsonList = json.decode(response.body);
      _dropdownTasks = jsonList.map((json) => DropdownTask.fromJson(json)).toList();
      notifyListeners(); // Notify listeners to update the UI
      return "Tasks loaded successfully.";
    } else {
      return "Failed to load tasks: ${response.statusCode}";
    }
  } catch (e) {
    return 'Network Error: $e';
  }
}


  // --- 6. GET ALL MACHINES (GET /machines) ---
  Future<void> fetchMachines() async {
    final url = '$_host/machines'; 
    
    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = json.decode(response.body);
        _machines = jsonList.map((json) => Machine.fromJson(json)).toList();
      }
    } catch (e) {
      // Handle error quietly as this is a utility fetch
      if (kDebugMode) {
        print('Error fetching machines: $e');
      } 
    }
  }

  // --- 7. ADD NEW MACHINE (POST /machines) ---
  Future<String> addMachine(String name, int capacity) async {
    final url = '$_host/machines'; 
    
    try {
      final response = await http.post(
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'name': name, 'capacity': capacity}),
      );

      if (response.statusCode == 201) {
        fetchMachines(); // Refresh the dynamic machine list
        return json.decode(response.body)['message'] ?? "Machine added successfully!";
      } else {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to add machine.';
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }



  // --- 1. ADD NEW TASK (POST /tasks) ---
  Future<String> addTask(String name, double duration, String machineName) async {
    // Note: The task creation endpoint is directly under the host, not /api
    final url = '$_host/tasks'; 
    
    try {
      final response = await http.post(
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'name': name,
          'duration_hours': duration,
          'machine_name': machineName,
          'job_id': 1, // Defaulting to Job ID 1 for now
        }),
      );

      if (response.statusCode == 201) {
        // Task created successfully
        fetchSchedule(); // Refresh the main schedule view
        return "Task added successfully! Run optimizer to schedule it.";
      } else {
        // Decode server response for error message
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to add task: Server returned status ${response.statusCode}';
      }
    } catch (e) {
      return "Network Error: Could not connect to the backend. Error: $e";
    }
  }
  
  // --- 2. ADD PRECEDENCE RULE (POST /precedences) ---
  Future<String> addPrecedence(int predecessorId, int successorId) async {
    // Note: The precedence endpoint is directly under the host, not /api
    final url = '$_host/precedences'; 
    
    try {
      final response = await http.post(
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'predecessor_id': predecessorId,
          'successor_id': successorId,
        }),
      );

      if (response.statusCode == 201) {
        return "Precedence rule added successfully!";
      } else {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to add precedence.';
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }


  // --- 3. FETCH SCHEDULE (GET /api/schedule) ---
  Future<void> fetchSchedule() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse('$_baseUrl/schedule'));

      if (response.statusCode == 200) {
        // Decode the JSON array from the Python backend
        final List<dynamic> jsonList = json.decode(response.body);
        _tasks = jsonList.map((json) => Task.fromJson(json)).toList();
      } else {
        _errorMessage = 'Failed to load schedule. Server returned status: ${response.statusCode}';
      }
    } catch (e) {
      _errorMessage = 'Connection error. Ensure Python server is running on $_host. Error: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // --- 4. RUN OPTIMIZATION (POST /api/optimize) ---
  Future<String> runOptimization({String? startTime}) async {
    final payload = startTime != null 
        ? json.encode({'start_time': startTime}) // Send the specified time
        : json.encode({}); // Send empty body if time is not specified

    final response = await http.post(
      Uri.parse('$_baseUrl/optimize'),
      headers: {'Content-Type': 'application/json'},
      body: payload, // Use the dynamic payload
    );
    
    if (response.statusCode == 200) {
      // Decode the JSON response to get the message
      final jsonResponse = json.decode(response.body);
      fetchSchedule();
      return jsonResponse['message'] ?? 'Optimization Triggered Successfully!';
    } else {
      final jsonResponse = json.decode(response.body);
      return jsonResponse['message'] ?? 'Optimization Failed: Unknown Error';
    }
  }

  // --- 5. UPDATE TASK STATUS (PATCH /tasks/<id>/status) ---
  Future<String> updateTaskStatus(int taskId, String newStatus) async {
    final url = '$_host/tasks/$taskId/status'; // Construct the specific URL
    
    try {
      final response = await http.patch( // Use http.patch for status updates
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'status': newStatus,
        }),
      );

      if (response.statusCode == 200) {
        // Status updated, refresh the local view immediately
        fetchSchedule(); 
        return json.decode(response.body)['message'] ?? 'Status updated successfully.';
      } else {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to update status.';
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }
  // --- 7 DELETE TASK (DELETE /tasks/<id>) ---
  Future<String> deleteTask(int taskId) async {
    final url = '$_host/tasks/$taskId'; 
    
    try {
      final response = await http.delete(
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        // Task deleted, refresh the local view immediately
        fetchSchedule(); 
        return json.decode(response.body)['message'] ?? 'Task deleted successfully.';
      } else {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to delete task.';
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }

  // --- 11. LOG PRODUCTION RESULTS (POST /api/production_log) ---
  Future<String> logProduction({
    required int taskId,
    required String resourceUsed,
    required int productCount,
  }) async {
    const url = '$_baseUrl/production_log';

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'task_id': taskId,
          'resource_used': resourceUsed,
          'product_count': productCount,
        }),
      );

      final jsonResponse = json.decode(response.body);

      if (response.statusCode == 201) {
        // Log successful, refresh the schedule to show updated status (if needed later)
        fetchSchedule(); 
        return jsonResponse['message'] ?? 'Production log saved successfully.';
      } else {
        return jsonResponse['error'] ?? 'Failed to log production.';
      }
    } catch (e) {
      return 'Network Error: $e';
    }
  }

  // 9 DELETE MACHINE (DELETE /machines/<id>)
  Future<String> deleteMachine(int machineId) async {
    final url = '$_baseUrl/machines/$machineId';

    try {
      final response = await http.delete(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );

      final jsonResponse = json.decode(response.body);

      if (response.statusCode == 200) {
        // CRITICAL: Refresh the list view after a successful deletion
        fetchMachines(); 
        return jsonResponse['message'] ?? 'Machine deleted successfully.';
      } else {
        // Return the error message provided by the backend (e.g., if machine is in use)
        return jsonResponse['message'] ?? 'Failed to delete machine.';
      }
    } catch (e) {
      return 'Network Error: $e';
    }
  }
   // 8 task
  Future<String> editTaskDetails(int taskId, {
    String? name,
    double? durationHours,
    String? machineName,
  }) async {
    final url = '$_host/tasks/$taskId'; 
    
    // Construct payload dynamically
    final Map<String, dynamic> payload = {};
    if (name != null) payload['name'] = name;
    if (durationHours != null) payload['duration_hours'] = durationHours;
    if (machineName != null) payload['machine_name'] = machineName;

    if (payload.isEmpty) {
      return "Error: No details provided to update.";
    }

    try {
      final response = await http.patch( // Use PATCH for partial updates
        Uri.parse(url), 
        headers: {'Content-Type': 'application/json'},
        body: json.encode(payload),
      );

      if (response.statusCode == 200) {
        fetchSchedule(); // Refresh the list view
        return json.decode(response.body)['message'] ?? 'Task details updated successfully.';
      } else {
        final jsonResponse = json.decode(response.body);
        return jsonResponse['message'] ?? 'Failed to update task details.';
      }
    } catch (e) {
      return "Network Error: $e";
    }
  }
}
