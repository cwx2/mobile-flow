/// connect_screen.dart - Connection page with three connection modes.
///
/// The app's "front door" screen. Supports:
///   1. LAN direct (ws://IP:Port + connection password)
///   2. Relay (QR scan / pairing code, E2E encrypted)
///   3. Tunnel direct (wss:// + Bearer Token)
/// Uses design system tokens, GlassCard, brand glow, and AppTextField.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_button.dart';
import '../components/app_text_field.dart';
import '../components/glass_card.dart';
import '../crypto/crypto_module.dart';
import '../crypto/relay_pairing.dart';
import '../services/websocket_service.dart';
import '../theme/theme_extensions.dart';
import '../l10n/app_localizations.dart';
import '../utils/connection_errors.dart';
import '../utils/logger.dart';
import '../utils/qr_parser.dart';
import 'qr_scanner_screen.dart';

final _log = getLogger('ConnectScreen');

enum _ConnectionMode {
  lan,
  relay,
  tunnel,
}

class _ConnectScreenLayout {
  final bool compact;
  final double contentMaxWidth;
  final double horizontalPadding;
  final double topPadding;
  final double heroHaloSize;
  final double heroCoreSize;
  final double heroIconSize;
  final double heroMaxWidth;

  const _ConnectScreenLayout({
    required this.compact,
    required this.contentMaxWidth,
    required this.horizontalPadding,
    required this.topPadding,
    required this.heroHaloSize,
    required this.heroCoreSize,
    required this.heroIconSize,
    required this.heroMaxWidth,
  });

  factory _ConnectScreenLayout.of(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final compact = mediaQuery.size.width < 390;

    return _ConnectScreenLayout(
      compact: compact,
      contentMaxWidth: mediaQuery.size.width < 720 ? 560 : 620,
      horizontalPadding: compact ? 16 : 24,
      topPadding: compact ? 10 : 16,
      heroHaloSize: compact ? 76 : 88,
      heroCoreSize: compact ? 56 : 64,
      heroIconSize: compact ? 24 : 28,
      heroMaxWidth: compact ? 280 : 360,
    );
  }
}

/// Connection screen with LAN, Relay, and Tunnel tabs.
///
/// Shown by [AppRouter] when not connected. Persists last connection
/// info in secure storage and attempts silent auto-connect on launch.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  /// Suppress auto-connect on next ConnectScreen mount.
  /// Call this when user manually disconnects to prevent immediate reconnection.
  static void suppressAutoConnect() {
    _ConnectScreenState._skipAutoConnect = true;
  }

  /// Clear all persisted connection parameters across all modes.
  ///
  /// Intended for a "Forget saved connections" action in Settings.
  /// Clears LAN, Relay, and Tunnel stored credentials including secrets.
  static Future<void> forgetSavedConnections() async {
    const storage = FlutterSecureStorage();
    await Future.wait([
      storage.delete(key: 'conn_lan_host'),
      storage.delete(key: 'conn_lan_port'),
      storage.delete(key: 'conn_lan_token'),
      storage.delete(key: 'conn_relay_code'),
      storage.delete(key: 'conn_tunnel_url'),
      storage.delete(key: 'conn_tunnel_token'),
      storage.delete(key: 'conn_lan_secret'),
      storage.delete(key: 'conn_lan_session_token'),
      storage.delete(key: 'conn_lan_client_id'),
    ]);
    _log.info('已清除所有保存的连接信息');
  }

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Track the previous tab index for reverting cancelled mode switches
  int _previousTabIndex = 0;
  // Guard to prevent re-entrant tab change handling during programmatic revert
  bool _suppressTabListener = false;

  final _lanHostController = TextEditingController();
  final _lanPortController = TextEditingController(text: '9600');
  final _lanTokenController = TextEditingController();
  final _relayCodeController = TextEditingController();
  final _tunnelUrlController = TextEditingController();
  final _tunnelTokenController = TextEditingController();

  // Password visibility toggles
  bool _lanPasswordVisible = false;
  bool _tunnelTokenVisible = false;

  String? _error;
  static const _storage = FlutterSecureStorage();

  /// When true, skip auto-connect on next ConnectScreen mount.
  /// Set by manual disconnect actions to prevent immediate reconnection.
  static bool _skipAutoConnect = false;

  // Mode-specific storage key prefixes to avoid collisions
  static const _keyLanHost = 'conn_lan_host';
  static const _keyLanPort = 'conn_lan_port';
  static const _keyLanToken = 'conn_lan_token';
  static const _keyRelayCode = 'conn_relay_code';
  static const _keyTunnelUrl = 'conn_tunnel_url';
  static const _keyTunnelToken = 'conn_tunnel_token';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadAndAutoConnect();
  }

  /// Handle tab switch - show confirmation dialog if currently connected.
  ///
  /// When the user taps a different tab while connected, we intercept
  /// the switch and ask for confirmation before disconnecting. If the
  /// user cancels, we revert to the previous tab. If not connected,
  /// the switch proceeds freely.
  void _onTabChanged() {
    // TabController fires twice per swipe (once during animation, once after).
    // Only act on the final settled index, and skip programmatic reverts.
    if (_tabController.indexIsChanging || _suppressTabListener) return;

    final newIndex = _tabController.index;
    if (newIndex == _previousTabIndex) return;

    // Check if currently connected via ConnectionService
    final connection = context.read<WebSocketService>();
    final isConnected = connection.connectionManager.isConnected;

    if (!isConnected) {
      // Not connected - allow free tab switch, clear error
      _previousTabIndex = newIndex;
      setState(() => _error = null);
      return;
    }

    // Connected - show confirmation dialog before switching
    _showModeSwitchDialog(newIndex);
  }

  /// Show a confirmation dialog for disconnecting before mode switch.
  ///
  /// On confirm: disconnects current connection and stays on the new tab.
  /// On cancel: reverts to the previous tab index.
  Future<void> _showModeSwitchDialog(int newIndex) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).connectSwitchModeTitle),
        content: Text(S.of(context).connectSwitchModeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(context).commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(S.of(context).commonConfirm),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Disconnect current connection — mark state as disconnected FIRST
      // to prevent the auto-reconnect loop from triggering
      final ws = context.read<WebSocketService>();
      ws.connection?.disconnect();
      await ws.connectionManager.disconnect();
      // Prevent auto-connect from firing when ConnectScreen rebuilds
      _skipAutoConnect = true;
      _previousTabIndex = newIndex;
      setState(() => _error = null);
    } else if (mounted) {
      // Revert to previous tab without triggering the listener again
      _suppressTabListener = true;
      _tabController.animateTo(_previousTabIndex);
      // Reset guard after animation completes
      Future.delayed(const Duration(milliseconds: 350), () {
        _suppressTabListener = false;
      });
    }
  }

  /// Load saved connection info for all three tabs and auto-connect LAN.
  ///
  /// Restores persisted parameters for LAN, Relay, and Tunnel tabs from
  /// secure storage (with SharedPreferences fallback for non-sensitive data).
  /// Only LAN mode attempts silent auto-connect on load.
  Future<void> _loadAndAutoConnect() async {
    // Try secure storage first, fall back to SharedPreferences
    // (SharedPreferences survives hot restart on devices where
    // FlutterSecureStorage gets cleared, e.g. MIUI debug mode)
    var host = await _storage.read(key: _keyLanHost);
    var port = await _storage.read(key: _keyLanPort);
    var token = await _storage.read(key: _keyLanToken);

    // SharedPreferences fallback for all LAN params
    if (host == null || host.isEmpty || token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final spHost = prefs.getString(_keyLanHost);
      final spPort = prefs.getString(_keyLanPort);
      final spToken = prefs.getString(_keyLanToken);
      _log.info('SecureStorage 读取不完整，尝试 SharedPreferences fallback: '
          'host=${spHost ?? "空"}, port=${spPort ?? "空"}, token=${spToken != null ? "有" : "无"}');
      host ??= spHost;
      port ??= spPort;
      token ??= spToken;
    }

    // Restore Relay params (secure storage + SharedPreferences fallback)
    var relayCode = await _storage.read(key: _keyRelayCode);
    if (relayCode == null || relayCode.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      relayCode = prefs.getString(_keyRelayCode);
    }

    // Restore Tunnel params (secure storage + SharedPreferences fallback)
    var tunnelUrl = await _storage.read(key: _keyTunnelUrl);
    var tunnelToken = await _storage.read(key: _keyTunnelToken);
    if (tunnelUrl == null || tunnelUrl.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      tunnelUrl = prefs.getString(_keyTunnelUrl);
      tunnelToken ??= prefs.getString(_keyTunnelToken);
    }

    if (mounted) {
      setState(() {
        // LAN tab
        if (host != null && host.isNotEmpty) _lanHostController.text = host;
        if (port != null) _lanPortController.text = port;
        if (token != null) _lanTokenController.text = token;
        // Relay tab
        if (relayCode != null && relayCode.isNotEmpty) {
          _relayCodeController.text = relayCode;
        }
        // Tunnel tab
        if (tunnelUrl != null && tunnelUrl.isNotEmpty) {
          _tunnelUrlController.text = tunnelUrl;
        }
        if (tunnelToken != null && tunnelToken.isNotEmpty) {
          _tunnelTokenController.text = tunnelToken;
        }
      });
    }

    // Silent auto-connect for LAN only
    // Strategy: try session_token first (no pairing needed), fall back to password
    _log.info('自动连接检查: host=${host ?? "空"}, port=${port ?? "空"}, token=${token != null ? "有" : "无"}');

    // Skip auto-connect if user just manually disconnected
    if (_skipAutoConnect) {
      _skipAutoConnect = false;
      _log.info('跳过自动连接（用户主动断开）');
      return;
    }
    if (host != null && host.isNotEmpty) {
      final ws = context.read<WebSocketService>();
      final portNum = int.tryParse(port ?? '9600') ?? 9600;

      try {
        // Try 1: reconnect with saved session_token (fast, no password needed)
        final sessionToken = await _storage.read(key: 'conn_lan_session_token');
        if (sessionToken != null && sessionToken.isNotEmpty) {
          _log.info('尝试 session_token 自动重连: $host:$portNum');
          final ok = await ws.reconnectWithSession(host, portNum, sessionToken);
          if (ok && mounted) {
            HapticFeedback.heavyImpact();
            return;
          }
          _log.info('session_token 重连失败，尝试连接密码');
        }

        // Try 2: fall back to saved password (persistent, survives Agent restart)
        if (token != null && token.isNotEmpty) {
          final ok = await ws.connect(host, portNum, token);
          if (ok && mounted) HapticFeedback.heavyImpact();
        }
      } catch (e) {
        // Auto-connect is best-effort; log and let user retry manually.
        // Ensures _isConnecting is never stuck on true.
        _log.warning('自动连接异常: $e');
      }
    }
  }

  /// Persist LAN connection info to both secure storage and SharedPreferences.
  ///
  /// Dual-write strategy: secure storage for encryption, SharedPreferences
  /// as fallback for devices where secure storage gets cleared on hot
  /// restart (e.g. MIUI debug mode).
  Future<void> _saveConnectionInfo(String host, int port, String token) async {
    _log.info('保存连接信息: host=$host, port=$port, token=${token.isNotEmpty ? "有" : "无"}');
    await _storage.write(key: _keyLanHost, value: host);
    await _storage.write(key: _keyLanPort, value: port.toString());
    await _storage.write(key: _keyLanToken, value: token);
    // SharedPreferences fallback for all LAN params
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLanHost, host);
    await prefs.setString(_keyLanPort, port.toString());
    await prefs.setString(_keyLanToken, token);
    _log.info('连接信息已保存到 SecureStorage + SharedPreferences');
  }

  /// Persist Relay pairing code to both secure storage and SharedPreferences.
  Future<void> _saveRelayInfo(String code) async {
    await _storage.write(key: _keyRelayCode, value: code);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyRelayCode, code);
  }

  /// Persist Tunnel connection info to both secure storage and SharedPreferences.
  Future<void> _saveTunnelInfo(String url, String? token) async {
    await _storage.write(key: _keyTunnelUrl, value: url);
    if (token != null && token.isNotEmpty) {
      await _storage.write(key: _keyTunnelToken, value: token);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTunnelUrl, url);
    if (token != null && token.isNotEmpty) {
      await prefs.setString(_keyTunnelToken, token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ws = context.watch<WebSocketService>();
    final colors = context.colors;
    final spacing = context.spacing;
    final layout = _ConnectScreenLayout.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: min(layout.contentMaxWidth, constraints.maxWidth),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    layout.horizontalPadding,
                    layout.topPadding,
                    layout.horizontalPadding,
                    spacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        alignment: Alignment.topCenter,
                        child: _buildHeroHeader(
                          ws: ws,
                          layout: layout,
                        ),
                      ),
                      SizedBox(height: spacing.lg),
                      _buildModeTabs(),
                      SizedBox(height: spacing.md),
                      // Error banner with smooth appear/disappear
                      AnimatedSize(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: _error != null
                            ? Padding(
                                padding: EdgeInsets.only(bottom: spacing.md),
                                child: _buildErrorBanner(_error!),
                              )
                            : const SizedBox(width: double.infinity, height: 0),
                      ),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _buildLanTab(ws),
                            _buildRelayTab(ws),
                            _buildTunnelTab(ws),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  IconData _modeIcon(_ConnectionMode mode) {
    return switch (mode) {
      _ConnectionMode.lan => Icons.wifi_rounded,
      _ConnectionMode.relay => Icons.hub_rounded,
      _ConnectionMode.tunnel => Icons.cloud_sync_rounded,
    };
  }

  String _modeSupportText(_ConnectionMode mode) {
    return switch (mode) {
      _ConnectionMode.lan => S.of(context).connectLanBadge,
      _ConnectionMode.relay => S.of(context).connectRelayBadge,
      _ConnectionMode.tunnel => S.of(context).connectTunnelBadge,
    };
  }

  Color _modeTint(BuildContext context, _ConnectionMode mode) {
    final colors = context.colors;
    return switch (mode) {
      _ConnectionMode.lan => colors.secondary,
      _ConnectionMode.relay => colors.primary,
      _ConnectionMode.tunnel => colors.warning,
    };
  }

  Widget _buildHeroHeader({
    required WebSocketService ws,
    required _ConnectScreenLayout layout,
  }) {
    final colors = context.colors;
    final typography = context.typography;
    final spacing = context.spacing;
    final connected = ws.connectionManager.isConnected;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: layout.heroMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: layout.heroHaloSize,
            height: layout.heroHaloSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(context.radii.xl),
              color: colors.surfaceVariant.withValues(
                alpha: context.isDark ? 0.72 : 0.92,
              ),
              border: Border.all(color: colors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: colors.scrim
                      .withValues(alpha: context.isDark ? 0.12 : 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Container(
              width: layout.heroCoreSize,
              height: layout.heroCoreSize,
              decoration: BoxDecoration(
                color: colors.secondary.withValues(
                  alpha: context.isDark ? 0.14 : 0.10,
                ),
                borderRadius: BorderRadius.circular(context.radii.lg),
                border: Border.all(
                  color: colors.secondary.withValues(
                    alpha: context.isDark ? 0.18 : 0.12,
                  ),
                ),
              ),
              child: Icon(
                Icons.developer_mode_rounded,
                size: layout.heroIconSize,
                color: colors.secondary,
              ),
            ),
          ),
          SizedBox(height: spacing.lg),
          Text(
            'MobileFlow',
            style: typography.displayLarge,
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.xxs),
          Text(
            S.of(context).connectSubtitle,
            style: typography.bodyMedium.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: spacing.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
                  ),
                  child: child,
                ),
              );
            },
            child: _buildHeroChip(
              key: ValueKey(connected),
              icon: connected
                  ? Icons.check_circle_rounded
                  : Icons.sensors_off_rounded,
              label: connected ? S.of(context).connectStatusConnected : S.of(context).connectStatusWaiting,
              tint: connected ? colors.success : colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroChip({
    Key? key,
    required IconData icon,
    required String label,
    required Color tint,
  }) {
    final typography = context.typography;
    final spacing = context.spacing;
    return Container(
      key: key,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm + spacing.xs,
        vertical: spacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.full),
        border: Border.all(color: tint.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          SizedBox(width: spacing.xs),
          Text(
            label,
            style: typography.labelSmall.copyWith(
              color: tint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabs() {
    final colors = context.colors;
    final typography = context.typography;
    Widget buildTab({
      required String label,
      required IconData icon,
    }) {
      return Tab(
        height: 50,
        iconMargin: const EdgeInsets.only(bottom: 6),
        text: label,
        icon: Icon(icon, size: 18),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceVariant
            .withValues(alpha: context.isDark ? 0.82 : 0.94),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: Border.all(color: colors.borderSubtle),
      ),
      padding: const EdgeInsets.all(3),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(context.radii.md),
          border: Border.all(color: colors.borderSubtle),
        ),
        labelColor: colors.onSurface,
        unselectedLabelColor: colors.onSurfaceMuted,
        labelStyle:
            typography.labelMedium.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle:
            typography.labelMedium.copyWith(fontWeight: FontWeight.w600),
        tabs: [
          buildTab(label: S.of(context).connectLanTab, icon: Icons.wifi_rounded),
          buildTab(label: S.of(context).connectRelayTab, icon: Icons.hub_rounded),
          buildTab(label: S.of(context).connectTunnelTab, icon: Icons.cloud_sync_rounded),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    final colors = context.colors;
    final spacing = context.spacing;
    final typography = context.typography;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
        border: Border.all(color: colors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: colors.error),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              message,
              style: typography.bodySmall.copyWith(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanTab(WebSocketService ws) {
    final spacing = context.spacing;
    return _buildModePanel(
      mode: _ConnectionMode.lan,
      headline: S.of(context).connectLanHeadline,
      description: S.of(context).connectLanDescription,
      fields: [
        AppTextField(
          controller: _lanHostController,
          labelText: S.of(context).connectLanHostLabel,
          hintText: '192.168.1.100',
          prefixIcon: Icons.computer,
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: spacing.md),
        AppTextField(
          controller: _lanPortController,
          labelText: S.of(context).connectLanPortLabel,
          hintText: '9600',
          prefixIcon: Icons.settings_ethernet,
          keyboardType: TextInputType.number,
        ),
        SizedBox(height: spacing.md),
        AppTextField(
          controller: _lanTokenController,
          labelText: S.of(context).connectLanPasswordLabel,
          hintText: S.of(context).connectLanPasswordHint,
          prefixIcon: Icons.vpn_key_rounded,
          obscureText: !_lanPasswordVisible,
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _lanPasswordVisible = !_lanPasswordVisible),
            child: Icon(
              _lanPasswordVisible ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: context.colors.onSurfaceMuted,
            ),
          ),
        ),
      ],
      primaryAction: AppButton(
        label: ws.isConnecting ? S.of(context).connectConnecting : S.of(context).connectConnect,
        loading: ws.isConnecting,
        width: double.infinity,
        onTap: _connectLan,
      ),
    );
  }

  Widget _buildRelayTab(WebSocketService ws) {
    final spacing = context.spacing;
    return _buildModePanel(
      mode: _ConnectionMode.relay,
      headline: S.of(context).connectRelayHeadline,
      description: S.of(context).connectRelayDescription,
      preface: Column(
        children: [
          AppButton(
            label: S.of(context).connectRelayScanQr,
            variant: AppButtonVariant.secondary,
            icon: Icons.qr_code_scanner_rounded,
            width: double.infinity,
            onTap: _scanQrCode,
          ),
          SizedBox(height: spacing.sm),
          Text(
            S.of(context).connectRelayScanNote,
            style: context.typography.bodySmall.copyWith(
              color: context.colors.onSurfaceMuted,
            ),
          ),
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(child: Divider(color: context.colors.borderSubtle)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: spacing.md),
                child: Text(
                  S.of(context).commonOr,
                  style: context.typography.bodySmall.copyWith(
                    color: context.colors.onSurfaceMuted,
                  ),
                ),
              ),
              Expanded(child: Divider(color: context.colors.borderSubtle)),
            ],
          ),
        ],
      ),
      fields: [
        AppTextField(
          controller: _relayCodeController,
          labelText: S.of(context).connectRelayCodeLabel,
          hintText: S.of(context).connectRelayCodeHint,
          prefixIcon: Icons.password_rounded,
        ),
      ],
      primaryAction: AppButton(
        label: ws.isConnecting ? S.of(context).connectConnecting : S.of(context).connectRelayConnect,
        loading: ws.isConnecting,
        width: double.infinity,
        onTap: _connectRelay,
      ),
    );
  }

  Widget _buildTunnelTab(WebSocketService ws) {
    final spacing = context.spacing;
    return _buildModePanel(
      mode: _ConnectionMode.tunnel,
      headline: S.of(context).connectTunnelHeadline,
      description: S.of(context).connectTunnelDescription,
      fields: [
        AppTextField(
          controller: _tunnelUrlController,
          labelText: S.of(context).connectTunnelUrlLabel,
          hintText: 'wss://your-server.com:8765',
          prefixIcon: Icons.link_rounded,
        ),
        SizedBox(height: spacing.md),
        AppTextField(
          controller: _tunnelTokenController,
          labelText: S.of(context).connectTunnelTokenLabel,
          hintText: S.of(context).connectTunnelTokenHint,
          prefixIcon: Icons.key_rounded,
          obscureText: !_tunnelTokenVisible,
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _tunnelTokenVisible = !_tunnelTokenVisible),
            child: Icon(
              _tunnelTokenVisible ? Icons.visibility_off : Icons.visibility,
              size: 20,
              color: context.colors.onSurfaceMuted,
            ),
          ),
        ),
      ],
      primaryAction: AppButton(
        label: ws.isConnecting ? S.of(context).connectConnecting : S.of(context).connectTunnelConnect,
        loading: ws.isConnecting,
        width: double.infinity,
        onTap: _connectTunnel,
      ),
    );
  }

  Widget _buildModePanel({
    required _ConnectionMode mode,
    required String headline,
    required String description,
    required List<Widget> fields,
    required Widget primaryAction,
    Widget? preface,
  }) {
    final spacing = context.spacing;
    final typography = context.typography;
    final tint = _modeTint(context, mode);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return GlassCard(
      enableBlur: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding:
                EdgeInsets.only(bottom: keyboardInset > 0 ? spacing.xs : 0),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildSecurityBadge(
                          _modeSupportText(mode),
                          _modeIcon(mode),
                          tint,
                        ),
                      ],
                    ),
                    SizedBox(height: spacing.md),
                    Text(headline, style: typography.titleMedium),
                    SizedBox(height: spacing.xs),
                    Text(
                      description,
                      style: typography.bodySmall.copyWith(
                        color: context.colors.onSurfaceMuted,
                        height: 1.45,
                      ),
                    ),
                    if (preface != null) ...[
                      SizedBox(height: spacing.md),
                      preface,
                    ],
                    SizedBox(height: spacing.lg),
                    ...fields,
                    const Spacer(),
                    SizedBox(height: spacing.lg),
                    primaryAction,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSecurityBadge(String text, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.spacing.md,
        vertical: context.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.full),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: context.spacing.xs),
          Text(
            text,
            style: context.typography.labelSmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _connectLan() async {
    final host = _lanHostController.text.trim();
    final port = int.tryParse(_lanPortController.text.trim()) ?? 9600;
    final token = _lanTokenController.text.trim();
    if (host.isEmpty) {
      setState(() => _error = S.of(context).connectErrorNoHost);
      return;
    }
    if (token.isEmpty) {
      setState(() => _error = S.of(context).connectErrorNoPassword);
      return;
    }
    _log.info('发起局域网连接: host=$host, port=$port');
    setState(() => _error = null);
    final ws = context.read<WebSocketService>();
    try {
      final ok = await ws.connect(host, port, token);
      if (!ok && mounted) {
        _log.warning('局域网连接失败: host=$host, port=$port');
        setState(
            () => _error = connectionErrorMessage(context, ConnectionError.generic));
      }
      // Save before mounted check — page may navigate away before
      // ws.connect() returns, making mounted=false. Persistence
      // doesn't need UI context.
      if (ok) {
        _saveConnectionInfo(host, port, token);
      }
      if (ok && mounted) {
        _log.info('局域网连接成功: host=$host, port=$port');
        HapticFeedback.heavyImpact();
      }
    } on TimeoutException {
      if (mounted) {
        setState(
            () => _error = connectionErrorMessage(context, ConnectionError.timeout));
      }
    } catch (e) {
      if (mounted) {
        final errType = classifyException(e, context: 'LAN');
        setState(() => _error = connectionErrorMessage(context, errType));
      }
    }
  }

  Future<void> _connectRelay() async {
    _log.info('开始远程中继连接');
    final code = _relayCodeController.text.trim();
    _log.info('配对码长度: ${code.length}');
    if (code.isEmpty) {
      _log.info('配对码为空，设置错误提示');
      if (mounted) {
        setState(() {
          _error = S.of(context).connectErrorNoRelayCode;
          _log.info('_error 已设置为: $_error');
        });
      }
      return;
    }
    _log.info('发起远程中继连接: code=...');
    setState(() => _error = null);
    RelayPairingPayload payload;
    try {
      payload = decodeRelayPairing(code);
    } on FormatException catch (e) {
      _log.warning('配对码解析失败: $e');
      if (mounted) {
        setState(() => _error = S.of(context).connectErrorInvalidRelayCode);
      }
      return;
    } catch (e) {
      _log.warning('配对码解析异常: $e');
      if (mounted) {
        setState(() => _error = S.of(context).connectErrorInvalidRelayCode);
      }
      return;
    }
    CryptoModule crypto;
    try {
      crypto = CryptoModule(payload.sharedSecret);
    } catch (e) {
      _log.severe('加密模块初始化失败: $e');
      setState(() => _error = S.of(context).connectErrorInvalidSecret);
      return;
    }
    final deviceIdHex =
        payload.deviceId.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final ws = context.read<WebSocketService>();
    try {
      final ok = await ws.connectRelay(
        relayUrl: payload.relayUrl,
        deviceId: deviceIdHex,
        targetDeviceId: deviceIdHex,
        crypto: crypto,
      );
      if (!ok && mounted) {
        _log.warning('远程中继连接失败: relay_url=${payload.relayUrl}');
        setState(() =>
            _error = connectionErrorMessage(context, ConnectionError.relayUnreachable));
      }
      if (ok) {
        _saveRelayInfo(code);
      }
      if (ok && mounted) {
        _log.info('远程中继连接成功: relay_url=${payload.relayUrl}');
        HapticFeedback.heavyImpact();
      }
    } on TimeoutException {
      if (mounted) {
        setState(
            () => _error = connectionErrorMessage(context, ConnectionError.timeout));
      }
    } catch (e) {
      if (mounted) {
        final errType = classifyException(e, context: 'Relay');
        setState(() => _error = connectionErrorMessage(context, errType));
      }
    }
  }

  Future<void> _connectTunnel() async {
    final url = _tunnelUrlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = S.of(context).connectErrorNoTunnelUrl);
      return;
    }
    _log.info('发起直连: url=$url');
    setState(() => _error = null);
    final ws = context.read<WebSocketService>();
    final token = _tunnelTokenController.text.trim();
    try {
      final ok = await ws.connectTunnel(
          wssUrl: url, bearerToken: token.isEmpty ? null : token);
      if (!ok && mounted) {
        _log.warning('直连失败: url=$url');
        setState(
            () => _error = connectionErrorMessage(context, ConnectionError.generic));
      }
      if (ok) {
        _saveTunnelInfo(url, token.isEmpty ? null : token);
      }
      if (ok && mounted) {
        _log.info('直连成功: url=$url');
        HapticFeedback.heavyImpact();
      }
    } on TimeoutException {
      if (mounted) {
        setState(
            () => _error = connectionErrorMessage(context, ConnectionError.timeout));
      }
    } catch (e) {
      if (mounted) {
        final errType = classifyException(e, context: 'Tunnel');
        setState(() => _error = connectionErrorMessage(context, errType));
      }
    }
  }

  /// Open QR code scanner for LAN connection pairing.
  ///
  /// Navigates to [QrScannerScreen] which uses the device camera to scan
  /// a mobileflow://connect QR code. On success, auto-fills the LAN fields
  /// and triggers connection. Falls back to relay pairing dialog if the
  /// scanned payload is a relay pairing code instead.
  Future<void> _scanQrCode() async {
    _log.fine('用户触发扫码配对');
    final result = await Navigator.of(context).push<ConnectionParams>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const QrScannerScreen(),
      ),
    );

    if (result == null || !mounted) return;

    _log.info('扫码成功，自动填充连接参数: host=${result.host}, port=${result.port}');

    // Auto-fill LAN fields with scanned parameters
    _lanHostController.text = result.host;
    _lanPortController.text = result.port.toString();
    _lanTokenController.text = result.token;

    // Switch to LAN tab if not already there
    if (_tabController.index != 0) {
      _suppressTabListener = true;
      _tabController.animateTo(0);
      Future.delayed(const Duration(milliseconds: 350), () {
        _suppressTabListener = false;
      });
      _previousTabIndex = 0;
    }

    // Auto-connect with the scanned parameters
    _connectLan();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _lanHostController.dispose();
    _lanPortController.dispose();
    _lanTokenController.dispose();
    _relayCodeController.dispose();
    _tunnelUrlController.dispose();
    _tunnelTokenController.dispose();
    super.dispose();
  }
}
