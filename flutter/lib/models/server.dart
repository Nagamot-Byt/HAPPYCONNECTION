class Server {
  final String name;
  final String code;
  final String address;
  final int port;
  final String department;
  final String description;
  final bool enabled;
  final String icon;
  final bool priority;

  Server({
    required this.name,
    required this.code,
    required this.address,
    required this.port,
    required this.department,
    required this.description,
    required this.enabled,
    required this.icon,
    this.priority = false,
  });

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      name: json['name'],
      code: json['code'],
      address: json['address'],
      port: json['port'],
      department: json['department'],
      description: json['description'],
      enabled: json['enabled'],
      icon: json['icon'],
      priority: json['priority'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'code': code,
    'address': address,
    'port': port,
    'department': department,
    'description': description,
    'enabled': enabled,
    'icon': icon,
    'priority': priority,
  };
}
