// WsMessage and MessageType tests
//
// Covers: WsMessage construction, fromJson, toJson, field defaults,
// edge cases (missing fields, extra fields, null payload).

import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/protocol.dart';

void main() {
  group('WsMessage construction', () {
    test('required fields only', () {
      final msg = WsMessage(type: MessageType.chatSend);
      expect(msg.type, MessageType.chatSend);
      expect(msg.id, isNotEmpty);
      expect(msg.timestamp, greaterThan(0));
      expect(msg.payload, isEmpty);
    });

    test('all fields provided', () {
      final msg = WsMessage(
        id: 'test-id',
        type: MessageType.chatStream,
        timestamp: 1000,
        payload: {'chunk': 'hello'},
      );
      expect(msg.id, 'test-id');
      expect(msg.type, MessageType.chatStream);
      expect(msg.timestamp, 1000);
      expect(msg.payload['chunk'], 'hello');
    });

    test('auto-generated id format', () {
      final msg = WsMessage(type: MessageType.statusPing);
      // ID is base-36 encoded millisecond timestamp
      expect(msg.id, isNotEmpty);
      expect(msg.id.length, greaterThan(5));
    });
  });

  group('WsMessage.fromJson', () {
    test('full json', () {
      final msg = WsMessage.fromJson({
        'id': 'abc',
        'type': 'chat.send',
        'timestamp': 12345,
        'payload': {'message': 'hi'},
      });
      expect(msg.id, 'abc');
      expect(msg.type, 'chat.send');
      expect(msg.timestamp, 12345);
      expect(msg.payload['message'], 'hi');
    });

    test('missing optional fields', () {
      final msg = WsMessage.fromJson({
        'type': 'status.ping',
      });
      expect(msg.type, 'status.ping');
      expect(msg.payload, isEmpty);
    });

    test('null payload becomes empty map', () {
      final msg = WsMessage.fromJson({
        'type': 'chat.done',
        'payload': null,
      });
      expect(msg.payload, isEmpty);
    });

    test('extra fields are ignored', () {
      final msg = WsMessage.fromJson({
        'type': 'chat.send',
        'payload': {'message': 'test'},
        'unknown_field': 42,
      });
      expect(msg.type, 'chat.send');
      expect(msg.payload['message'], 'test');
    });
  });

  group('WsMessage.toJson', () {
    test('roundtrip', () {
      final original = WsMessage(
        id: 'rt-1',
        type: MessageType.fileRead,
        timestamp: 9999,
        payload: {'path': 'main.dart'},
      );
      final json = original.toJson();
      final restored = WsMessage.fromJson(json);
      expect(restored.id, original.id);
      expect(restored.type, original.type);
      expect(restored.timestamp, original.timestamp);
      expect(restored.payload['path'], 'main.dart');
    });

    test('toJson structure', () {
      final msg = WsMessage(
        id: 'x',
        type: 'test',
        timestamp: 1,
        payload: {'k': 'v'},
      );
      final json = msg.toJson();
      expect(json.keys, containsAll(['id', 'type', 'timestamp', 'payload']));
      expect(json['id'], 'x');
      expect(json['type'], 'test');
    });
  });

  group('MessageType constants', () {
    test('chat types', () {
      expect(MessageType.chatSend, 'chat.send');
      expect(MessageType.chatStream, 'chat.stream');
      expect(MessageType.chatDone, 'chat.done');
      expect(MessageType.chatError, 'chat.error');
      expect(MessageType.chatCancel, 'chat.cancel');
      expect(MessageType.chatHistory, 'chat.history');
      expect(MessageType.chatHistoryResult, 'chat.history.result');
    });

    test('cli types', () {
      expect(MessageType.cliList, 'cli.list');
      expect(MessageType.cliListResult, 'cli.list.result');
      expect(MessageType.cliStatus, 'cli.status');
      expect(MessageType.cliRetry, 'cli.retry');
    });

    test('file types', () {
      expect(MessageType.fileTree, 'file.tree');
      expect(MessageType.fileRead, 'file.read');
      expect(MessageType.fileWrite, 'file.write');
      expect(MessageType.fileSearch, 'file.search');
      expect(MessageType.fileCreate, 'file.create');
      expect(MessageType.fileDelete, 'file.delete');
    });

    test('git types', () {
      expect(MessageType.gitStatus, 'git.status');
      expect(MessageType.gitCommit, 'git.commit');
      expect(MessageType.gitPush, 'git.push');
      expect(MessageType.gitPull, 'git.pull');
    });

    test('terminal types', () {
      expect(MessageType.terminalStart, 'terminal.start');
      expect(MessageType.terminalOutput, 'terminal.output');
      expect(MessageType.terminalInput, 'terminal.input');
      expect(MessageType.terminalResize, 'terminal.resize');
    });

    test('session types', () {
      expect(MessageType.sessionList, 'session.list');
      expect(MessageType.sessionNew, 'session.new');
      expect(MessageType.sessionSwitch, 'session.switch');
    });

    test('permission types', () {
      expect(MessageType.permissionRequest, 'permission.request');
      expect(MessageType.permissionResponse, 'permission.response');
    });

    test('plugin types', () {
      expect(MessageType.pluginList, 'plugin.list');
      expect(MessageType.pluginEnable, 'plugin.enable');
      expect(MessageType.pluginInstall, 'plugin.install');
      expect(MessageType.pluginConfigGet, 'plugin.config.get');
      expect(MessageType.pluginConfigSet, 'plugin.config.set');
    });
  });
}
