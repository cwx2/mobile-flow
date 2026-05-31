// GENERATED CODE — DO NOT EDIT BY HAND
// Generated from mobileflow_protocol v1
//
// To regenerate, run from pocket-coder/protocol/:
//   python generate_dart_payloads.py
//
// Source: protocol/src/mobileflow_protocol/payloads/project.py

/// Payload for ``project.list`` — list registered projects.
class ProjectListPayload {
  const ProjectListPayload();

  factory ProjectListPayload.fromJson(Map<String, dynamic> json) {
    return const ProjectListPayload();
  }

  Map<String, dynamic> toJson() => {
      };
}

/// Payload for ``project.list.result`` — project list.
class ProjectListResultPayload {
  final List<Map<String, dynamic>> projects;

  const ProjectListResultPayload({
    this.projects = const [],
  });

  factory ProjectListResultPayload.fromJson(Map<String, dynamic> json) {
    return ProjectListResultPayload(
      projects: (json['projects'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'projects': projects,
      };
}

/// Payload for ``project.add`` — add a project directory.
class ProjectAddPayload {
  final String path;
  final String? name;

  const ProjectAddPayload({
    required this.path,
    this.name = null,
  });

  factory ProjectAddPayload.fromJson(Map<String, dynamic> json) {
    return ProjectAddPayload(
      path: json['path'] as String? ?? '',
      name: json['name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
      };
}

/// Payload for ``project.remove`` — remove a project.
class ProjectRemovePayload {
  final String path;

  const ProjectRemovePayload({
    required this.path,
  });

  factory ProjectRemovePayload.fromJson(Map<String, dynamic> json) {
    return ProjectRemovePayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``project.switch`` — switch active project.
class ProjectSwitchPayload {
  final String path;

  const ProjectSwitchPayload({
    required this.path,
  });

  factory ProjectSwitchPayload.fromJson(Map<String, dynamic> json) {
    return ProjectSwitchPayload(
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
      };
}

/// Payload for ``project.current`` — current project info.
class ProjectCurrentPayload {
  final String name;
  final String path;

  const ProjectCurrentPayload({
    this.name = '',
    this.path = '',
  });

  factory ProjectCurrentPayload.fromJson(Map<String, dynamic> json) {
    return ProjectCurrentPayload(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
      };
}

/// Payload for ``project.search`` — search/browse for projects.
class ProjectSearchPayload {
  final String query;
  final String? path;
  final int? maxResults;

  const ProjectSearchPayload({
    this.query = '',
    this.path = null,
    this.maxResults = null,
  });

  factory ProjectSearchPayload.fromJson(Map<String, dynamic> json) {
    return ProjectSearchPayload(
      query: json['query'] as String? ?? '',
      path: json['path'] as String?,
      maxResults: json['max_results'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'query': query,
        'path': path,
        'max_results': maxResults,
      };
}

/// Payload for ``project.search.result`` — search results.
class ProjectSearchResultPayload {
  final List<Map<String, dynamic>> results;
  final bool isBrowsing;
  final String currentPath;
  final bool isComplete;
  final String? error;

  const ProjectSearchResultPayload({
    this.results = const [],
    this.isBrowsing = false,
    this.currentPath = '',
    this.isComplete = true,
    this.error = null,
  });

  factory ProjectSearchResultPayload.fromJson(Map<String, dynamic> json) {
    return ProjectSearchResultPayload(
      results: (json['results'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList(),
      isBrowsing: json['is_browsing'] as bool? ?? false,
      currentPath: json['current_path'] as String? ?? '',
      isComplete: json['is_complete'] as bool? ?? false,
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'results': results,
        'is_browsing': isBrowsing,
        'current_path': currentPath,
        'is_complete': isComplete,
        'error': error,
      };
}
