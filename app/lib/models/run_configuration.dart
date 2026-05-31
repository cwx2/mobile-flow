/// run_configuration.dart — Run Configuration data models.
///
/// Defines the data models for the Run Configuration system:
/// configuration types, lifecycle states, before-run tasks,
/// preview settings, and the main RunConfiguration class.
///
/// JSON serialization uses snake_case keys to match the Python
/// Agent-side models (Pydantic default serialization).
library;

/// Available configuration types.
///
/// Each type determines default behavior and available settings:
/// - preview: Web dev server with reverse proxy for phone access
/// - script: One-off or long-running shell scripts
/// - test: Test runner with optional pattern filtering
/// - custom: Generic command with no type-specific behavior
enum RunConfigType {
  preview,
  script,
  test,
  custom;

  /// Parse from a JSON string value.
  static RunConfigType fromString(String value) => switch (value) {
        'preview' => RunConfigType.preview,
        'script' => RunConfigType.script,
        'test' => RunConfigType.test,
        'custom' => RunConfigType.custom,
        _ => RunConfigType.custom,
      };

  /// Serialize to JSON string value.
  String toJson() => name;
}

/// Process lifecycle states for a running configuration.
///
/// State machine transitions:
///   idle → beforeRun → starting → running → stopping → stopped
enum RunConfigState {
  idle,
  beforeRun,
  starting,
  running,
  stopping,
  stopped;

  /// Parse from a JSON string value (snake_case from Python).
  static RunConfigState fromString(String value) => switch (value) {
        'idle' => RunConfigState.idle,
        'before_run' => RunConfigState.beforeRun,
        'starting' => RunConfigState.starting,
        'running' => RunConfigState.running,
        'stopping' => RunConfigState.stopping,
        'stopped' => RunConfigState.stopped,
        _ => RunConfigState.idle,
      };

  /// Serialize to JSON string value (snake_case for Python).
  String toJson() => switch (this) {
        RunConfigState.idle => 'idle',
        RunConfigState.beforeRun => 'before_run',
        RunConfigState.starting => 'starting',
        RunConfigState.running => 'running',
        RunConfigState.stopping => 'stopping',
        RunConfigState.stopped => 'stopped',
      };
}

/// A prerequisite command that runs before the main configuration.
///
/// Before-run tasks execute sequentially in order. If any enabled task
/// exits with a non-zero code, the entire execution is cancelled.
class BeforeRunTask {
  /// Shell command string to execute.
  final String command;

  /// Optional working directory override.
  final String? workingDirectory;

  /// Whether this task should be executed.
  final bool enabled;

  /// Create a before-run task.
  const BeforeRunTask({
    required this.command,
    this.workingDirectory,
    this.enabled = true,
  });

  /// Deserialize from a JSON map.
  factory BeforeRunTask.fromJson(Map<String, dynamic> json) => BeforeRunTask(
        command: json['command'] as String? ?? '',
        workingDirectory: json['working_directory'] as String?,
        enabled: json['enabled'] as bool? ?? true,
      );

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'command': command,
        'working_directory': workingDirectory,
        'enabled': enabled,
      };
}

/// Additional settings for preview-type configurations.
///
/// Controls how the reverse proxy connects to the target dev server
/// and how the phone WebView interacts with the preview.
class PreviewSettings {
  /// Target URL to proxy (e.g. "http://localhost:3000").
  final String url;

  /// Optional override for the Host header sent to the target.
  final String? hostHeader;

  /// Whether the WebView should reload on file changes.
  final bool autoRefresh;

  /// Create preview settings.
  const PreviewSettings({
    this.url = 'http://localhost:3000',
    this.hostHeader,
    this.autoRefresh = true,
  });

  /// Deserialize from a JSON map.
  factory PreviewSettings.fromJson(Map<String, dynamic> json) =>
      PreviewSettings(
        url: json['url'] as String? ?? 'http://localhost:3000',
        hostHeader: json['host_header'] as String?,
        autoRefresh: json['auto_refresh'] as bool? ?? true,
      );

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'url': url,
        'host_header': hostHeader,
        'auto_refresh': autoRefresh,
      };
}

/// Additional settings for test-type configurations.
///
/// Attributes:
/// - [testPattern]: Optional glob or regex for filtering test files.
class TestSettings {
  /// Optional glob or regex for filtering test files.
  final String? testPattern;

  /// Create test settings.
  const TestSettings({this.testPattern});

  /// Deserialize from a JSON map.
  factory TestSettings.fromJson(Map<String, dynamic> json) => TestSettings(
        testPattern: json['test_pattern'] as String?,
      );

  /// Serialize to a JSON map.
  Map<String, dynamic> toJson() => {
        'test_pattern': testPattern,
      };
}

/// A single run configuration with all fields.
///
/// Represents a named, persisted set of parameters that defines how
/// to run a specific project task. Transmitted over WebSocket from
/// the Agent for display and execution control from the phone.
class RunConfiguration {
  /// Unique identifier (UUID string).
  final String id;

  /// User-visible display name.
  final String name;

  /// Configuration type determining behavior and available settings.
  final RunConfigType type;

  /// Shell command string to execute.
  final String command;

  /// Working directory for the subprocess (null = project root).
  final String? workingDirectory;

  /// Key-value map of environment variable overrides.
  final Map<String, String> environmentVariables;

  /// Whether to inherit the parent process environment.
  final bool passParentEnv;

  /// Whether multiple instances can run simultaneously.
  final bool allowParallel;

  /// Ordered list of prerequisite commands.
  final List<BeforeRunTask> beforeRunTasks;

  /// Whether this is a Quick Run temporary configuration.
  final bool isTemporary;

  /// Optional grouping label for the list UI.
  final String? folderName;

  /// ISO 8601 timestamp of creation.
  final String createdAt;

  /// ISO 8601 timestamp of last execution (null if never run).
  final String? lastUsedAt;

  /// Type-specific settings for preview configurations.
  final PreviewSettings? preview;

  /// Type-specific settings for test configurations.
  final TestSettings? test;

  /// Create a run configuration.
  RunConfiguration({
    required this.id,
    required this.name,
    required this.type,
    this.command = '',
    this.workingDirectory,
    Map<String, String>? environmentVariables,
    this.passParentEnv = true,
    this.allowParallel = false,
    List<BeforeRunTask>? beforeRunTasks,
    this.isTemporary = false,
    this.folderName,
    String? createdAt,
    this.lastUsedAt,
    this.preview,
    this.test,
  })  : environmentVariables = environmentVariables ?? {},
        beforeRunTasks = beforeRunTasks ?? [],
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  /// Deserialize from a JSON map received from the Agent.
  ///
  /// JSON keys use snake_case matching the Python Pydantic model.
  factory RunConfiguration.fromJson(Map<String, dynamic> json) {
    return RunConfiguration(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      type: RunConfigType.fromString(json['type'] as String? ?? 'custom'),
      command: json['command'] as String? ?? '',
      workingDirectory: json['working_directory'] as String?,
      environmentVariables:
          (json['environment_variables'] as Map<String, dynamic>?)
                  ?.map((k, v) => MapEntry(k, v.toString())) ??
              {},
      passParentEnv: json['pass_parent_env'] as bool? ?? true,
      allowParallel: json['allow_parallel'] as bool? ?? false,
      beforeRunTasks: (json['before_run_tasks'] as List<dynamic>?)
              ?.map(
                  (e) => BeforeRunTask.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isTemporary: json['is_temporary'] as bool? ?? false,
      folderName: json['folder_name'] as String?,
      createdAt: json['created_at'] as String? ?? '',
      lastUsedAt: json['last_used_at'] as String?,
      preview: json['preview'] != null
          ? PreviewSettings.fromJson(json['preview'] as Map<String, dynamic>)
          : null,
      test: json['test'] != null
          ? TestSettings.fromJson(json['test'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Serialize to a JSON map for sending to the Agent.
  ///
  /// Uses snake_case keys matching the Python Pydantic model.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.toJson(),
        'command': command,
        'working_directory': workingDirectory,
        'environment_variables': environmentVariables,
        'pass_parent_env': passParentEnv,
        'allow_parallel': allowParallel,
        'before_run_tasks': beforeRunTasks.map((t) => t.toJson()).toList(),
        'is_temporary': isTemporary,
        'folder_name': folderName,
        'created_at': createdAt,
        'last_used_at': lastUsedAt,
        'preview': preview?.toJson(),
        'test': test?.toJson(),
      };
}
