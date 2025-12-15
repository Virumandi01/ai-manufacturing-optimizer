// lib/models/machine.dart

class Machine {
  final int machineId;
  final String name;
  final int capacity;

  Machine({
    required this.machineId,
    required this.name,
    required this.capacity,
  });

  factory Machine.fromJson(Map<String, dynamic> json) {
    return Machine(
      machineId: json['machine_id'],
      name: json['name'],
      capacity: json['capacity'] ?? 1,
    );
  }
}