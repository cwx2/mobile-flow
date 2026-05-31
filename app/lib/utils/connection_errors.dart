/// connection_errors.dart — Transport-level error to user message mapping.
///
/// Maps transport exceptions and error codes to localized user-friendly
/// error messages for display on ConnectScreen. Technical details
/// are logged at SEVERE level; only the human-readable message is shown.
///
/// Each [ConnectionError] variant corresponds to a specific failure mode
/// documented in the design doc's Error Handling section.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'logger.dart';

final _log = getLogger('ConnectionErrors');

/// Enumeration of connection error types across all transport modes.
///
/// Each variant maps to exactly one localized error message string.
/// The mapping is exhaustive — every transport-level failure the App
/// can encounter has a corresponding user-facing message.
enum ConnectionError {
  /// LAN: OS reports network unreachable / no route to host.
  networkUnreachable,

  /// LAN: TCP connection refused (Agent not listening on that port).
  portRefused,

  /// LAN: auth.result returned success=false, error=invalid_token.
  wrongPairingCode,

  /// Relay: WebSocket connect to relay server failed.
  relayUnreachable,

  /// Tunnel: TLS handshake failed (bad cert, expired, etc.).
  tlsFailure,

  /// Any mode: no response within 5 seconds.
  timeout,

  /// auth.connect returned error=session_expired.
  sessionExpired,

  /// auth.pair returned error=lockout (brute-force protection).
  lockout,

  /// Tunnel: HTTP 401/403 on WebSocket upgrade.
  tunnelAuthFailed,

  /// Catch-all for unrecognised failures.
  generic,
}

/// Map a [ConnectionError] to a localized user-friendly message.
///
/// Requires [context] to resolve the current locale via [S.of].
/// The optional [retryAfterSeconds] is used only for [ConnectionError.lockout]
/// to interpolate the remaining lockout duration into the message.
String connectionErrorMessage(
  BuildContext context,
  ConnectionError error, {
  int? retryAfterSeconds,
}) {
  final s = S.of(context);
  switch (error) {
    case ConnectionError.networkUnreachable:
      return s.connectErrorNetworkUnreachable;
    case ConnectionError.portRefused:
      return s.connectErrorPortRefused;
    case ConnectionError.wrongPairingCode:
      return s.connectErrorWrongPairingCode;
    case ConnectionError.relayUnreachable:
      return s.connectErrorRelayUnreachable;
    case ConnectionError.tlsFailure:
      return s.connectErrorTlsFailure;
    case ConnectionError.timeout:
      return s.connectErrorTimeout;
    case ConnectionError.sessionExpired:
      return s.connectErrorSessionExpired;
    case ConnectionError.lockout:
      return s.connectErrorLockout(retryAfterSeconds ?? 30);
    case ConnectionError.tunnelAuthFailed:
      return s.connectErrorTunnelAuthFailed;
    case ConnectionError.generic:
      return s.connectErrorGeneric;
  }
}

/// Classify a caught exception into a [ConnectionError] variant.
///
/// Inspects the exception's string representation and type to determine
/// the most specific error category. Logs the raw technical detail at
/// SEVERE level so it's available in debug logs.
///
/// [label] is a short tag for the connection mode (e.g. "LAN", "Relay")
/// used in the log message for easier triage.
ConnectionError classifyException(dynamic error, {String context = ''}) {
  final msg = error.toString().toLowerCase();
  final prefix = context.isNotEmpty ? '[$context] ' : '';
  _log.severe('$prefix连接异常: $error');

  // Timeout — check first because TimeoutException is common
  if (error is TimeoutException || msg.contains('timeout') || msg.contains('timed out')) {
    return ConnectionError.timeout;
  }

  // Network unreachable / no route to host
  if (msg.contains('network is unreachable') ||
      msg.contains('no route to host') ||
      msg.contains('host unreachable') ||
      msg.contains('enetunreach') ||
      msg.contains('ehostunreach') ||
      msg.contains('no address associated')) {
    return ConnectionError.networkUnreachable;
  }

  // Connection refused (port not listening)
  if (msg.contains('connection refused') || msg.contains('econnrefused')) {
    return ConnectionError.portRefused;
  }

  // TLS / SSL failures
  if (msg.contains('handshake') ||
      msg.contains('certificate') ||
      msg.contains('ssl') ||
      msg.contains('tls')) {
    return ConnectionError.tlsFailure;
  }

  // HTTP 401/403 (tunnel auth)
  if (msg.contains('401') || msg.contains('403') || msg.contains('tunnel_auth_failed')) {
    return ConnectionError.tunnelAuthFailed;
  }

  // Relay-specific: if the context is relay and we got a socket error
  if (context.toLowerCase() == 'relay' &&
      (msg.contains('socketexception') || msg.contains('websocketexception'))) {
    return ConnectionError.relayUnreachable;
  }

  return ConnectionError.generic;
}

/// Classify an auth.result error code from the Agent into a [ConnectionError].
///
/// The Agent returns structured error codes in auth.result payloads:
/// "invalid_token", "lockout", "session_expired", "token_not_found".
/// This maps them to the corresponding [ConnectionError] variant.
///
/// Returns null if the error code is not recognised (caller should
/// fall back to [ConnectionError.generic]).
ConnectionError? classifyAuthError(String? errorCode) {
  if (errorCode == null) return null;
  switch (errorCode) {
    case 'invalid_token':
      return ConnectionError.wrongPairingCode;
    case 'lockout':
      return ConnectionError.lockout;
    case 'session_expired':
      return ConnectionError.sessionExpired;
    case 'token_not_found':
      return ConnectionError.sessionExpired;
    default:
      return null;
  }
}
