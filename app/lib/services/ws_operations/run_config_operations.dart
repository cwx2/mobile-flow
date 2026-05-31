/// run_config_operations.dart — Run Configuration send operations.
///
/// Implements all outbound WebSocket messages for the Run Configuration
/// feature. Stateless sender — constructs and sends messages but does not
/// handle responses. Incoming messages arrive via RunConfigProvider.
///
/// Depends on [MessageSender] interface only — no WebSocketService coupling.
library;

import '../../models/protocol.dart';
import '../ws_message_sender.dart';

/// Domain operations for the Run Configuration feature.
///
/// Stateless sender — constructs and sends messages but does not
/// handle responses. Incoming messages arrive via RunConfigProvider.
class RunConfigOperations {
  final MessageSender _sender;

  RunConfigOperations(this._sender);

  // ── CRUD operations ──

  /// Request the full configuration list from the Agent.
  void requestList() => _sender.send(WsMessage(
        type: MessageType.runConfigList,
        payload: const <String, dynamic>{},
      ));

  /// Create a new configuration of the given [type].
  ///
  /// Optionally pass [initialFields] to override template defaults
  /// (e.g. name, command, working_directory).
  void create(String type, {Map<String, dynamic>? initialFields}) =>
      _sender.send(WsMessage(
        type: MessageType.runConfigCreate,
        payload: <String, dynamic>{
          'type': type,
          if (initialFields != null) 'initial_fields': initialFields,
        },
      ));

  /// Update fields of an existing configuration.
  ///
  /// [updates] is a partial map of field names to new values.
  void update(String configId, Map<String, dynamic> updates) =>
      _sender.send(WsMessage(
        type: MessageType.runConfigUpdate,
        payload: <String, dynamic>{
          'config_id': configId,
          'updates': updates,
        },
      ));

  /// Delete a configuration by ID.
  void delete(String configId) => _sender.send(WsMessage(
        type: MessageType.runConfigDelete,
        payload: <String, dynamic>{
          'config_id': configId,
        },
      ));

  /// Set the selected configuration (or null to clear selection).
  void select(String? configId) => _sender.send(WsMessage(
        type: MessageType.runConfigSelect,
        payload: <String, dynamic>{
          'config_id': configId,
        },
      ));

  // ── Execution operations ──

  /// Start execution of a configuration.
  void start(String configId) => _sender.send(WsMessage(
        type: MessageType.runConfigStart,
        payload: <String, dynamic>{
          'config_id': configId,
        },
      ));

  /// Stop a running configuration.
  void stop(String configId) => _sender.send(WsMessage(
        type: MessageType.runConfigStop,
        payload: <String, dynamic>{
          'config_id': configId,
        },
      ));

  /// Restart a configuration (stop then start).
  void restart(String configId) => _sender.send(WsMessage(
        type: MessageType.runConfigRestart,
        payload: <String, dynamic>{
          'config_id': configId,
        },
      ));

  /// Request current execution status for all configurations.
  void requestStatus() => _sender.send(WsMessage(
        type: MessageType.runConfigStatus,
        payload: const <String, dynamic>{},
      ));
}
