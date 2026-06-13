/// A folder for organizing notes. Folders may be nested via [parentId].
class Folder {
  Folder({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  final String id;
  String name;

  /// Parent folder id, or null for a top-level folder.
  String? parentId;

  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Folder.fromJson(Map<String, dynamic> json) => Folder(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Folder',
        parentId: json['parentId'] as String?,
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
      );
}
