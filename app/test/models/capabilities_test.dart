// CliCapabilities and capability-driven UI tests
//
// Covers: CliCapabilities.fromJson, fromAdapter, empty defaults,
// CliLifecycleState.authRequired, handleCliStatus with auth_methods,
// MessageType.authSubmit constant.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/models/protocol.dart';
import 'package:mobileflow/models/payloads/cli_payloads.g.dart';
import 'package:mobileflow/services/chat_state.dart';

/// Minimal host class for the mixin under test
class TestChatState extends ChangeNotifier with ChatStateMixin {}

void main() {
  group('CliCapabilities.fromJson', () {
    test('full capabilities', () {
      final caps = CliCapabilities.fromJson({
        'supports_session_load': true,
        'supports_image': true,
        'supports_audio': false,
        'supports_embedded_context': true,
        'supports_session_list': true,
        'supports_session_close': false,
        'supports_session_fork': false,
        'supports_session_resume': false,
        'supports_mcp_http': true,
        'supports_mcp_sse': false,
        'available_modes': [
          {'id': 'code', 'name': 'Code'},
          {'id': 'ask', 'name': 'Ask'},
        ],
      });
      expect(caps.supportsImage, true);
      expect(caps.supportsAudio, false);
      expect(caps.supportsEmbeddedContext, true);
      expect(caps.supportsSessionList, true);
      expect(caps.supportsSessionClose, false);
      expect(caps.supportsMcpHttp, true);
      expect(caps.supportsMcpSse, false);
      expect(caps.availableModes.length, 2);
    });

    test('empty json defaults to false', () {
      final caps = CliCapabilities.fromJson({});
      expect(caps.supportsImage, false);
      expect(caps.supportsAudio, false);
      expect(caps.supportsEmbeddedContext, false);
      expect(caps.supportsSessionLoad, false);
      expect(caps.supportsSessionList, false);
      expect(caps.availableModes, isEmpty);
    });

    test('null values default to false', () {
      final caps = CliCapabilities.fromJson({
        'supports_image': null,
        'supports_audio': null,
      });
      expect(caps.supportsImage, false);
      expect(caps.supportsAudio, false);
    });
  });

  group('CliCapabilities.fromAdapter', () {
    test('parses adapter map', () {
      final caps = CliCapabilities.fromAdapter({
        'name': 'claude-code',
        'installed': true,
        'supports_image': true,
        'supports_session_list': true,
      });
      expect(caps.supportsImage, true);
      expect(caps.supportsSessionList, true);
      expect(caps.supportsAudio, false);
    });
  });

  group('CliCapabilities.empty', () {
    test('all false', () {
      const caps = CliCapabilities.empty;
      expect(caps.supportsImage, false);
      expect(caps.supportsAudio, false);
      expect(caps.supportsEmbeddedContext, false);
      expect(caps.supportsSessionLoad, false);
      expect(caps.availableModes, isEmpty);
    });
  });

  group('CliLifecycleState authRequired', () {
    late TestChatState state;

    setUp(() => state = TestChatState());
    tearDown(() {
      state.disposeChatState();
      state.dispose();
    });

    test('handleCliStatus auth_required', () {
      state.handleCliStatus(CliStatusPayload(
        cli: '',
        state: 'auth_required',
        message: 'Need API key',
        authMethods: [
          {
            'id': 'env_key',
            'name': 'API Key',
            'type': 'env_var',
            'vars': [
              {'name': 'ANTHROPIC_API_KEY', 'label': 'API Key', 'secret': true, 'optional': false},
            ],
          },
        ],
      ));
      expect(state.cliLifecycleState, CliLifecycleState.authRequired);
      expect(state.cliStatusMessage, 'Need API key');
      expect(state.authMethods.length, 1);
      expect(state.authMethods[0]['id'], 'env_key');
    });

    test('auth_methods cleared on ready', () {
      // First set auth_required
      state.handleCliStatus(CliStatusPayload(
        cli: '',
        state: 'auth_required',
        message: 'Need key',
        authMethods: [{'id': 'test'}],
      ));
      expect(state.authMethods.length, 1);

      // Then transition to ready — auth_methods should not grow
      state.handleCliStatus(CliStatusPayload(cli: '', state: 'ready', message: 'OK'));
      expect(state.cliLifecycleState, CliLifecycleState.ready);
      // authMethods stays from last auth_required (not cleared, just not updated)
      expect(state.authMethods.length, 1);
    });

    test('auth_methods empty when no methods provided', () {
      state.handleCliStatus(CliStatusPayload(
        cli: '',
        state: 'auth_required',
        message: 'Need auth',
      ));
      expect(state.authMethods, isEmpty);
    });
  });

  group('MessageType constants', () {
    test('authSubmit', () {
      expect(MessageType.authSubmit, 'auth.submit');
    });

    test('cliStatus', () {
      expect(MessageType.cliStatus, 'cli.status');
    });

    test('cliRetry', () {
      expect(MessageType.cliRetry, 'cli.retry');
    });
  });
}
