import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:rms/core/constants/api_constants.dart';
import 'package:rms/core/utils/url_utils.dart';
import 'package:rms/features/auth/auth_service.dart';
import 'package:rms/core/l10n/fitconnect_localizations.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/shared/widgets/common/horizontal_tab_swipe_listener.dart';

import 'nutrition_ai_service.dart';
import 'nutrition_chatbot_page.dart';
import 'recipe_detail_page.dart';
import 'recipes_data.dart';
import 'user_metrics_form.dart';

class NutricionView extends StatefulWidget {
  final ValueChanged<int>? onHorizontalTabSwipe;

  const NutricionView({super.key, this.onHorizontalTabSwipe});

  @override
  State<NutricionView> createState() => _NutricionViewState();
}

class _NutricionViewState extends State<NutricionView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final NutritionAIService _nutritionService = NutritionAIService();

  static const List<String> _mealSlots = <String>[
    'Desayuno',
    'Media Mañana',
    'Comida',
    'Merienda',
    'Cena',
  ];

  Map<String, dynamic>? _userMetrics;
  bool _isLoadingMetrics = true;
  String? _apiErrorMessage;

  String _recipeFilter = 'Todos';
  List<Map<String, dynamic>> _catalogFoodRecipes = [];

  bool _isLoadingToday = true;
  List<Map<String, dynamic>> _todayMeals = [];

  DateTime _historyMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isLoadingMonth = true;
  Map<String, int> _monthCaloriesByDate = {};

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return DateTime.tryParse(value);
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _bootstrap();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadUserMetrics();
    await Future.wait([
      _loadTodayMeals(),
      _loadMonthlySummary(_historyMonth),
      _loadCatalogFoods(),
    ]);
  }

  Future<void> _loadCatalogFoods() async {
    try {
      final token = AuthService().token;
      if (token == null || token.isEmpty) return;

      final response = await http.get(
        Uri.parse('${ApiConstants.nutritionBaseUrl}/foods'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );

      if (response.statusCode != 200 || !mounted) return;

      final rows = List<Map<String, dynamic>>.from(json.decode(response.body));
      setState(() {
        _catalogFoodRecipes = rows.map(_foodRowToRecipe).toList();
      });
    } catch (e) {
      debugPrint('NutricionView._loadCatalogFoods: $e');
    }
  }

  Map<String, dynamic> _foodRowToRecipe(Map<String, dynamic> food) {
    final category = food['category']?.toString().trim();
    final tag =
        (category != null && category.isNotEmpty) ? category : 'Mantenimiento';

    return {
      'title': food['name']?.toString() ?? 'Alimento',
      'description':
          'Catalogo admin · ${_toInt(food['protein'])}g proteina · ${_toInt(food['carbs'])}g carbos · ${_toInt(food['fat'])}g grasa',
      'image':
          'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=800&q=80',
      'calories': _toInt(food['calories']),
      'tags': [tag],
      'ingredients': [
        'Proteina: ${_toInt(food['protein'])} g',
        'Carbohidratos: ${_toInt(food['carbs'])} g',
        'Grasas: ${_toInt(food['fat'])} g',
      ],
      'steps': const [
        'Prepara el alimento segun tu plan del dia.',
        'Registra la porcion en tu diario nutricional.',
      ],
      'catalogFoodId': food['id'],
    };
  }

  List<Map<String, dynamic>> get _allRecipes => [
        ...nutritionRecipes,
        ..._catalogFoodRecipes,
      ];

  Future<void> _loadUserMetrics() async {
    try {
      if (mounted) setState(() => _apiErrorMessage = null);
      final token = AuthService().token;
      final response = await http.get(
        Uri.parse('${ApiConstants.apiHost}/nutrition/metrics'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;
      if (response.statusCode == 200) {
        Map<String, dynamic>? metrics;
        try {
          final decoded = json.decode(response.body);
          if (decoded is Map<String, dynamic>) {
            if (decoded['hasMetrics'] == false) {
              metrics = null;
            } else if (decoded['hasMetrics'] == true &&
                decoded['metrics'] is Map) {
              metrics = Map<String, dynamic>.from(decoded['metrics'] as Map);
            } else if (decoded.containsKey('calories') ||
                decoded.containsKey('userId')) {
              metrics = decoded;
            }
          }
        } catch (_) {
          metrics = null;
        }
        setState(() {
          _userMetrics = metrics;
          _isLoadingMetrics = false;
          if (metrics == null) {
            _apiErrorMessage = null;
          }
        });
      } else if (response.statusCode == 404) {
        setState(() {
          _userMetrics = null;
          _isLoadingMetrics = false;
          _apiErrorMessage = null;
        });
      } else {
        if (!mounted) return;
        final msg =
            FitconnectLocalizations.of(context).nutritionMetricsLoadError;
        setState(() {
          _isLoadingMetrics = false;
          _apiErrorMessage = msg;
        });
      }
    } catch (e) {
      debugPrint('Error loading metrics: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMetrics = false;
        _apiErrorMessage =
            'No se puede conectar con el servidor. Revisa que el backend esté funcionando o configura API_BASE_URL para apuntar a tu servidor.';
      });
    }
  }

  Future<void> _loadTodayMeals() async {
    if (!mounted) return;
    setState(() => _isLoadingToday = true);
    try {
      final meals = await _nutritionService.getTodayMeals();
      if (!mounted) return;
      setState(() {
        _todayMeals = meals;
        _isLoadingToday = false;
        _apiErrorMessage = null;
      });
    } catch (e) {
      debugPrint('Error loading today meals: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingToday = false;
        _apiErrorMessage =
            'No se han podido cargar las comidas de hoy. Comprueba la conexión con el servidor.';
      });
    }
  }

  Future<void> _loadMonthlySummary(DateTime month) async {
    if (!mounted) return;
    setState(() => _isLoadingMonth = true);
    try {
      final days = await _nutritionService.getMonthlySummary(
        year: month.year,
        month: month.month,
      );

      final map = <String, int>{};
      for (final row in days) {
        final date = row['date'];
        if (date is String) {
          final kcal = _toInt(row['calories']);
          if (kcal > 0) map[date] = kcal;
        }
      }

      if (!mounted) return;
      setState(() {
        _monthCaloriesByDate = map;
        _isLoadingMonth = false;
        _apiErrorMessage = null;
      });
    } catch (e) {
      debugPrint('Error loading monthly summary: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMonth = false;
        _apiErrorMessage =
            'No se ha podido cargar el historial mensual. Comprueba la conexión con el servidor.';
      });
    }
  }

  Map<String, int> _computeTotals(List<Map<String, dynamic>> meals) {
    var calories = 0;
    var protein = 0;
    var carbs = 0;
    var fat = 0;

    for (final meal in meals) {
      calories += _toInt(meal['calorias']);
      protein += _toInt(meal['proteinas']);
      carbs += _toInt(meal['carbohidratos']);
      fat += _toInt(meal['grasas']);
    }

    return {
      'calories': calories,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
    };
  }

  Map<String, Map<String, dynamic>> _groupMealsBySlot(
      List<Map<String, dynamic>> meals) {
    final result = <String, Map<String, dynamic>>{};
    for (final meal in meals) {
      final rawType = (meal['mealType'] ?? '').toString();
      final type = rawType == 'Almuerzo' ? 'Media Mañana' : rawType;
      if (_mealSlots.contains(type) && !result.containsKey(type)) {
        // Normalize legacy "Almuerzo" -> "Media Mañana" so it shows in the right slot.
        if (rawType != type) {
          final normalized = Map<String, dynamic>.from(meal);
          normalized['mealType'] = type;
          result[type] = normalized;
        } else {
          result[type] = meal;
        }
      }
    }
    return result;
  }

  Future<void> _openNutritionChatbot() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const NutritionChatbotPage()),
    );
    await _loadTodayMeals();
    await _loadMonthlySummary(_historyMonth);
  }

  String? _caloriesOverMessage({
    required int consumed,
    required int goal,
  }) {
    if (goal <= 0) return null;
    final over = consumed - goal;
    if (over <= 0) return null;
    if (over <= 100) return 'Has superado ligeramente tu objetivo diario.';
    if (over <= 300) {
      return 'Te has pasado de tu objetivo diario. Intenta ajustar las próximas comidas.';
    }
    return 'Has superado bastante tu objetivo diario. Revisa tu planificación nutricional.';
  }

  Color _overBannerColor(int overKcal) {
    final base = FeedPalette.surface;
    final tint = overKcal <= 100
        ? Colors.orange
        : (overKcal <= 300 ? Colors.deepOrange : Colors.red);
    final alpha = FeedPalette.isDark ? 0.22 : 0.12;
    return Color.alphaBlend(tint.withValues(alpha: alpha), base);
  }

  Color _overBannerBorderColor(int overKcal) {
    final tint = overKcal <= 100
        ? Colors.orange
        : (overKcal <= 300 ? Colors.deepOrange : Colors.red);
    final alpha = FeedPalette.isDark ? 0.48 : 0.28;
    return tint.withValues(alpha: alpha);
  }

  static const _weekdayNames = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];
  static const _monthNames = [
    'enero',
    'febrero',
    'marzo',
    'abril',
    'mayo',
    'junio',
    'julio',
    'agosto',
    'septiembre',
    'octubre',
    'noviembre',
    'diciembre',
  ];

  String _formatNutritionDayTitle(DateTime date) {
    final day = _weekdayNames[date.weekday - 1];
    final month = _monthNames[date.month - 1];
    return 'Comidas del $day ${date.day} de $month';
  }

  Future<void> _openDayDetails(String dateIso) async {
    try {
      final data = await _nutritionService.getDay(dateIso: dateIso);
      final meals = (data['meals'] as List?)?.whereType<Map>().toList() ?? [];
      final parsedMeals = meals
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList()
          .cast<Map<String, dynamic>>();

      if (!mounted) return;
      final parsedDate = DateTime.tryParse(dateIso);
      final dayTitle =
          parsedDate != null ? _formatNutritionDayTitle(parsedDate) : 'Tu día';

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          final maxHeight = MediaQuery.sizeOf(context).height * 0.88;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: FeedPalette.border,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      dayTitle,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: FeedPalette.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      parsedMeals.isEmpty
                          ? 'Sin registros de comida'
                          : '${parsedMeals.length} comida${parsedMeals.length == 1 ? '' : 's'} registrada${parsedMeals.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        color: FeedPalette.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (parsedMeals.isEmpty)
                      Text(
                        'No hay comidas registradas.',
                        style: TextStyle(color: FeedPalette.muted),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: parsedMeals.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) => _buildMealCard(
                            parsedMeals[index],
                            showTime: true,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando el día: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingMetrics) {
      return Scaffold(
        backgroundColor: FeedPalette.background,
        body: Center(
          child: CircularProgressIndicator(color: FeedPalette.accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 84,
        title: Text(
          'Nutrición',
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.w800,
          ),
        ),
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
              labelPadding: const EdgeInsets.symmetric(horizontal: 18),
              labelColor: Colors.white,
              unselectedLabelColor: FeedPalette.muted,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: FeedPalette.accent,
                borderRadius: const BorderRadius.all(Radius.circular(16)),
              ),
              tabs: const [
                Tab(text: 'DIARIO'),
                Tab(text: 'RECETAS'),
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
            children: [
              _userMetrics == null
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_apiErrorMessage != null)
                            _buildApiErrorBanner(_apiErrorMessage!),
                          Expanded(
                            child: UserMetricsForm(onSaved: _loadUserMetrics),
                          ),
                        ],
                      ),
                    )
                  : _buildTodayTab(),
              _buildRecipesTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecipesTab() {
    final filtered = _recipeFilter == 'Todos'
        ? _allRecipes
        : _allRecipes
            .where(
                (r) => (r['tags'] as List?)?.contains(_recipeFilter) ?? false)
            .toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: ['Todos', 'Volumen', 'Definición', 'Mantenimiento']
                .map(
                  (f) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        f,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _recipeFilter == f
                              ? Colors.white
                              : FeedPalette.text,
                        ),
                      ),
                      selected: _recipeFilter == f,
                      onSelected: (_) => setState(() => _recipeFilter = f),
                      selectedColor: FeedPalette.accent,
                      backgroundColor: FeedPalette.surfaceSoft,
                      side: BorderSide(
                        color: _recipeFilter == f
                            ? FeedPalette.accent
                            : FeedPalette.border,
                      ),
                      showCheckmark: false,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final r = filtered[index];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => RecipeDetailPage(recipe: r)),
                ),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: FeedPalette.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
                        child: CachedNetworkImage(
                          imageUrl: (r['image'] ?? '').toString(),
                          height: 140,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Icon(Icons.broken_image),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                (r['nombre'] ?? 'Receta').toString(),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            Icon(Icons.flash_on,
                                color: FeedPalette.accent, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              (r['cal'] ?? '').toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTodayTab() {
    final m = _userMetrics;
    if (m == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            FitconnectLocalizations.of(context).nutritionMetricsLoadError,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final totals = _computeTotals(_todayMeals);

    final goalCalories = _toInt(m['calories']);
    final goalProtein = _toInt(m['protein']);
    final goalCarbs = _toInt(m['carbs']);
    final goalFat = _toInt(m['fat']);

    final consumedCalories = totals['calories'] ?? 0;
    final message =
        _caloriesOverMessage(consumed: consumedCalories, goal: goalCalories);
    final overKcal = consumedCalories - goalCalories;

    return RefreshIndicator(
      color: FeedPalette.accent,
      onRefresh: () async {
        await _loadTodayMeals();
        await _loadMonthlySummary(_historyMonth);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  if (_apiErrorMessage != null) ...[
                    _buildApiErrorBanner(_apiErrorMessage!),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _openNutritionChatbot,
                          icon: const Icon(Icons.auto_awesome_rounded),
                          label: const Text('ESCANEAR CON IA'),
                          style: FeedPalette.primaryButtonStyle(
                            radius: 18,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 128),
                        child: OutlinedButton.icon(
                          onPressed: _openHistoryPage,
                          icon: const Icon(Icons.calendar_month_rounded),
                          label: const Text('Historial'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FeedPalette.text,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18)),
                            backgroundColor: FeedPalette.surface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.of(context).padding.bottom +
                  kBottomNavigationBarHeight +
                  2,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  if (message != null && overKcal > 0) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _overBannerColor(overKcal),
                        borderRadius: BorderRadius.circular(16),
                        border:
                            Border.all(color: _overBannerBorderColor(overKcal)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: FeedPalette.accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: FeedPalette.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _buildTotalsCard(
                    totals: totals,
                    goalCalories: goalCalories,
                    goalProtein: goalProtein,
                    goalCarbs: goalCarbs,
                    goalFat: goalFat,
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Comidas de hoy',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() => _userMetrics = null),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Editar plan'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_isLoadingToday)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                            color: FeedPalette.accent),
                      ),
                    )
                  else
                    ..._buildTodaySlots(),
                  _buildDailySuggestions(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openHistoryPage() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: FeedPalette.background,
          appBar: AppBar(
            title: const Text(
              'Historial',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            backgroundColor: FeedPalette.background,
            elevation: 0,
          ),
          body: Container(
            decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
            child: _buildHistoryTab(),
          ),
        ),
      ),
    );
  }

  Widget _buildApiErrorBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: Colors.red.shade400),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: _bootstrap,
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTodaySlots() {
    final mealsBySlot = _groupMealsBySlot(_todayMeals);

    final widgets = <Widget>[];
    for (final slot in _mealSlots) {
      final meal = mealsBySlot[slot];
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: FeedPalette.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        slot,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (meal == null)
                      Text(
                        'Vacío',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (meal == null)
                  Text(
                    'Escanea una imagen con IA y asígnala a este apartado.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                else
                  _buildMealCard(meal, showTime: true),
              ],
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildDailySuggestions() {
    final dayIndex = DateTime.now().weekday % 7;

    final suggestionsList = [
      {
        'Desayuno': 'Avena con manzana y canela',
        'Almuerzo': 'Yogur con nueces',
        'Comida': 'Pollo a la plancha con arroz integral',
        'Merienda': 'Batido de proteínas',
        'Cena': 'Ensalada de atún',
      },
      {
        'Desayuno': 'Tostadas integrales con aguacate',
        'Almuerzo': 'Fruta fresca de temporada',
        'Comida': 'Salmón al horno con verduras',
        'Merienda': 'Un puñado de almendras',
        'Cena': 'Crema de calabacín',
      },
      {
        'Desayuno': 'Huevos revueltos con espinacas',
        'Almuerzo': 'Galletas de avena caseras',
        'Comida': 'Lentejas con verduras',
        'Merienda': 'Queso fresco con miel',
        'Cena': 'Tortilla francesa con pavo',
      },
      {
        'Desayuno': 'Batido verde (espinacas, plátano, manzana)',
        'Almuerzo': 'Un puñado de nueces',
        'Comida': 'Pechuga de pollo con boniato asado',
        'Merienda': 'Yogur griego con chía',
        'Cena': 'Merluza a la plancha con espárragos',
      },
      {
        'Desayuno': 'Porridge de avena con frutos rojos',
        'Almuerzo': 'Pera y un trozo de queso',
        'Comida': 'Pasta integral con tomate casero',
        'Merienda': 'Hummus con zanahoria',
        'Cena': 'Sopa de fideos y ensalada',
      },
      {
        'Desayuno': 'Tortitas de avena y plátano',
        'Almuerzo': 'Manzana con crema de cacahuete',
        'Comida': 'Garbanzos con espinacas',
        'Merienda': 'Kéfir o yogur natural',
        'Cena': 'Pizza de base de coliflor',
      },
      {
        'Desayuno': 'Yogur, granola y kiwi',
        'Almuerzo': 'Mandarinas y almendras',
        'Comida': 'Ternera con ensalada verde',
        'Merienda': 'Batido de frutas',
        'Cena': 'Pescado blanco con patatas',
      },
    ];

    final todaySuggestions = suggestionsList[dayIndex];
    final mealStyles = {
      'Desayuno': {
        'icon': Icons.free_breakfast_rounded,
        'color': const Color(0xFFFF9800),
      },
      'Almuerzo': {
        'icon': Icons.apple_rounded,
        'color': const Color(0xFF4CAF50),
      },
      'Comida': {
        'icon': Icons.restaurant_rounded,
        'color': const Color(0xFF2196F3),
      },
      'Merienda': {
        'icon': Icons.bakery_dining_rounded,
        'color': const Color(0xFF9C27B0),
      },
      'Cena': {
        'icon': Icons.nightlight_round,
        'color': const Color(0xFF3F51B5),
      },
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FeedPalette.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.auto_awesome_rounded,
                  color: FeedPalette.accent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Inspiración del día',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 170,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: todaySuggestions.length,
            itemBuilder: (context, index) {
              final key = todaySuggestions.keys.elementAt(index);
              final value = todaySuggestions[key]!;
              final style = mealStyles[key] as Map<String, dynamic>?;
              final icon = style?['icon'] as IconData? ?? Icons.restaurant;
              final color = style?['color'] as Color? ?? FeedPalette.accent;

              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border:
                      Border.all(color: color.withValues(alpha: 0.1), width: 2),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const Spacer(),
                    Text(
                      key,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FeedPalette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTotalsCard({
    required Map<String, int> totals,
    required int goalCalories,
    required int goalProtein,
    required int goalCarbs,
    required int goalFat,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: FeedPalette.border),
        boxShadow: [
          BoxShadow(
            color: FeedPalette.accent.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Totales de hoy',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          _progressRow(
            label: 'Calorías',
            value: totals['calories'] ?? 0,
            goal: goalCalories,
            color: FeedPalette.accent,
            unit: 'kcal',
          ),
          const SizedBox(height: 10),
          _progressRow(
            label: 'Proteínas',
            value: totals['protein'] ?? 0,
            goal: goalProtein,
            color: Colors.blue,
            unit: 'g',
          ),
          const SizedBox(height: 10),
          _progressRow(
            label: 'Carbohidratos',
            value: totals['carbs'] ?? 0,
            goal: goalCarbs,
            color: Colors.orange,
            unit: 'g',
          ),
          const SizedBox(height: 10),
          _progressRow(
            label: 'Grasas',
            value: totals['fat'] ?? 0,
            goal: goalFat,
            color: Colors.green,
            unit: 'g',
          ),
        ],
      ),
    );
  }

  Widget _progressRow({
    required String label,
    required int value,
    required int goal,
    required Color color,
    required String unit,
  }) {
    final safeGoal = goal <= 0 ? 1 : goal;
    final ratio = (value / safeGoal).clamp(0.0, 1.0);
    final rightText = goal > 0 ? '$value/$goal $unit' : '$value $unit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.text,
                ),
              ),
            ),
            Text(
              rightText,
              style: TextStyle(
                color: FeedPalette.muted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _buildMealCard(Map<String, dynamic> meal, {required bool showTime}) {
    final title = (meal['comida'] ?? 'Comida').toString();
    final calories = _toInt(meal['calorias']);
    final protein = _toInt(meal['proteinas']);
    final carbs = _toInt(meal['carbohidratos']);
    final fat = _toInt(meal['grasas']);

    final createdAt = _toDateTime(meal['createdAt']);
    final timeLabel = createdAt == null
        ? ''
        : DateFormat('HH:mm').format(createdAt.toLocal());

    final rawImage = (meal['image'] ?? '').toString();
    // Images are stored as a relative path like `/uploads/...` and served by the backend.
    final imageUrl = rawImage.isEmpty ? '' : UrlUtils.resolveFullUrl(rawImage);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FeedPalette.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: narrow ? 52 : 64,
                  height: narrow ? 52 : 64,
                  color: FeedPalette.surfaceSoft,
                  child: imageUrl.isEmpty
                      ? Icon(Icons.fastfood_rounded, color: FeedPalette.muted)
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.broken_image,
                            color: FeedPalette.muted,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (narrow) ...[
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: FeedPalette.text,
                        ),
                      ),
                      if (showTime && timeLabel.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            color: FeedPalette.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                color: FeedPalette.text,
                              ),
                            ),
                          ),
                          if (showTime && timeLabel.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                timeLabel,
                                style: TextStyle(
                                  color: FeedPalette.muted,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _chip('Kcal', '$calories', FeedPalette.accent),
                        _chip('P', '${protein}g', Colors.blue),
                        _chip('C', '${carbs}g', Colors.orange),
                        _chip('G', '${fat}g', Colors.green),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, String value, Color color) {
    final text = label.trim().isEmpty ? value : '$label $value';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight + 2,
      ),
      children: [
        _buildHistorySummaryCard(),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: FeedPalette.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  final prev =
                      DateTime(_historyMonth.year, _historyMonth.month - 1, 1);
                  setState(() => _historyMonth = prev);
                  _loadMonthlySummary(prev);
                },
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_historyMonth),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: FeedPalette.text,
                  ),
                ),
              ),
              IconButton(
                onPressed: () {
                  final next =
                      DateTime(_historyMonth.year, _historyMonth.month + 1, 1);
                  setState(() => _historyMonth = next);
                  _loadMonthlySummary(next);
                },
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Toca un día para ver tus comidas.',
          style:
              TextStyle(color: FeedPalette.muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        if (_isLoadingMonth)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: CircularProgressIndicator(color: FeedPalette.accent),
            ),
          )
        else
          _buildCalendarGrid(_historyMonth),
      ],
    );
  }

  Widget _buildHistorySummaryCard() {
    final daysTracked = _monthCaloriesByDate.length;
    final totalKcal = _monthCaloriesByDate.values.fold<int>(0, (a, b) => a + b);
    final avg = daysTracked == 0 ? 0 : (totalKcal / daysTracked).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: FeedPalette.heroDecoration(radius: 22),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(Icons.insights_rounded, color: FeedPalette.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumen del mes',
                  style: TextStyle(
                    color: FeedPalette.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  daysTracked == 0
                      ? 'Aún no hay días registrados.'
                      : '${daysTracked == 1 ? '1 día' : '$daysTracked días'} · media $avg kcal',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: FeedPalette.muted, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: FeedPalette.surfaceSoft.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: FeedPalette.border.withValues(alpha: 0.6)),
            ),
            child: Text(
              avg == 0 ? '—' : '$avg',
              style: TextStyle(
                color: FeedPalette.text,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarGrid(DateTime month) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 380;
        return _buildCalendarGridContent(
          month,
          cellHeight: isCompact ? 40.0 : 46.0,
        );
      },
    );
  }

  Widget _buildCalendarGridContent(
    DateTime month, {
    required double cellHeight,
  }) {
    final firstDay = DateTime(month.year, month.month, 1);
    final firstWeekdayOffset = firstDay.weekday - DateTime.monday; // 0..6
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final cells = <Widget>[];
    for (var i = 0; i < firstWeekdayOffset; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      final kcal = _monthCaloriesByDate[dateKey];
      final hasKcal = kcal != null && kcal > 0;

      cells.add(
        InkWell(
          onTap: () => _openDayDetails(dateKey),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              gradient: hasKcal
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        FeedPalette.accent.withValues(alpha: 0.16),
                        FeedPalette.surface,
                      ],
                    )
                  : null,
              color: hasKcal ? null : FeedPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasKcal
                    ? FeedPalette.accent.withValues(alpha: 0.22)
                    : FeedPalette.border,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$day',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: FeedPalette.text,
                    fontSize: 13,
                    height: 1.1,
                  ),
                ),
                if (hasKcal) ...[
                  const SizedBox(height: 3),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: FeedPalette.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            _WeekdayLabel('L'),
            _WeekdayLabel('M'),
            _WeekdayLabel('X'),
            _WeekdayLabel('J'),
            _WeekdayLabel('V'),
            _WeekdayLabel('S'),
            _WeekdayLabel('D'),
          ],
        ),
        const SizedBox(height: 10),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: cells.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            mainAxisExtent: cellHeight,
          ),
          itemBuilder: (context, index) => cells[index],
        ),
      ],
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  final String text;
  const _WeekdayLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            color: FeedPalette.muted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
