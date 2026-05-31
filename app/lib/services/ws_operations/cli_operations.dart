/// cli_operations.dart — CLI list, install, switch, retry, and auth operations.
///
/// Holds a [WebSocketService] reference for methods that need state
/// mutation: [switchCLI] clears messages and resets CLI state,
/// [retryCli] resets CLI state, [setMode] and [setConfigOption]
/// perform optimistic local updates before sending.
library;

import '../../models/protocol.dart';
import '../../models/payloads/auth_payloads.g.dart';
import '../../models/payloads/cli_payloads.g.dart';
import '../../models/payloads/state_payloads.g.dart';
import '../websocket_service.dart';

/// Domain operations for CLI management.
///
/// Most methods are pure senders, but [switchCLI], [retryCli],
/// [setMode], and [setConfigOption] need WebSocketService access
/// for state mutation before sending.
class CliOperations {
  final WebSocketService _ws;

  CliOperations(this._ws);

  /// Request the list of available CLIs from the agent.
  void requestCLIList() =>
      _ws.send(WsMessage(type: MessageType.cliList));

  /// Install an agent CLI by [name].
  void installCLI(String name) => _ws.send(WsMessage(
      type: MessageType.cliInstall,
      payload: CliInstallPayload(cli: name).toJson()));

  /// Uninstall an agent CLI by [name].
  void uninstallCLI(String name) => _ws.send(WsMessage(
      type: MessageType.cliUninstall,
      payload: CliUninstallPayload(cli: name).toJson()));

  /// Switch the default CLI globally (affects both chat and terminal).
  ///
  /// Clears current messages, resets mode/config, and loads
  /// the new CLI's chat history when cli.status=ready arrives.
  void switchCLI(String name) {
    if (name == _ws.defaultCli) return;
    _ws.defaultCli = name;
    _ws.currentModeValue = '';
    _ws.configOptionsValue = [];
    _ws.messages.clear();
    _ws.resetCliState();
    _ws.historyRequestedForCli = false;
    _ws.send(WsMessage(
        type: MessageType.cliSwitch,
        payload: CliSwitchPayload(cli: name).toJson()));
    // History will be loaded when cli.status=ready arrives for the new CLI
    _ws.notifyUI();
  }

  /// Retry CLI initialization after a failure.
  void retryCli({String? cli}) {
    _ws.resetCliState();
    _ws.send(WsMessage(
        type: MessageType.cliRetry,
        payload: CliRetryPayload(cli: cli ?? _ws.defaultCli).toJson()));
  }

  /// Add a custom agent CLI.
  void addCustomCLI({
    required String name,
    required String command,
    required List<String> args,
    required String displayName,
  }) =>
      _ws.send(WsMessage(
          type: MessageType.cliAdd,
          payload: CliAddPayload(
            name: name,
            command: command,
            args: args,
            displayName: displayName,
          ).toJson()));

  /// Remove a custom agent CLI.
  void removeCLI(String name) => _ws.send(WsMessage(
      type: MessageType.cliRemove,
      payload: CliRemovePayload(name: name).toJson()));

  /// Submit authentication credentials for a CLI.
  ///
  /// [methodId] identifies the auth method; [data] contains the credentials.
  void submitAuth(
      {String? cli,
      required String methodId,
      required Map<String, String> data}) {
    _ws.send(WsMessage(
        type: MessageType.authSubmit,
        payload: AuthSubmitPayload(
          cli: cli ?? _ws.defaultCli,
          methodId: methodId,
          data: data,
        ).toJson()));
  }

  /// Switch session mode via ACP.
  ///
  /// Performs an optimistic local update before sending to the agent.
  void setMode(String modeId, {String? cli}) {
    _ws.currentModeValue = modeId; // optimistic update
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.modeSet,
        payload: ModeSetPayload(
          cli: cli ?? _ws.defaultCli,
          modeId: modeId,
        ).toJson()));
  }

  /// Set a config option value via ACP.
  ///
  /// Performs an optimistic local update before sending to the agent.
  void setConfigOption(String configId, dynamic value, {String? cli}) {
    // Optimistic update
    _ws.configOptionsValue = _ws.configOptions.map((o) {
      if (o.id == configId) {
        return ConfigOption(
          id: o.id,
          name: o.name,
          type: o.type,
          description: o.description,
          category: o.category,
          currentValue: value,
          options: o.options,
        );
      }
      return o;
    }).toList();
    _ws.notifyUI();
    _ws.send(WsMessage(
        type: MessageType.configSet,
        payload: ConfigSetPayload(
          cli: cli ?? _ws.defaultCli,
          configId: configId,
          value: value,
        ).toJson()));
  }
}
