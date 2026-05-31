/// home_screen.dart - Main app frame with bottom navigation.
///
/// Uses Flutter native [NavigationBar] with directional
/// slide + fade tab transitions. [IndexedStack] preserves
/// all tab page states across switches.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/event_bus.dart';
import '../l10n/app_localizations.dart';
import '../services/foreground_service.dart';
import '../theme/theme_extensions.dart';
import '../widgets/connection_banner.dart';
import 'chat_screen.dart';
import 'files_screen.dart';
import 'git_screen.dart';
import 'settings_screen.dart';
import 'test_panel_screen.dart';

/// Main app frame shown after successful connection.
///
/// Contains five tabs (Chat, Files, Git, Test, Settings) managed
/// by [IndexedStack] with a themed native [NavigationBar].
/// Terminal is embedded within the Chat tab, toggled via an AppBar button.
/// Tab switches use a directional slide + fade animation:
/// tapping a tab to the right slides content left, and vice versa.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  int _previousIndex = 0;

  /// Tab switch animation controller.
  late AnimationController _animController;

  /// EventBus reference for cleanup in dispose.
  late AppEventBus _eventBus;

  /// Immersive reading mode flag — set by ChatScreen when user scrolls
  /// up to browse history. Hides the bottom tab bar to maximize
  /// reading space. Reset when user scrolls back to bottom.
  final _immersiveMode = ValueNotifier<bool>(false);

  /// Terminal visibility toggle — shared with ChatScreen so the terminal
  /// can be shown/hidden via the AppBar toggle button or navigateToTerminal event.
  final _showTerminal = ValueNotifier<bool>(false);

  // Each page maintains its own state (not const)
  late final _screens = [
    ChatScreen(immersiveMode: _immersiveMode, showTerminal: _showTerminal),
    const FilesScreen(),
    const GitScreen(),
    const TestPanelScreen(),
    const SettingsScreen(),
  ];

  /// Navigation item configuration.
  static List<_NavItem> _navItems(BuildContext context) => [
    _NavItem(
      icon: Icons.chat_bubble_outline,
      selectedIcon: Icons.chat_bubble,
      label: S.of(context).homeTabChat,
    ),
    _NavItem(
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: S.of(context).homeTabProject,
    ),
    _NavItem(
      icon: Icons.commit_outlined,
      selectedIcon: Icons.commit,
      label: 'Git',
    ),
    _NavItem(
      icon: Icons.science_outlined,
      selectedIcon: Icons.science,
      label: S.of(context).testPanelTab,
    ),
    _NavItem(
      icon: Icons.settings_outlined,
      selectedIcon: Icons.settings,
      label: S.of(context).homeTabSettings,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    // Initial state: fully visible
    _animController.value = 1.0;

    // Listen for navigation events from SendToAiService
    _eventBus = context.read<AppEventBus>();
    _eventBus.on(AppEvents.navigateToChat, _onNavigateToChat);
    _eventBus.on(AppEvents.navigateToTerminal, _onNavigateToTerminal);
    _eventBus.on(AppEvents.navigateToTestPanel, _onNavigateToTestPanel);
  }

  void _onNavigateToChat(Map<String, dynamic> _) {
    _onTabTap(0); // Chat tab is index 0
  }

  void _onNavigateToTerminal(Map<String, dynamic> _) {
    // Terminal is now embedded in chat — switch to chat tab and show terminal
    _onTabTap(0);
    _showTerminal.value = true;
  }

  void _onNavigateToTestPanel(Map<String, dynamic> _) {
    _onTabTap(3); // Test Panel tab is index 3 (after removing terminal tab)
  }

  /// Handle tab tap: directional slide out → switch → slide in.
  void _onTabTap(int index) {
    if (index == _currentIndex) return;

    // Dismiss keyboard before switching tabs to prevent it from
    // re-appearing when the user switches back to the chat tab.
    FocusManager.instance.primaryFocus?.unfocus();

    // Exit immersive mode when leaving chat tab
    if (_currentIndex == 0 && _immersiveMode.value) {
      _immersiveMode.value = false;
    }

    _previousIndex = _currentIndex;

    // Fade out current content, then switch and fade in
    _animController.reverse().then((_) {
      if (mounted) {
        setState(() => _currentIndex = index);
        _animController.forward();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Cache localized notification strings for the foreground service.
    // Safe to call on every build — it just overwrites the same values.
    ForegroundService.init(context);

    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final colors = context.colors;
    final typography = context.typography;

    // Slide direction: positive = moving right (new tab is to the right)
    final goingRight = _currentIndex > _previousIndex;
    // Small horizontal offset for directional feel (3% of width)
    final slideOffset = goingRight ? -0.03 : 0.03;

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          // Global connection status banner (reconnecting / failed)
          const ConnectionBanner(),
          // Tab content with directional slide animation
          Expanded(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (_, child) {
                final t = CurvedAnimation(
                  parent: _animController,
                  curve: Curves.easeOutCubic,
                ).value;
                return Opacity(
                  opacity: t,
                  child: Transform.translate(
                    // Slide from offset to zero as animation progresses
                    offset: Offset(
                      (1 - t) * slideOffset * MediaQuery.of(context).size.width,
                      0,
                    ),
                    child: child,
                  ),
                );
              },
              child: IndexedStack(
                index: _currentIndex,
                children: _screens,
              ),
            ),
          ),
        ],
      ),
      // Bottom nav bar: hidden in immersive reading mode (chat scroll)
      // and when keyboard is visible. AnimatedSize + AnimatedOpacity
      // provide smooth transitions for both cases.
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: _immersiveMode,
        builder: (context, immersive, child) {
          // Hide when keyboard is visible OR immersive reading mode.
          // isKeyboardVisible comes from the outer build() via MediaQuery —
          // both triggers (keyboard change → full rebuild, immersive change
          // → ValueListenableBuilder rebuild) correctly update shouldHide.
          final shouldHide = isKeyboardVisible || (immersive && _currentIndex == 0);
          return ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: shouldHide ? 0 : null,
                child: AnimatedOpacity(
                  opacity: shouldHide ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            border: Border(
              top: BorderSide(
                color: colors.borderSubtle.withValues(alpha: 0.8),
              ),
            ),
          ),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              height: 48,
              backgroundColor: colors.surfaceElevated,
              indicatorColor: colors.primary.withValues(
                alpha: context.isDark ? 0.18 : 0.12,
              ),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                final selected =
                    states.contains(WidgetState.selected);
                return IconThemeData(
                  size: 22,
                  color: selected
                      ? colors.primary
                      : colors.onSurfaceMuted,
                );
              }),
              labelTextStyle:
                  WidgetStateProperty.resolveWith((states) {
                final selected =
                    states.contains(WidgetState.selected);
                return typography.labelSmall.copyWith(
                  color: selected
                      ? colors.onSurface
                      : colors.onSurfaceMuted,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w600,
                );
              }),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: _onTabTap,
              labelBehavior:
                  NavigationDestinationLabelBehavior.alwaysHide,
              destinations: _navItems(context)
                  .map(
                    (item) => NavigationDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: item.label,
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _eventBus.off(AppEvents.navigateToChat, _onNavigateToChat);
    _eventBus.off(AppEvents.navigateToTerminal, _onNavigateToTerminal);
    _eventBus.off(AppEvents.navigateToTestPanel, _onNavigateToTestPanel);
    _animController.dispose();
    _immersiveMode.dispose();
    _showTerminal.dispose();
    super.dispose();
  }
}

class _NavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
