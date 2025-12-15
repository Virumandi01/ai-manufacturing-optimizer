// lib/screens/gantt_chart_widget.dart

import 'package:flutter/material.dart';
import 'package:ai_scheduler_app/models/task.dart';

class GanttChartWidget extends StatelessWidget {
  final List<Task> tasks;

  const GanttChartWidget({super.key, required this.tasks});

  // Simple, deterministic color list for jobs
  Color _getJobColor(int jobId) {
    const List<Color> colors = [
      Colors.blue,
      Colors.red,
      Colors.green,
      Colors.purple,
      Colors.orange,
      Colors.teal,
      Colors.brown,
      Colors.pink,
    ];
    // Cycle through the colors based on job ID
    // Note: Use modulo operator (%) to keep the index within bounds
    return colors[jobId % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    // 1. Filter out tasks without start/end times and find max end time
    final scheduledTasks = tasks.where((t) => t.startTime != null && t.endTime != null).toList();

    if (scheduledTasks.isEmpty) {
      return const Center(
        child: Text("Schedule data incomplete or tasks are missing start/end times."),
      );
    }

    // Determine the overall time boundaries
    final DateTime startTime = scheduledTasks.map((t) => t.startTime!).reduce((a, b) => a.isBefore(b) ? a : b);
    final DateTime endTime = scheduledTasks.map((t) => t.endTime!).reduce((a, b) => a.isAfter(b) ? a : b);
    final double makespanHours = endTime.difference(startTime).inMinutes / 60.0;
    
    // 2. Group tasks by machine for vertical arrangement
    final Map<String, List<Task>> tasksByMachine = {};
    for (var task in scheduledTasks) {
      tasksByMachine.putIfAbsent(task.machineName, () => []).add(task);
    }

    // 3. Extract unique Jobs for the Legend
    final uniqueJobs = scheduledTasks
        .map((t) => {'jobId': t.jobId, 'jobName': 'Job #${t.jobId}'})
        .toSet()
        .toList()
        // Sort by Job ID for consistent legend order
        ..sort((a, b) => (a['jobId'] as int).compareTo(b['jobId'] as int));
    
    // Define a chart width that scales with the makespan but has a minimum
    final double chartBaseWidth = MediaQuery.of(context).size.width * 0.85;
    final double chartScaleFactor = makespanHours > 10 ? makespanHours / 10 : 1.0;
    final double chartWidth = chartBaseWidth * chartScaleFactor;


    // The entire chart needs to be scrollable horizontally if necessary
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal, 
      child: Container(
        // CHANGE THIS LINE to reduce bottom padding from 16.0 to 8.0
        padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0, bottom: 8.0), 
        width: chartWidth, 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Total Duration Display
            Text(
              'Total Schedule Duration (Makespan): ${makespanHours.toStringAsFixed(2)} hours',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 15),

            // Legend (Color Key) - Displays Job ID
            Wrap(
              spacing: 12.0,
              runSpacing: 4.0,
              children: uniqueJobs.map((job) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      color: _getJobColor(job['jobId'] as int),
                    ),
                    const SizedBox(width: 4),
                    Text(job['jobName'] as String, style: const TextStyle(fontSize: 12)),
                  ],
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            
            // Gantt Chart Visualization Area
            // Calculate total vertical height needed
            SizedBox(
              // Give the main chart area height based on number of machines
              height: tasksByMachine.length * 65.0 + 10.0, 
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: tasksByMachine.entries.map((entry) {
                  final machineName = entry.key;
                  final machineTasks = entry.value.toList();
                  
                  // Sort tasks by start time for visual stacking
                  machineTasks.sort((a, b) => a.startTime!.compareTo(b.startTime!));

                  // The actual row for a machine
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          machineName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 5),
                        
                        // Stack for the horizontal task bars
                        SizedBox(
                          height: 35, 
                          width: chartWidth, // Use the calculated chart width
                          child: Stack(
                            children: machineTasks.map((task) {
                              final taskDurationMinutes = task.endTime!.difference(task.startTime!).inMinutes;
                              final startOffsetMinutes = task.startTime!.difference(startTime).inMinutes;
                              final totalDurationMinutes = endTime.difference(startTime).inMinutes;
                              
                              // Calculate position and width relative to the makespan (0.0 to 1.0)
                              final leftFraction = startOffsetMinutes / totalDurationMinutes;
                              final widthFraction = taskDurationMinutes / totalDurationMinutes;

                              return Positioned(
                                // Left position as a fraction of the total width
                                left: leftFraction * chartWidth, 
                                width: widthFraction * chartWidth,
                                top: 0,
                                bottom: 0,
                                child: Tooltip(
                                  message: '${task.taskName} (Job #${task.jobId})\n'
                                      'Start: ${task.startTime!.toLocal().toString().split('.')[0]}\n'
                                      'End: ${task.endTime!.toLocal().toString().split('.')[0]}',
                                  child: Container(
                                    height: 30, 
                                    decoration: BoxDecoration(
                                      color: _getJobColor(task.jobId),
                                      borderRadius: BorderRadius.circular(4),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 2, offset: const Offset(1, 1)),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        task.taskName.split(' ').first,
                                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            
            // Time Axis (Simplified for clarity)
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Start: ${startTime.toLocal().toString().split('.')[0]}', style: const TextStyle(fontSize: 12)),
                Text('End: ${endTime.toLocal().toString().split('.')[0]}', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}