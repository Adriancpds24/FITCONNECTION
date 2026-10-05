import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rms/core/theme/theme_provider.dart';
import '../map/map_view.dart';
import 'duelos_view.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/shared/widgets/common/horizontal_tab_swipe_listener.dart';

class SocialView extends ConsumerStatefulWidget {
  /// -1 = pestaña anterior, 1 = pestaña siguiente.
  final ValueChanged<int>? onHorizontalTabSwipe;

  const SocialView({super.key, this.onHorizontalTabSwipe});

  @override
  ConsumerState<SocialView> createState() => _SocialViewState();
}

class _SocialViewState extends ConsumerState<SocialView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Puntos de encuentro',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: FeedPalette.text,
                fontSize: 26,
                letterSpacing: -0.9,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Explora lugares y activa retos con tu comunidad.',
              style: TextStyle(
                color: FeedPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        toolbarHeight: 82,
        backgroundColor: FeedPalette.background,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(58),
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            decoration: BoxDecoration(
              color: FeedPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              labelColor: Colors.white,
              unselectedLabelColor: FeedPalette.muted,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              indicator: BoxDecoration(
                color: FeedPalette.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tabController.index == 0
                          ? Colors.transparent
                          : FeedPalette.surface.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _tabController.index == 0
                            ? Colors.transparent
                            : FeedPalette.border,
                      ),
                    ),
                    child: const Text('Explora cerca'),
                  ),
                ),
                Tab(
                  child: Container(
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _tabController.index == 1
                          ? Colors.transparent
                          : FeedPalette.surface.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _tabController.index == 1
                            ? Colors.transparent
                            : FeedPalette.border,
                      ),
                    ),
                    child: const Text('Retos amigos'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        child: HorizontalTabSwipeListener(
          innerTabController: _tabController,
          onMainTabSwipe: widget.onHorizontalTabSwipe,
          child: TabBarView(
            controller: _tabController,
            physics: const NeverScrollableScrollPhysics(),
            children: const [
              MapView(key: ValueKey('map_tab')),
              DuelosView(key: ValueKey('duelos_tab')),
            ],
          ),
        ),
      ),
    );
  }
}
