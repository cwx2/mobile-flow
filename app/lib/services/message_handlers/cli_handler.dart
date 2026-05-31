/// cli_handler.dart — Handler for CLI status and list result messages.
library;

import '../../models/protocol.dart';
import '../../models/payloads/cli_payloads.g.dart';
import '../../utils/logger.dart';
import '../../widgets/slash_command_menu.dart';
import '../websocket_service.dart';
import 'message_handler.dart';

final _log = getLogger('CliHandler');

/// Handles CLI lifecycle status and adapter list results.
///
/// Message types: cliStatus, cliListResult, cliCommands.
class CliHandler extends MessageHandler {
  @override
  void handle(WsMessage msg, WebSocketService ws) {
    switch (msg.type) {
      case MessageType.cliStatus:
        _handleCliStatus(msg, ws);
      case MessageType.cliListResult:
        _handleCliListResult(msg, ws);
      case MessageType.cliCommands:
        _handleCliCommands(msg, ws);
    }
  }

  void _handleCliStatus(WsMessage msg, WebSocketService ws) {
    final payload = CliStatusPayload.fromJson(msg.payload);

    // Update capabilities BEFORE handleCliStatus so UI reads fresh data
    // when notifyListeners fires inside handleCliStatus.
    if (payload.capabilities != null && payload.cli.isNotEmpty) {
      ws.cliCapabilitiesMap[payload.cli] =
          CliCapabilities.fromJson(payload.capabilities!);
      _log.fine('[CliStatus] 能力更新: ${payload.cli}, '
          'image=${payload.capabilities!['supports_image']}');
    }

    ws.handleCliStatus(payload);

    // Gate: load chat history only after provider is ready.
    // Before this fix, chat.history was sent immediately from
    // cli.list.result, racing with provider initialization and
    // causing timeouts on slow CLIs (e.g. Qoder ~3s cold start).
    if (payload.state == 'ready' &&
        payload.cli == ws.defaultCli &&
        !ws.historyRequestedForCli) {
      ws.historyRequestedForCli = true;
      ws.chatOps.requestChatHistory();
    }
  }

  void _handleCliListResult(WsMessage msg, WebSocketService ws) {
    final listResult = CliListResultPayload.fromJson(msg.payload);
    final installed = <String>[];
    final displayNames = <String, String>{};

    for (final a in listResult.adapters) {
      final name = a['name']?.toString() ?? '';
      final displayName = a['display_name']?.toString() ?? name;
      if (name.isNotEmpty) {
        displayNames[name] = displayName;
        if (a['installed'] == true) installed.add(name);
      }
    }
    ws.installedClis = installed;
    ws.cliDisplayNames = displayNames;

    // Parse capabilities from each adapter
    for (final a in listResult.adapters) {
      final name = a['name']?.toString() ?? '';
      if (name.isNotEmpty) {
        ws.cliCapabilitiesMap[name] = CliCapabilities.fromAdapter(a);
      }
    }

    final agentDefault = listResult.defaultCli;
    _log.info('CLI 同步: agentDefault=$agentDefault, '
        'appDefault=${ws.defaultCli}, installed=${ws.installedClis.length}');

    // CLI state sync strategy:
    // Agent is the authority. App follows Agent's default_cli.
    // Exception: after Agent restart, Agent has no default but App
    // remembers the last used CLI — App tells Agent to restore it.
    if (agentDefault.isNotEmpty) {
      // Agent has a preference — adopt it
      if (agentDefault != ws.defaultCli) {
        ws.defaultCli = agentDefault;
        ws.messages.clear();
        ws.resetCliState();
        ws.historyRequestedForCli = false;
        // History will be loaded when cli.status=ready arrives
      }
    } else if (ws.defaultCli.isNotEmpty &&
        ws.installedClis.contains(ws.defaultCli)) {
      // Agent has no preference but App remembers a valid CLI — restore it
      ws.send(WsMessage(
          type: MessageType.cliSwitch,
          payload: CliSwitchPayload(cli: ws.defaultCli).toJson()));
      ws.historyRequestedForCli = false;
    } else if (ws.installedClis.isNotEmpty) {
      // Nobody has a preference — auto-select the first installed CLI
      ws.defaultCli = ws.installedClis.first;
      ws.send(WsMessage(
          type: MessageType.cliSwitch,
          payload: CliSwitchPayload(cli: ws.defaultCli).toJson()));
      ws.historyRequestedForCli = false;
    } else {
      // No CLIs installed at all
      ws.defaultCli = '';
      ws.messages.clear();
      ws.resetCliState();
    }
    ws.notifyUI();
  }

  void _handleCliCommands(WsMessage msg, WebSocketService ws) {
    final payload = CliCommandsPayload.fromJson(msg.payload);
    if (payload.cli.isEmpty) {
      _log.warning('cli.commands 缺少 cli 字段，忽略');
      return;
    }

    final commands = payload.commands
        .map((c) => CliCommand(
              name: c['name']?.toString() ?? '',
              description: c['description']?.toString() ?? '',
            ))
        .where((c) => c.name.isNotEmpty)
        .toList();

    _log.fine('CLI 命令接收: cli=${payload.cli}, count=${commands.length}');
    ws.handleCliCommands(payload.cli, commands);
  }
}
