import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:rms/features/admin/admin_dashboard.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/features/chat/chat_realtime_service.dart';
import 'package:rms/features/entrenamiento/entrenamiento_view.dart';
import 'package:rms/features/home/home.dart';
import 'package:rms/features/nutricion/nutricion_view.dart';
import 'package:rms/features/profile/profile_view.dart';
import 'package:rms/features/social/social_view.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/core/theme/theme_provider.dart';

class _MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
      };
}

class MainNavigationScreen extends ConsumerStatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  ConsumerState<MainNavigationScreen> createState() =>
      _MainNavigationScreenState();
}

class _MainNavigationScreenState extends ConsumerState<MainNavigationScreen> {
  int _currentIndex = 0;
  bool _hideBottomBar = false;
  late PageController _pageController;

  static const List<_NavItemData> _baseItems = [
    _NavItemData(icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    _NavItemData(
      icon: Icons.fitness_center_outlined,
      activeIcon: Icons.fitness_center_rounded,
    ),
    _NavItemData(
      icon: Icons.restaurant_outlined,
      activeIcon: Icons.restaurant_rounded,
    ),
    _NavItemData(
      icon: Icons.explore_outlined,
      activeIcon: Icons.explore_rounded,
    ),
    _NavItemData(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];

  static const _adminItem = _NavItemData(
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings_rounded,
  );

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
    ChatRealtimeService.instance.connect();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<Widget> _buildScreens() {
    final screens = <Widget>[
      HomePage(
        onCameraModeChanged: (isInCamera) {
          if (_hideBottomBar == isInCamera) return;
          setState(() {
            _hideBottomBar = isInCamera;
          });
        },
        onHorizontalTabSwipe: _changeTabByOffset,
      ),
      EntrenamientoView(onHorizontalTabSwipe: _changeTabByOffset),
      NutricionView(onHorizontalTabSwipe: _changeTabByOffset),
      SocialView(onHorizontalTabSwipe: _changeTabByOffset),
      ProfileView(),
    ];

    if (AuthService().isAdmin) {
      screens.add(const AdminDashboardPage());
    }

    return screens;
  }

  List<_NavItemData> _buildItems() {
    final items = List<_NavItemData>.from(_baseItems);
    if (AuthService().isAdmin) {
      items.add(_adminItem);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final screens = _buildScreens();
    final items = _buildItems();
    final safeIndex = _currentIndex.clamp(0, screens.length - 1);

    // Sincronizar FeedPalette con el estado actual
    FeedPalette.update(ref.watch(themeProvider));

    return Scaffold(
      extendBody: true,
      body: ScrollConfiguration(
        behavior: _MyCustomScrollBehavior(),
        child: PageView(
          controller: _pageController,
          // Solo cambia de pestaña con la barra inferior o un deslizamiento intencional.
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            if (_currentIndex == index) return;
            setState(() {
              _currentIndex = index;
            });
          },
          children: screens,
        ),
      ),
      bottomNavigationBar: _hideBottomBar
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [FeedPalette.surfaceSoft, FeedPalette.background],
                  ),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: FeedPalette.border),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF9A5A34).withValues(alpha: 0.16),
                      blurRadius: 24,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < items.length; index++)
                      Expanded(
                        child: _buildNavItem(
                          item: items[index],
                          isSelected: safeIndex == index,
                          onTap: () => _handleNavigationTap(index),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  void _changeTabByOffset(int offset) {
    final screens = _buildScreens();
    final nextIndex = (_currentIndex + offset).clamp(0, screens.length - 1);
    if (nextIndex == _currentIndex) return;
    _handleNavigationTap(nextIndex);
  }

  void _handleNavigationTap(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  Widget _buildNavItem({
    required _NavItemData item,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 58;
        final horizontalMargin = compact ? 2.0 : 6.0;
        final selectedHorizontalPadding = compact ? 8.0 : 14.0;
        final normalHorizontalPadding = compact ? 6.0 : 10.0;
        final selectedVerticalPadding = compact ? 10.0 : 12.0;
        final normalVerticalPadding = compact ? 8.0 : 10.0;
        final selectedIconSize = compact ? 22.0 : 26.0;
        final normalIconSize = compact ? 21.0 : 24.0;

        final content = AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
          padding: EdgeInsets.symmetric(
            horizontal: isSelected
                ? selectedHorizontalPadding
                : normalHorizontalPadding,
            vertical:
                isSelected ? selectedVerticalPadding : normalVerticalPadding,
          ),
          decoration: BoxDecoration(
            color: isSelected ? FeedPalette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: FeedPalette.accent.withValues(alpha: 0.28),
                      blurRadius: compact ? 10 : 16,
                      offset: Offset(0, compact ? 5 : 8),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isSelected ? item.activeIcon : item.icon,
                color: isSelected ? Colors.white : FeedPalette.muted,
                size: isSelected ? selectedIconSize : normalIconSize,
              ),
            ],
          ),
        );

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: content,
          ),
        );
      },
    );
  }
}

class _NavItemData {
  final IconData icon;
  final IconData activeIcon;

  const _NavItemData({required this.icon, required this.activeIcon});
}
