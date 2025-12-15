// lib/main.dart (COMPLETE REPLACEMENT)

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/schedule_screen.dart'; 
import 'screens/resource_management_screen.dart'; // Handles Machines
import 'screens/production_log_screen.dart';     // Handles Production Logging
import 'services/api_service.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => ApiService(),
      child: const ManufacturingApp(),
    ),
  );
}

class ManufacturingApp extends StatelessWidget {
  const ManufacturingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Manufacturing Scheduler',
      // We are adding the simple blue theme back, as you requested to hold off on UI polish
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainTabView(), // Use the new tab view as the home screen
    );
  }
}


// --- New MainTabView Widget for Tabs (The new "home" screen) ---
class MainTabView extends StatelessWidget {
  const MainTabView({super.key});

  @override
  Widget build(BuildContext context) {
    // Manages the Schedule, Resources, and Production Log tabs
    return DefaultTabController(
      length: 3, // *** CRITICAL CHANGE: We now have 3 tabs ***
      child: Scaffold(
        appBar: AppBar(
          title: const Text('AI Manufacturing Scheduler'),
          // TabBar placed at the bottom of the AppBar
          bottom: const TabBar(
            tabs: [
              // Tab 1: Schedule
              Tab(icon: Icon(Icons.calendar_today), text: 'Schedule'),
              // Tab 2: Resources (Machines)
              Tab(icon: Icon(Icons.precision_manufacturing), text: 'Resources'),
              // Tab 3: Production Log (The New Feature)
              Tab(icon: Icon(Icons.inventory), text: 'Log Production'),
            ],
            // Use the default theme colors
          ),
        ),
        
        // The body shows the content of the selected tab
        body: const TabBarView(
          children: [
            ScheduleScreen(), 
            ResourceManagementScreen(), 
            ProductionLogScreen(), // The new production log screen
          ],
        ),
      ),
    );
  }
}