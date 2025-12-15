// lib/models/task.dart
import 'package:intl/intl.dart';

class Task {
  final int taskId;
  final int jobId;
  final String taskName;
  final double durationHours;
  final String machineName;
  final String status;
  final DateTime? startTime;
  final DateTime? endTime;

  Task({
    required this.taskId,
    required this.jobId,
    required this.taskName,
    required this.durationHours,
    required this.machineName,
    required this.status,
    this.startTime,
    this.endTime,
  });

  // Factory constructor to create a Task object from a JSON map
  factory Task.fromJson(Map<String, dynamic> json) {
    // Helper to parse dates which can be null (if not yet scheduled)
    DateTime? parseDate(dynamic dateValue) {
  if (dateValue == null) return null;

  // If the value is already a String (which it should be from JSON)
  if (dateValue is String) {
    try {
      // Attempt 1: Parse the full RFC 1123 format (e.g., "Sun, 07 Dec 2025 08:56:00 GMT")
      return DateFormat("EEE, dd MMM yyyy HH:mm:ss 'GMT'").parseUtc(dateValue);
    } catch (e) {
      // Attempt 2: Fallback to the standard ISO format if the first fails
      try {
        return DateTime.parse(dateValue).toUtc();
      } catch (e2) {
        return null; // Parsing failed completely
      }
    }
  }
  return null;
}

    return Task(
      taskId: json['task_id'] as int,
      jobId: json['job_id'] as int,
      taskName: json['task_name'] as String,
      // Convert String to double
      durationHours: double.parse(json['duration_hours'].toString()),
      machineName: json['machine_name'] as String,
      status: json['status'] as String,
      startTime: parseDate(json['start_time']),
      endTime: parseDate(json['end_time']),
    );
  }

  get name => null;
}