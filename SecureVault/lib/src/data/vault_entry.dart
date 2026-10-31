import 'dart:convert';

enum VaultCategory { social, banking, work, other }

class VaultEntry {
  const VaultEntry({
    required this.id,
    required this.title,
    required this.site,
    required this.username,
    required this.password,
    required this.notes,
    required this.category,
    required this.favorite,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String site;
  final String username;
  final String password;
  final String notes;
  final VaultCategory category;
  final bool favorite;
  final DateTime updatedAt;

  Map<String, Object> toJson() => {
        'id': id,
        'title': title,
        'site': site,
        'username': username,
        'password': password,
        'notes': notes,
        'category': category.name,
        'favorite': favorite,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory VaultEntry.fromJson(Map<String, dynamic> json) => VaultEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        site: json['site'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String,
        notes: json['notes'] as String? ?? '',
        category: VaultCategory.values.firstWhere(
          (value) => value.name == json['category'],
          orElse: () => VaultCategory.other,
        ),
        favorite: json['favorite'] as bool? ?? false,
        updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
      );
}

String entriesToJson(List<VaultEntry> entries) =>
    jsonEncode(entries.map((entry) => entry.toJson()).toList());

List<VaultEntry> entriesFromJson(String value) =>
    (jsonDecode(value) as List<dynamic>)
        .map((entry) => VaultEntry.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
