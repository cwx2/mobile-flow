/// file_node.dart — File tree node model.
///
/// Represents a single node (file or directory) in the project
/// file tree returned by the agent's `file.tree.result` message.

/// A node in the project file tree.
///
/// Each node has a [name], a [type] ("file" or "dir"), an optional
/// [size] in bytes, an optional [gitStatus] indicator, and optional
/// [children] for directory nodes.
class FileNode {
  final String name;
  final String type; // "file" | "dir"
  final int? size;
  final String? gitStatus;
  final List<FileNode>? children;

  FileNode({
    required this.name,
    required this.type,
    this.size,
    this.gitStatus,
    this.children,
  });

  /// Whether this node represents a directory.
  bool get isDir => type == 'dir';

  /// Deserialize from a JSON map (recursive for children).
  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      name: json['name'] as String,
      type: json['type'] as String,
      size: json['size'] as int?,
      gitStatus: json['git_status'] as String?,
      children: json['children'] != null
          ? (json['children'] as List)
              .map((c) => FileNode.fromJson(c as Map<String, dynamic>))
              .toList()
          : null,
    );
  }
}
