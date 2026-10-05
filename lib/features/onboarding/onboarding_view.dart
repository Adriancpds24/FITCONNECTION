import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:rms/core/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

class OnboardingView extends ConsumerStatefulWidget {
  const OnboardingView({super.key});

  @override
  ConsumerState<OnboardingView> createState() => _OnboardingViewState();
}

class _OnboardingViewState extends ConsumerState<OnboardingView> {
  final PageController _pageController = PageController();
  bool isLastPage = false;

  Future<void> _onDone() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      body: SafeArea(
        child: Stack(
          children: [
            // Background glow
            Positioned(
              top: -100,
              left: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent.withAlpha((255 * 0.15).toInt()),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              right: -50,
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accent.withAlpha((255 * 0.1).toInt()),
                ),
              ),
            ),

            // PageView + controls in a Column so we don't overlay and overflow on small screens.
            Column(
              children: [
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: (index) {
                      setState(() => isLastPage = index == 3);
                    },
                    children: [
                      _buildPage(
                        title: 'Bienvenido a FitConnect',
                        subtitle:
                            'Únete a la mejor comunidad de atletas y lleva tu entrenamiento al siguiente nivel.',
                        lottieAsset: 'assets/animations/onboarding_1.json',
                        iconFallback: Icons.fitness_center_rounded,
                        theme: theme,
                      ),
                      _buildPage(
                        title: 'Configura tus metas',
                        subtitle:
                            'Ya sea perder peso, ganar masa muscular o mantenerte en forma, tenemos un plan y sugerencias de nutrición para ti.',
                        lottieAsset: 'assets/animations/onboarding_2.json',
                        iconFallback: Icons.track_changes_rounded,
                        theme: theme,
                      ),
                      _buildPage(
                        title: 'Conecta con atletas',
                        subtitle:
                            'Comparte tus progresos, historias y rutinas. Encuentra inspiración diaria con nuestra IA y el ecosistema social.',
                        lottieAsset: 'assets/animations/onboarding_3.json',
                        iconFallback: Icons.group_add_rounded,
                        theme: theme,
                      ),
                      _buildThemeSelectionPage(theme),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _onDone,
                        child: Text(
                          'Omitir',
                          style: TextStyle(
                            color: theme.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      SmoothPageIndicator(
                        controller: _pageController,
                        count: 4,
                        effect: ExpandingDotsEffect(
                          activeDotColor: theme.accent,
                          dotColor: theme.surfaceSoft,
                          dotHeight: 8,
                          dotWidth: 8,
                        ),
                      ),
                      isLastPage
                          ? ElevatedButton(
                              onPressed: _onDone,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.accent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 12,
                                ),
                              ),
                              child: const Text(
                                'Empezar',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            )
                          : TextButton(
                              onPressed: () {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 500),
                                  curve: Curves.easeInOut,
                                );
                              },
                              child: Text(
                                'Sig.',
                                style: TextStyle(
                                  color: theme.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required String title,
    required String subtitle,
    required String lottieAsset,
    required IconData iconFallback,
    required AppThemeState theme,
  }) {
    final animHeight =
        (MediaQuery.sizeOf(context).height * 0.34).clamp(180.0, 300.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: animHeight,
                  child: Lottie.asset(
                    lottieAsset,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return _lottieFallbackIcon(
                        theme: theme,
                        iconFallback: iconFallback,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: theme.muted,
                    fontSize: 16,
                    height: 1.5,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _lottieFallbackIcon({
    required AppThemeState theme,
    required IconData iconFallback,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: theme.accent.withAlpha((255 * 0.2).toInt()),
            blurRadius: 30,
            spreadRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.all(40),
      child: Icon(
        iconFallback,
        size: 100,
        color: theme.accent,
      ),
    );
  }

  Widget _buildThemeSelectionPage(AppThemeState theme) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: theme.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: theme.accent.withAlpha((255 * 0.15).toInt()),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(
              Icons.palette_rounded,
              size: 80,
              color: theme.accent,
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Elige tu estilo',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Personaliza la aplicación con tu color favorito. Podrás cambiarlo siempre que quieras desde tu perfil.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.muted,
              fontSize: 16,
              height: 1.5,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildColorOption(
                type: AppThemeType.orange,
                color: const Color(0xFFFF6A2B),
                current: theme.type,
              ),
              const SizedBox(width: 25),
              _buildColorOption(
                type: AppThemeType.green,
                color: const Color(0xFF22C55E),
                current: theme.type,
              ),
              const SizedBox(width: 25),
              _buildColorOption(
                type: AppThemeType.blue,
                color: const Color(0xFF0EA5E9),
                current: theme.type,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorOption({
    required AppThemeType type,
    required Color color,
    required AppThemeType current,
  }) {
    final isSelected = type == current;
    return GestureDetector(
      onTap: () {
        ref.read(themeProvider.notifier).setTheme(type);
      },
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withAlpha((255 * 0.3).toInt()),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
            if (isSelected)
              BoxShadow(
                color: Colors.black.withAlpha((255 * 0.1).toInt()),
                blurRadius: 1,
                spreadRadius: 2,
              ),
          ],
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 30)
            : null,
      ),
    );
  }
}
