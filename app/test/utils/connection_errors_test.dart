// Feature: connection-architecture-overhaul
//
// Connection error message mapping tests.
//
// Verifies that each ConnectionError variant maps to a unique,
// non-empty localized message, and that classifyException /
// classifyAuthError correctly categorise transport exceptions.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobileflow/l10n/app_localizations.dart';
import 'package:mobileflow/utils/connection_errors.dart';

/// Build a minimal MaterialApp with i18n so we get a valid BuildContext.
Widget _testApp(Widget child) {
  return MaterialApp(
    localizationsDelegates: S.localizationsDelegates,
    supportedLocales: S.supportedLocales,
    locale: const Locale('en'),
    home: child,
  );
}

void main() {
  group('error message mapping', () {
    testWidgets('test_all_errors_have_unique_messages', (tester) async {
      await tester.pumpWidget(_testApp(Builder(builder: (context) {
        final messages = <String>{};
        for (final error in ConnectionError.values) {
          final msg = error == ConnectionError.lockout
              ? connectionErrorMessage(context, error, retryAfterSeconds: 30)
              : connectionErrorMessage(context, error);
          expect(messages.add(msg), isTrue,
              reason: '${error.name} has a duplicate message: "$msg"');
        }
        return const SizedBox.shrink();
      })));
    });

    testWidgets('test_all_errors_have_non_empty_messages', (tester) async {
      await tester.pumpWidget(_testApp(Builder(builder: (context) {
        for (final error in ConnectionError.values) {
          final msg = connectionErrorMessage(context, error);
          expect(msg.isNotEmpty, isTrue,
              reason: '${error.name} has an empty message');
        }
        return const SizedBox.shrink();
      })));
    });

    testWidgets('test_lockout_includes_seconds', (tester) async {
      await tester.pumpWidget(_testApp(Builder(builder: (context) {
        final msg = connectionErrorMessage(
          context,
          ConnectionError.lockout,
          retryAfterSeconds: 45,
        );
        expect(msg, contains('45'));
        return const SizedBox.shrink();
      })));
    });
  });

  group('classifyException', () {
    test('test_classify_timeout_exception', () {
      final result = classifyException(TimeoutException('timed out'));
      expect(result, ConnectionError.timeout);
    });

    test('test_classify_connection_refused', () {
      final result = classifyException(
        Exception('OS Error: Connection refused'),
      );
      expect(result, ConnectionError.portRefused);
    });

    test('test_classify_network_unreachable', () {
      final result = classifyException(
        Exception('OS Error: Network is unreachable'),
      );
      expect(result, ConnectionError.networkUnreachable);
    });

    test('test_classify_401_403', () {
      expect(
        classifyException(Exception('HTTP 401 Unauthorized')),
        ConnectionError.tunnelAuthFailed,
      );
      expect(
        classifyException(Exception('HTTP 403 Forbidden')),
        ConnectionError.tunnelAuthFailed,
      );
    });

    test('test_classify_tls_handshake', () {
      final result = classifyException(
        Exception('HandshakeException: TLS handshake failed'),
      );
      expect(result, ConnectionError.tlsFailure);
    });

    test('test_classify_unknown_error', () {
      final result = classifyException(
        Exception('something completely unexpected'),
      );
      expect(result, ConnectionError.generic);
    });
  });

  group('classifyAuthError', () {
    test('test_classify_auth_error_invalid_token', () {
      expect(
        classifyAuthError('invalid_token'),
        ConnectionError.wrongPairingCode,
      );
    });

    test('test_classify_auth_error_lockout', () {
      expect(classifyAuthError('lockout'), ConnectionError.lockout);
    });

    test('test_classify_auth_error_session_expired', () {
      expect(
        classifyAuthError('session_expired'),
        ConnectionError.sessionExpired,
      );
    });
  });
}
