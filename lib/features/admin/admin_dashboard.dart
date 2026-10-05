import 'package:flutter/material.dart';
import 'package:rms/core/constants/admin_catalog_options.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/shared/widgets/common/smart_image.dart';

import 'admin_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final AdminService _adminService = AdminService();
  final TextEditingController _userSearchController = TextEditingController();
  late Future<AdminDashboardData> _dashboardFuture;

  @override
  void initState() {
    super.initState();
    _dashboardFuture = _loadDashboard();
  }

  Future<_AdminSectionLoad<T>> _safeLoadSection<T>(
    String label,
    Future<T> Function() loader,
    T fallback,
  ) async {
    try {
      return _AdminSectionLoad(label: label, value: await loader());
    } catch (error) {
      debugPrint('Admin section "$label" failed: $error');
      return _AdminSectionLoad(
        label: label,
        value: fallback,
        error: error.toString(),
      );
    }
  }

  Map<String, dynamic> _emptyOverview() {
    return const {
      'metrics': <String, dynamic>{},
      'system': <String, dynamic>{},
      'recentAuditLogs': <Map<String, dynamic>>[],
    };
  }

  Future<AdminDashboardData> _loadDashboard() async {
    final results = await Future.wait<_AdminSectionLoad<dynamic>>([
      _safeLoadSection('Resumen', _adminService.getOverview, _emptyOverview()),
      _safeLoadSection(
        'Usuarios',
        _adminService.getUsers,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Reportes',
        _adminService.getReports,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Publicaciones',
        _adminService.getModerationPosts,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Comentarios',
        _adminService.getModerationComments,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Historias',
        _adminService.getModerationStories,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Ejercicios',
        _adminService.getExercises,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Alimentos',
        _adminService.getFoods,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Deportes',
        _adminService.getSports,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Plantillas de entrenamiento',
        _adminService.getWorkoutTemplates,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Plantillas de nutricion',
        _adminService.getNutritionTemplates,
        const <Map<String, dynamic>>[],
      ),
      _safeLoadSection(
        'Logs',
        _adminService.getAuditLogs,
        const <Map<String, dynamic>>[],
      ),
    ]);

    final sectionErrors = <String, String>{};
    for (final result in results) {
      if (result.error != null) {
        sectionErrors[result.label] = result.error!;
      }
    }

    return AdminDashboardData(
      overview: Map<String, dynamic>.from(results[0].value as Map),
      users: List<Map<String, dynamic>>.from(
        results[1].value as List<Map<String, dynamic>>,
      ),
      reports: List<Map<String, dynamic>>.from(
        results[2].value as List<Map<String, dynamic>>,
      ),
      posts: List<Map<String, dynamic>>.from(
        results[3].value as List<Map<String, dynamic>>,
      ),
      comments: List<Map<String, dynamic>>.from(
        results[4].value as List<Map<String, dynamic>>,
      ),
      stories: List<Map<String, dynamic>>.from(
        results[5].value as List<Map<String, dynamic>>,
      ),
      exercises: List<Map<String, dynamic>>.from(
        results[6].value as List<Map<String, dynamic>>,
      ),
      foods: List<Map<String, dynamic>>.from(
        results[7].value as List<Map<String, dynamic>>,
      ),
      sports: List<Map<String, dynamic>>.from(
        results[8].value as List<Map<String, dynamic>>,
      ),
      workoutTemplates: List<Map<String, dynamic>>.from(
        results[9].value as List<Map<String, dynamic>>,
      ),
      nutritionTemplates: List<Map<String, dynamic>>.from(
        results[10].value as List<Map<String, dynamic>>,
      ),
      auditLogs: List<Map<String, dynamic>>.from(
        results[11].value as List<Map<String, dynamic>>,
      ),
      sectionErrors: sectionErrors,
      loadedAt: DateTime.now(),
    );
  }

  Future<void> _refresh() async {
    final nextFuture = _loadDashboard();
    setState(() {
      _dashboardFuture = nextFuture;
    });
    await nextFuture;
  }

  Future<void> _handleAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error'), backgroundColor: Colors.redAccent),
      );
    }
  }

  Future<String?> _showTextPrompt({
    required String title,
    String? initialValue,
    String hint = '',
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: initialValue ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(hintText: hint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: Text('Guardar'),
            ),
          ],
        );
      },
    );

    controller.dispose();
    return result;
  }

  Future<void> _confirmAction({
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      await onConfirm();
    }
  }

  Future<void> _confirmCatalogDelete({
    required String title,
    required String message,
    required Future<void> Function() onConfirm,
  }) async {
    await _confirmAction(
      title: title,
      message: message,
      onConfirm: () => _handleAction(
        onConfirm,
        successMessage: 'Elemento eliminado',
      ),
    );
  }

  List<Map<String, dynamic>> _filterUsers(List<Map<String, dynamic>> users) {
    final query = _userSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return users;

    return users.where((user) {
      final values = [
        user['username'],
        user['email'],
        user['name'],
        user['role'],
      ];
      return values.any(
        (value) =>
            value != null && value.toString().toLowerCase().contains(query),
      );
    }).toList();
  }

  int _metricValue(Map<String, dynamic> metrics, String key) {
    final raw = metrics[key];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Widget _buildHeaderStat({
    required IconData icon,
    required String label,
    required String value,
    required bool lightMode,
  }) {
    final statText = lightMode ? const Color(0xFF2A1A12) : Colors.white;
    final statSub = lightMode
        ? const Color(0xFF5B4437)
        : Colors.white.withValues(alpha: 0.82);
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: lightMode
            ? const Color(0xFFFFFFFF).withValues(alpha: 0.78)
            : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: lightMode
              ? const Color(0xFFF2D7C8)
              : Colors.white.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: statText, size: 18),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: statText,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: statSub,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAdminHero(AdminDashboardData data) {
    final metrics = Map<String, dynamic>.from(
      data.overview['metrics'] as Map? ?? const {},
    );

    final lightMode = !FeedPalette.isDark;
    final titleColor = lightMode ? const Color(0xFF2A1A12) : Colors.white;
    final subtitleColor = lightMode ? const Color(0xFF5B4437) : Colors.white70;
    final iconPanelColor = lightMode
        ? Colors.white.withValues(alpha: 0.85)
        : Colors.white.withValues(alpha: 0.12);
    final gradient = lightMode
        ? const LinearGradient(
            colors: [Color(0xFFFFB286), Color(0xFFFF8B52)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : FeedPalette.heroGradient;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2A3D1E10),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconPanelColor,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.admin_panel_settings_rounded,
                  color: titleColor,
                  size: 26,
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Centro de control',
                      style: TextStyle(
                        color: titleColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Gestiona usuarios, incidencias y catalogos con una vista mas clara.',
                      style: TextStyle(color: subtitleColor, height: 1.35),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildHeaderStat(
                icon: Icons.groups_rounded,
                label: 'Usuarios',
                value: '${data.users.length}',
                lightMode: lightMode,
              ),
              _buildHeaderStat(
                icon: Icons.flag_rounded,
                label: 'Reportes abiertos',
                value: '${_metricValue(metrics, 'openReports')}',
                lightMode: lightMode,
              ),
              _buildHeaderStat(
                icon: Icons.auto_stories_rounded,
                label: 'Historias activas',
                value: '${_metricValue(metrics, 'activeStories')}',
                lightMode: lightMode,
              ),
              _buildHeaderStat(
                icon: Icons.inventory_2_rounded,
                label: 'Catalogos activos',
                value:
                    '${_metricValue(metrics, 'exercises') + _metricValue(metrics, 'foods') + _metricValue(metrics, 'sportCategories')}',
                lightMode: lightMode,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionErrorsBanner(Map<String, String> sectionErrors) {
    if (sectionErrors.isEmpty) {
      return SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FeedPalette.accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FeedPalette.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFB85A21)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Algunas secciones no se pudieron cargar, pero el panel sigue disponible.',
                  style: TextStyle(
                    color: Color(0xFF6B3B16),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ...sectionErrors.entries.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${entry.key}: ${entry.value}',
                style: TextStyle(
                  color: Color(0xFF7A4D2B),
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showExerciseDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(
      text: initial?['name']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: initial?['description']?.toString() ?? '',
    );
    var selectedCategory = AdminCatalogOptions.exerciseCategories.contains(
      initial?['category']?.toString(),
    )
        ? initial!['category'].toString()
        : AdminCatalogOptions.exerciseCategories.first;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null ? 'Nuevo ejercicio' : 'Editar ejercicio',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedCategory),
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Categoria',
                      ),
                      items: AdminCatalogOptions.exerciseCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedCategory = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripcion',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'name': name.text.trim(),
                    'category': selectedCategory,
                    'description': description.text.trim(),
                  }),
                  child: Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    description.dispose();
    return payload;
  }

  Future<Map<String, dynamic>?> _showFoodDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(
      text: initial?['name']?.toString() ?? '',
    );
    final calories = TextEditingController(
      text: initial?['calories']?.toString() ?? '',
    );
    final protein = TextEditingController(
      text: initial?['protein']?.toString() ?? '',
    );
    final carbs = TextEditingController(
      text: initial?['carbs']?.toString() ?? '',
    );
    final fat = TextEditingController(text: initial?['fat']?.toString() ?? '');
    var selectedCategory = AdminCatalogOptions.foodCategories.contains(
      initial?['category']?.toString(),
    )
        ? initial!['category'].toString()
        : AdminCatalogOptions.foodCategories.first;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title:
                  Text(initial == null ? 'Nuevo alimento' : 'Editar alimento'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedCategory),
                      initialValue: selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Catalogo (recetas)',
                      ),
                      items: AdminCatalogOptions.foodCategories
                          .map(
                            (category) => DropdownMenuItem(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedCategory = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: calories,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Calorias'),
                    ),
                    TextField(
                      controller: protein,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Proteina'),
                    ),
                    TextField(
                      controller: carbs,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Carbohidratos'),
                    ),
                    TextField(
                      controller: fat,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Grasas'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'name': name.text.trim(),
                    'category': selectedCategory,
                    'calories': num.tryParse(calories.text.trim()) ?? 0,
                    'protein': num.tryParse(protein.text.trim()) ?? 0,
                    'carbs': num.tryParse(carbs.text.trim()) ?? 0,
                    'fat': num.tryParse(fat.text.trim()) ?? 0,
                  }),
                  child: Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
    return payload;
  }

  Future<Map<String, dynamic>?> _showSportDialog({
    Map<String, dynamic>? initial,
  }) async {
    final name = TextEditingController(
      text: initial?['name']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: initial?['description']?.toString() ?? '',
    );
    bool isActive = initial?['isActive'] != false;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Nueva categoria deportiva'
                    : 'Editar categoria',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                    ),
                    TextField(
                      controller: description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descripcion',
                      ),
                    ),
                    SwitchListTile(
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                      title: Text('Activa'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'name': name.text.trim(),
                    'description': description.text.trim(),
                    'isActive': isActive,
                  }),
                  child: Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    name.dispose();
    description.dispose();
    return payload;
  }

  String _serializeExercises(dynamic value) {
    if (value is List) {
      return value.map((item) {
        final map = Map<String, dynamic>.from(item as Map);
        return [
          map['name'] ?? '',
          map['sets'] ?? '',
          map['reps'] ?? '',
          map['duration'] ?? '',
        ].join('|');
      }).join('\n');
    }

    return '';
  }

  List<Map<String, dynamic>> _parseExercises(String raw) {
    return raw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) {
          final parts = line.split('|');
          return {
            'name': parts.isNotEmpty ? parts[0].trim() : '',
            'sets': parts.length > 1 ? int.tryParse(parts[1].trim()) ?? 1 : 1,
            if (parts.length > 2 && parts[2].trim().isNotEmpty)
              'reps': int.tryParse(parts[2].trim()) ?? 0,
            if (parts.length > 3 && parts[3].trim().isNotEmpty)
              'duration': parts[3].trim(),
          };
        })
        .where((item) => (item['name'] as String).isNotEmpty)
        .toList();
  }

  Future<Map<String, dynamic>?> _showWorkoutTemplateDialog({
    Map<String, dynamic>? initial,
  }) async {
    final title = TextEditingController(
      text: initial?['title']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: initial?['description']?.toString() ?? '',
    );
    final sport = TextEditingController(
      text: initial?['sport']?.toString() ?? '',
    );
    final difficulty = TextEditingController(
      text: initial?['difficulty']?.toString() ?? '',
    );
    final exercises = TextEditingController(
      text: _serializeExercises(initial?['exercisesJson']),
    );
    bool isActive = initial?['isActive'] != false;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Nueva plantilla de entrenamiento'
                    : 'Editar plantilla',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: title,
                        decoration: const InputDecoration(labelText: 'Titulo'),
                      ),
                      TextField(
                        controller: sport,
                        decoration: const InputDecoration(labelText: 'Deporte'),
                      ),
                      TextField(
                        controller: difficulty,
                        decoration: const InputDecoration(
                          labelText: 'Dificultad',
                        ),
                      ),
                      TextField(
                        controller: description,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Descripcion',
                        ),
                      ),
                      TextField(
                        controller: exercises,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Ejercicios',
                          hintText: 'Nombre|sets|reps|duracion, uno por linea',
                        ),
                      ),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (value) =>
                            setDialogState(() => isActive = value),
                        title: Text('Activa'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'title': title.text.trim(),
                    'sport': sport.text.trim(),
                    'difficulty': difficulty.text.trim(),
                    'description': description.text.trim(),
                    'isActive': isActive,
                    'exercises': _parseExercises(exercises.text),
                  }),
                  child: Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    description.dispose();
    sport.dispose();
    difficulty.dispose();
    exercises.dispose();
    return payload;
  }

  Future<Map<String, dynamic>?> _showNutritionTemplateDialog({
    Map<String, dynamic>? initial,
  }) async {
    final title = TextEditingController(
      text: initial?['title']?.toString() ?? '',
    );
    final goal = TextEditingController(
      text: initial?['goal']?.toString() ?? '',
    );
    final calories = TextEditingController(
      text: initial?['calories']?.toString() ?? '',
    );
    final protein = TextEditingController(
      text: initial?['protein']?.toString() ?? '',
    );
    final carbs = TextEditingController(
      text: initial?['carbs']?.toString() ?? '',
    );
    final fat = TextEditingController(text: initial?['fat']?.toString() ?? '');
    final notes = TextEditingController(
      text: initial?['notes']?.toString() ?? '',
    );
    bool isActive = initial?['isActive'] != false;

    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(
                initial == null
                    ? 'Nueva plantilla de nutricion'
                    : 'Editar plantilla',
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: title,
                        decoration: const InputDecoration(labelText: 'Titulo'),
                      ),
                      TextField(
                        controller: goal,
                        decoration: const InputDecoration(
                          labelText: 'Objetivo',
                        ),
                      ),
                      TextField(
                        controller: calories,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Calorias',
                        ),
                      ),
                      TextField(
                        controller: protein,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Proteina',
                        ),
                      ),
                      TextField(
                        controller: carbs,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Carbohidratos',
                        ),
                      ),
                      TextField(
                        controller: fat,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Grasas'),
                      ),
                      TextField(
                        controller: notes,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Notas'),
                      ),
                      SwitchListTile(
                        value: isActive,
                        onChanged: (value) =>
                            setDialogState(() => isActive = value),
                        title: Text('Activa'),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop({
                    'title': title.text.trim(),
                    'goal': goal.text.trim(),
                    'calories': int.tryParse(calories.text.trim()) ?? 0,
                    'protein': int.tryParse(protein.text.trim()) ?? 0,
                    'carbs': int.tryParse(carbs.text.trim()) ?? 0,
                    'fat': int.tryParse(fat.text.trim()) ?? 0,
                    'notes': notes.text.trim(),
                    'isActive': isActive,
                  }),
                  child: Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    title.dispose();
    goal.dispose();
    calories.dispose();
    protein.dispose();
    carbs.dispose();
    fat.dispose();
    notes.dispose();
    return payload;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        toolbarHeight: 84,
        backgroundColor: FeedPalette.background,
        foregroundColor: FeedPalette.text,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Centro de control',
              style: TextStyle(
                color: FeedPalette.text,
                fontWeight: FontWeight.w900,
                fontSize: 26,
                letterSpacing: -0.8,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Moderacion, gestion y seguimiento del sistema.',
              style: TextStyle(
                color: FeedPalette.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Recargar',
            icon: Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<AdminDashboardData>(
        future: _dashboardFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No se pudo cargar el panel admin.\n${snapshot.error ?? ''}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final data = snapshot.data!;
          final isNarrow = MediaQuery.sizeOf(context).width < 420;
          return DefaultTabController(
            length: 6,
            child: NestedScrollView(
              headerSliverBuilder: (context, _) {
                return [
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        _buildAdminHero(data),
                        _buildSectionErrorsBanner(data.sectionErrors),
                      ],
                    ),
                  ),
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickyTabBarDelegate(
                      height: isNarrow ? 64 : 72,
                      child: Container(
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: FeedPalette.surface,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: FeedPalette.border),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x1218120E),
                              blurRadius: 18,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: TabBar(
                          isScrollable: true,
                          dividerColor: Colors.transparent,
                          tabAlignment: TabAlignment.start,
                          indicator: BoxDecoration(
                            color: FeedPalette.accent,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: FeedPalette.accent.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: FeedPalette.muted,
                          labelStyle:
                              const TextStyle(fontWeight: FontWeight.w700),
                          tabs: const [
                            Tab(text: 'Resumen'),
                            Tab(text: 'Usuarios'),
                            Tab(text: 'Reportes'),
                            Tab(text: 'Moderacion'),
                            Tab(text: 'Catalogos'),
                            Tab(text: 'Logs'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ];
              },
              body: ColoredBox(
                color: FeedPalette.background,
                child: TabBarView(
                  children: [
                    _OverviewTab(data: data.overview),
                    _UsersTab(
                      users: _filterUsers(data.users),
                      totalUsersCount: data.users.length,
                      searchController: _userSearchController,
                      onSearchChanged: () => setState(() {}),
                      onRoleChanged: (userId, role) => _handleAction(
                        () => _adminService.updateUserRole(userId, role),
                        successMessage: 'Rol actualizado',
                      ),
                      onStatusChanged: (userId, isActive) => _handleAction(
                        () => _adminService.updateUserStatus(userId, isActive),
                        successMessage:
                            isActive ? 'Usuario activado' : 'Usuario bloqueado',
                      ),
                      onSendReset: (userId) => _handleAction(() async {
                        await _adminService.sendPasswordReset(userId);
                      }, successMessage: 'Correo de recuperacion reenviado'),
                    ),
                    _AdminReportsTab(
                      reports: data.reports,
                      onUpdateStatus: (reportId, status) =>
                          _handleAction(() async {
                        final notes = await _showTextPrompt(
                          title: 'Notas de resolucion',
                          hint: 'Opcional',
                          maxLines: 3,
                        );
                        await _adminService.updateReport(
                          reportId,
                          status: status,
                          resolutionNotes: notes,
                        );
                      }, successMessage: 'Reporte actualizado'),
                    ),
                    _AdminModerationTab(
                      posts: data.posts,
                      comments: data.comments,
                      stories: data.stories,
                      onDeletePost: (postId) => _confirmAction(
                        title: 'Eliminar publicacion',
                        message:
                            'Esta accion eliminara la publicacion y sus interacciones.',
                        onConfirm: () => _handleAction(
                          () => _adminService.deletePost(postId),
                          successMessage: 'Publicacion eliminada',
                        ),
                      ),
                      onDeleteComment: (commentId) => _confirmAction(
                        title: 'Eliminar comentario',
                        message:
                            'El comentario se eliminara de forma permanente.',
                        onConfirm: () => _handleAction(
                          () => _adminService.deleteComment(commentId),
                          successMessage: 'Comentario eliminado',
                        ),
                      ),
                      onArchiveStory: (storyId) => _confirmAction(
                        title: 'Archivar historia',
                        message:
                            'La historia se marcara como archivada por administracion.',
                        onConfirm: () => _handleAction(
                          () => _adminService.archiveStory(storyId),
                          successMessage: 'Historia archivada',
                        ),
                      ),
                    ),
                    _AdminCatalogTab(
                      exercises: data.exercises,
                      foods: data.foods,
                      sports: data.sports,
                      workoutTemplates: data.workoutTemplates,
                      nutritionTemplates: data.nutritionTemplates,
                      onCreateExercise: () async {
                        final payload = await _showExerciseDialog();
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.createExercise(payload),
                          successMessage: 'Ejercicio creado',
                        );
                      },
                      onEditExercise: (item) async {
                        final payload =
                            await _showExerciseDialog(initial: item);
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.updateExercise(
                            item['id'] as int,
                            payload,
                          ),
                          successMessage: 'Ejercicio actualizado',
                        );
                      },
                      onCreateFood: () async {
                        final payload = await _showFoodDialog();
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.createFood(payload),
                          successMessage: 'Alimento creado',
                        );
                      },
                      onEditFood: (item) async {
                        final payload = await _showFoodDialog(initial: item);
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.updateFood(
                            item['id'] as int,
                            payload,
                          ),
                          successMessage: 'Alimento actualizado',
                        );
                      },
                      onCreateSport: () async {
                        final payload = await _showSportDialog();
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.createSport(payload),
                          successMessage: 'Categoria creada',
                        );
                      },
                      onEditSport: (item) async {
                        final payload = await _showSportDialog(initial: item);
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.updateSport(
                            item['id'] as int,
                            payload,
                          ),
                          successMessage: 'Categoria actualizada',
                        );
                      },
                      onCreateWorkoutTemplate: () async {
                        final payload = await _showWorkoutTemplateDialog();
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.createWorkoutTemplate(payload),
                          successMessage: 'Plantilla creada',
                        );
                      },
                      onEditWorkoutTemplate: (item) async {
                        final payload = await _showWorkoutTemplateDialog(
                          initial: item,
                        );
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.updateWorkoutTemplate(
                            item['id'] as int,
                            payload,
                          ),
                          successMessage: 'Plantilla actualizada',
                        );
                      },
                      onCreateNutritionTemplate: () async {
                        final payload = await _showNutritionTemplateDialog();
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.createNutritionTemplate(payload),
                          successMessage: 'Plantilla creada',
                        );
                      },
                      onEditNutritionTemplate: (item) async {
                        final payload = await _showNutritionTemplateDialog(
                          initial: item,
                        );
                        if (payload == null) return;
                        await _handleAction(
                          () => _adminService.updateNutritionTemplate(
                            item['id'] as int,
                            payload,
                          ),
                          successMessage: 'Plantilla actualizada',
                        );
                      },
                      onDeleteExercise: (item) => _confirmCatalogDelete(
                        title: 'Eliminar ejercicio',
                        message:
                            'Se eliminara "${_safeText(item['name'])}" del catalogo.',
                        onConfirm: () =>
                            _adminService.deleteExercise(item['id'] as int),
                      ),
                      onDeleteFood: (item) => _confirmCatalogDelete(
                        title: 'Eliminar alimento',
                        message:
                            'Se eliminara "${_safeText(item['name'])}" del catalogo.',
                        onConfirm: () =>
                            _adminService.deleteFood(item['id'] as int),
                      ),
                      onDeleteSport: (item) => _confirmCatalogDelete(
                        title: 'Eliminar categoria',
                        message:
                            'Se eliminara "${_safeText(item['name'])}" del catalogo.',
                        onConfirm: () =>
                            _adminService.deleteSport(item['id'] as int),
                      ),
                      onDeleteWorkoutTemplate: (item) => _confirmCatalogDelete(
                        title: 'Eliminar plantilla',
                        message:
                            'Se eliminara "${_safeText(item['title'])}" del catalogo.',
                        onConfirm: () => _adminService.deleteWorkoutTemplate(
                          item['id'] as int,
                        ),
                      ),
                      onDeleteNutritionTemplate: (item) =>
                          _confirmCatalogDelete(
                        title: 'Eliminar plantilla',
                        message:
                            'Se eliminara "${_safeText(item['title'])}" del catalogo.',
                        onConfirm: () => _adminService.deleteNutritionTemplate(
                          item['id'] as int,
                        ),
                      ),
                    ),
                    _AdminAuditLogsTab(
                      logs: data.auditLogs,
                      loadedAt: data.loadedAt,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    super.dispose();
  }
}

class _StickyTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  _StickyTabBarDelegate({required this.child, required this.height});

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: FeedPalette.background,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyTabBarDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> data;

  const _OverviewTab({required this.data});

  @override
  Widget build(BuildContext context) {
    final metrics = Map<String, dynamic>.from(
      data['metrics'] as Map? ?? const {},
    );
    final system = Map<String, dynamic>.from(
      data['system'] as Map? ?? const {},
    );
    final orderedKeys = [
      'users',
      'blockedUsers',
      'posts',
      'comments',
      'activeStories',
      'reports',
      'openReports',
      'exercises',
      'foods',
      'sportCategories',
      'workoutTemplates',
      'nutritionTemplates',
      'passwordResetsLast24h',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const _AdminSectionTitle(
          title: 'Resumen general',
          subtitle:
              'Indicadores clave del sistema y estado rapido de la configuracion.',
        ),
        SizedBox(height: 14),
        if (metrics.isEmpty)
          const _AdminEmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No hay metricas disponibles',
            subtitle: 'Recarga el panel para volver a intentarlo.',
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: orderedKeys
                .where(metrics.containsKey)
                .map(
                  (key) => SizedBox(
                    width: 172,
                    child: _AdminGlassCard(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: FeedPalette.surfaceSoft,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              _metricIcon(key),
                              color: FeedPalette.accent,
                            ),
                          ),
                          SizedBox(height: 14),
                          Text(
                            '${_safeInt(metrics[key])}',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: FeedPalette.text,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            _metricLabel(key),
                            style: TextStyle(
                              color: FeedPalette.muted,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        SizedBox(height: 18),
        _AdminGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _AdminSectionTitle(
                title: 'Estado del sistema',
                subtitle:
                    'Comprobaciones importantes para recovery, entorno y operativa diaria.',
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _AdminInfoPill(
                    label: 'SMTP',
                    value: system['smtpReady'] == true ? 'Listo' : 'Pendiente',
                  ),
                  _AdminInfoPill(
                    label: 'Entorno',
                    value: _safeText(system['nodeEnv']),
                  ),
                  _AdminInfoPill(
                    label: 'Recovery URL',
                    value: _safeText(system['passwordResetUrl']),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UsersTab extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final int totalUsersCount;
  final TextEditingController searchController;
  final VoidCallback onSearchChanged;
  final Future<void> Function(int userId, String role) onRoleChanged;
  final Future<void> Function(int userId, bool isActive) onStatusChanged;
  final Future<void> Function(int userId) onSendReset;

  const _UsersTab({
    required this.users,
    required this.totalUsersCount,
    required this.searchController,
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onStatusChanged,
    required this.onSendReset,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _AdminSectionTitle(
          title: 'Usuarios de la app',
          subtitle:
              'Mostrando ${users.length} resultado(s) de $totalUsersCount usuario(s) cargado(s).',
        ),
        SizedBox(height: 14),
        _AdminGlassCard(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: searchController,
            onChanged: (_) => onSearchChanged(),
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Buscar por email, usuario, nombre o rol',
              suffixIcon: searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        searchController.clear();
                        onSearchChanged();
                      },
                      icon: Icon(Icons.close_rounded),
                    ),
              filled: true,
              fillColor: FeedPalette.inputFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: BorderSide(color: FeedPalette.border),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            ),
          ),
        ),
        SizedBox(height: 16),
        if (users.isEmpty)
          const _AdminEmptyState(
            icon: Icons.person_search_rounded,
            title: 'No hay usuarios para mostrar',
            subtitle: 'Prueba con otro termino de busqueda o recarga el panel.',
          )
        else
          ...users.map((user) {
            final username = _safeText(user['username'], fallback: 'usuario');
            final email = _safeText(user['email']);
            final name = _safeText(user['name']);
            final sport = _safeText(user['sport']);
            final role = _safeText(user['role'], fallback: 'user');
            final isActive = user['isActive'] == true;
            final imagePath = user['imagePath']?.toString();

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AdminGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: FeedPalette.surfaceSoft,
                          child: ClipOval(
                            child: SmartImage(
                              imageUrl: imagePath ?? '',
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorWidget: Center(
                                child: Text(
                                  _initialsFromText(username),
                                  style: TextStyle(
                                    color: FeedPalette.accent,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: FeedPalette.text,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                email,
                                style: TextStyle(color: FeedPalette.muted),
                              ),
                              SizedBox(height: 4),
                              Text(
                                name == '-' ? 'Nombre sin completar' : name,
                                style: TextStyle(color: FeedPalette.muted),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _AdminBadge(
                              label: _roleLabel(role),
                              backgroundColor: _roleColor(role),
                            ),
                            SizedBox(height: 8),
                            _AdminBadge(
                              label: isActive ? 'Activo' : 'Bloqueado',
                              backgroundColor: isActive
                                  ? const Color(0xFFE4F5EA)
                                  : const Color(0xFFFFE3E1),
                              foregroundColor: isActive
                                  ? const Color(0xFF1F7A43)
                                  : const Color(0xFFB33B30),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AdminInfoPill(label: 'Deporte', value: sport),
                        _AdminInfoPill(
                          label: 'Posts',
                          value: '${_safeInt(user['postsCount'])}',
                        ),
                        _AdminInfoPill(
                          label: 'Seguidores',
                          value: '${_safeInt(user['followersCount'])}',
                        ),
                        _AdminInfoPill(
                          label: 'Reportes creados',
                          value: '${_safeInt(user['reportsCreatedCount'])}',
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final fullWidth = constraints.maxWidth;
                        final isWide = fullWidth >= 560;
                        final controlWidth =
                            isWide ? (fullWidth - 12) / 2 : fullWidth;

                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: controlWidth,
                              child: DropdownButtonFormField<String>(
                                initialValue: role,
                                decoration: InputDecoration(
                                  labelText: 'Rol',
                                  filled: true,
                                  fillColor: FeedPalette.inputFill,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: FeedPalette.border,
                                    ),
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'user',
                                    child: Text('Usuario'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'moderator',
                                    child: Text('Moderador'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin',
                                    child: Text('Admin'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    onRoleChanged(_safeInt(user['id']), value);
                                  }
                                },
                              ),
                            ),
                            SizedBox(
                              width: controlWidth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: FeedPalette.inputFill,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: FeedPalette.border),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Estado de la cuenta',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: FeedPalette.text,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      isActive ? 'Activo' : 'Bloqueado',
                                      style: TextStyle(
                                        color: isActive
                                            ? const Color(0xFF1F7A43)
                                            : const Color(0xFFB33B30),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Switch(
                                      value: isActive,
                                      onChanged: (value) => onStatusChanged(
                                        _safeInt(user['id']),
                                        value,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: () => onSendReset(_safeInt(user['id'])),
                        icon: Icon(Icons.mark_email_read_outlined),
                        label: Text('Reenviar recovery'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ignore: unused_element
class _ReportsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final Future<void> Function(int reportId, String status) onUpdateStatus;

  const _ReportsTab({required this.reports, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: reports
          .map(
            (report) => Card(
              child: ListTile(
                title: Text(
                  'Reporte #${report['id']} · ${report['type'] ?? 'sin tipo'}',
                ),
                subtitle: Text(
                  'Reporter: ${report['reporterUsername'] ?? '-'}\n'
                  'Estado: ${report['status'] ?? 'open'}\n'
                  'Objetivo: ${report['targetLabel'] ?? '-'}\n'
                  'Motivo: ${report['reason'] ?? '-'}',
                ),
                trailing: Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () =>
                          onUpdateStatus(report['id'] as int, 'in_review'),
                      child: Text('En revision'),
                    ),
                    TextButton(
                      onPressed: () =>
                          onUpdateStatus(report['id'] as int, 'resolved'),
                      child: Text('Resolver'),
                    ),
                    TextButton(
                      onPressed: () =>
                          onUpdateStatus(report['id'] as int, 'dismissed'),
                      child: Text('Descartar'),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

// ignore: unused_element
class _ModerationTab extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> stories;
  final Future<void> Function(int postId) onDeletePost;
  final Future<void> Function(int commentId) onDeleteComment;
  final Future<void> Function(int storyId) onArchiveStory;

  const _ModerationTab({
    required this.posts,
    required this.comments,
    required this.stories,
    required this.onDeletePost,
    required this.onDeleteComment,
    required this.onArchiveStory,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ModerationSection(
          title: 'Publicaciones',
          children: posts
              .map(
                (post) => ListTile(
                  title: Text(post['authorUsername']?.toString() ?? 'post'),
                  subtitle: Text(
                    '${post['content'] ?? ''}\nReportes: ${post['reportsCount'] ?? 0}',
                  ),
                  trailing: IconButton(
                    onPressed: () => onDeletePost(post['id'] as int),
                    icon: Icon(Icons.delete_outline),
                  ),
                ),
              )
              .toList(),
        ),
        _ModerationSection(
          title: 'Comentarios',
          children: comments
              .map(
                (comment) => ListTile(
                  title: Text(
                    comment['authorUsername']?.toString() ?? 'comentario',
                  ),
                  subtitle: Text(
                    '${comment['content'] ?? ''}\nReportes: ${comment['reportsCount'] ?? 0}',
                  ),
                  trailing: IconButton(
                    onPressed: () => onDeleteComment(comment['id'] as int),
                    icon: Icon(Icons.delete_outline),
                  ),
                ),
              )
              .toList(),
        ),
        _ModerationSection(
          title: 'Historias',
          children: stories
              .map(
                (story) => ListTile(
                  title: Text(story['username']?.toString() ?? 'story'),
                  subtitle: Text(
                    'Estado: ${story['deletedAt'] == null ? 'Activa' : 'Archivada'}\n'
                    '${story['imagePath'] ?? ''}',
                  ),
                  trailing: IconButton(
                    onPressed: () => onArchiveStory(story['id'] as int),
                    icon: Icon(Icons.archive_outlined),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _CatalogTab extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> foods;
  final List<Map<String, dynamic>> sports;
  final List<Map<String, dynamic>> workoutTemplates;
  final List<Map<String, dynamic>> nutritionTemplates;
  final Future<void> Function() onCreateExercise;
  final Future<void> Function(Map<String, dynamic> item) onEditExercise;
  final Future<void> Function() onCreateFood;
  final Future<void> Function(Map<String, dynamic> item) onEditFood;
  final Future<void> Function() onCreateSport;
  final Future<void> Function(Map<String, dynamic> item) onEditSport;
  final Future<void> Function() onCreateWorkoutTemplate;
  final Future<void> Function(Map<String, dynamic> item) onEditWorkoutTemplate;
  final Future<void> Function() onCreateNutritionTemplate;
  final Future<void> Function(Map<String, dynamic> item)
      onEditNutritionTemplate;

  const _CatalogTab({
    required this.exercises,
    required this.foods,
    required this.sports,
    required this.workoutTemplates,
    required this.nutritionTemplates,
    required this.onCreateExercise,
    required this.onEditExercise,
    required this.onCreateFood,
    required this.onEditFood,
    required this.onCreateSport,
    required this.onEditSport,
    required this.onCreateWorkoutTemplate,
    required this.onEditWorkoutTemplate,
    required this.onCreateNutritionTemplate,
    required this.onEditNutritionTemplate,
  });

  Widget _buildSection({
    required String title,
    required VoidCallback onCreate,
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: Icon(Icons.add),
                  label: Text('Crear'),
                ),
              ],
            ),
            SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildSection(
          title: 'Ejercicios',
          onCreate: () => onCreateExercise(),
          children: exercises
              .map(
                (item) => ListTile(
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text(item['category']?.toString() ?? '-'),
                  trailing: IconButton(
                    onPressed: () => onEditExercise(item),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Alimentos',
          onCreate: () => onCreateFood(),
          children: foods
              .map(
                (item) => ListTile(
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text(
                    'Kcal ${item['calories'] ?? 0} · P ${item['protein'] ?? 0} · C ${item['carbs'] ?? 0} · G ${item['fat'] ?? 0}',
                  ),
                  trailing: IconButton(
                    onPressed: () => onEditFood(item),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Categorias deportivas',
          onCreate: () => onCreateSport(),
          children: sports
              .map(
                (item) => ListTile(
                  title: Text(item['name']?.toString() ?? ''),
                  subtitle: Text(item['description']?.toString() ?? '-'),
                  trailing: IconButton(
                    onPressed: () => onEditSport(item),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Plantillas de entrenamiento',
          onCreate: () => onCreateWorkoutTemplate(),
          children: workoutTemplates
              .map(
                (item) => ListTile(
                  title: Text(item['title']?.toString() ?? ''),
                  subtitle: Text(
                    '${item['sport'] ?? '-'} · ${item['difficulty'] ?? '-'}',
                  ),
                  trailing: IconButton(
                    onPressed: () => onEditWorkoutTemplate(item),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Plantillas de nutricion',
          onCreate: () => onCreateNutritionTemplate(),
          children: nutritionTemplates
              .map(
                (item) => ListTile(
                  title: Text(item['title']?.toString() ?? ''),
                  subtitle: Text(
                    '${item['goal'] ?? '-'} · ${item['calories'] ?? 0} kcal',
                  ),
                  trailing: IconButton(
                    onPressed: () => onEditNutritionTemplate(item),
                    icon: Icon(Icons.edit_outlined),
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _AuditLogsTab extends StatelessWidget {
  final List<Map<String, dynamic>> logs;

  const _AuditLogsTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: logs
          .map(
            (log) => Card(
              child: ListTile(
                title: Text(log['action']?.toString() ?? 'accion'),
                subtitle: Text(
                  'Admin: ${log['adminUsername'] ?? '-'}\n'
                  'Tipo: ${log['targetType'] ?? '-'} · Target: ${log['targetId'] ?? '-'}\n'
                  'Fecha: ${log['createdAt'] ?? '-'}',
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ModerationSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _ModerationSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AdminReportsTab extends StatelessWidget {
  final List<Map<String, dynamic>> reports;
  final Future<void> Function(int reportId, String status) onUpdateStatus;

  const _AdminReportsTab({required this.reports, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _AdminSectionTitle(
          title: 'Reportes y revisiones',
          subtitle: '${reports.length} reporte(s) disponibles para revisar.',
        ),
        SizedBox(height: 14),
        if (reports.isEmpty)
          const _AdminEmptyState(
            icon: Icons.flag_outlined,
            title: 'No hay reportes pendientes',
            subtitle: 'Cuando aparezcan incidencias las veras aqui.',
          )
        else
          ...reports.map((report) {
            final reportId = _safeInt(report['id']);
            final status = _safeText(report['status'], fallback: 'open');

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _AdminGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Reporte #$reportId',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1512),
                            ),
                          ),
                        ),
                        _AdminBadge(
                          label: _reportStatusLabel(status),
                          backgroundColor: _reportStatusColor(status),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tipo: ${_safeText(report['type'])}',
                      style: TextStyle(
                        color: Color(0xFF6E655E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AdminInfoPill(
                          label: 'Reporter',
                          value: _safeText(report['reporterUsername']),
                        ),
                        _AdminInfoPill(
                          label: 'Objetivo',
                          value: _safeText(report['targetLabel']),
                        ),
                        _AdminInfoPill(
                          label: 'Fecha',
                          value: _formatAdminDateTime(report['createdAt']),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Text(
                      _safeText(report['reason']),
                      style: TextStyle(color: Color(0xFF3F3833), height: 1.45),
                    ),
                    SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              onUpdateStatus(reportId, 'in_review'),
                          child: Text('En revision'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => onUpdateStatus(reportId, 'resolved'),
                          child: Text('Resolver'),
                        ),
                        TextButton(
                          onPressed: () =>
                              onUpdateStatus(reportId, 'dismissed'),
                          child: Text('Descartar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _AdminModerationTab extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> comments;
  final List<Map<String, dynamic>> stories;
  final Future<void> Function(int postId) onDeletePost;
  final Future<void> Function(int commentId) onDeleteComment;
  final Future<void> Function(int storyId) onArchiveStory;

  const _AdminModerationTab({
    required this.posts,
    required this.comments,
    required this.stories,
    required this.onDeletePost,
    required this.onDeleteComment,
    required this.onArchiveStory,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const _AdminSectionTitle(
          title: 'Moderacion de contenido',
          subtitle:
              'Accesos rapidos para limpiar contenido conflictivo y mantener el feed sano.',
        ),
        SizedBox(height: 14),
        _AdminModerationBlock(
          title: 'Publicaciones',
          icon: Icons.photo_library_outlined,
          emptyDescription: 'No hay publicaciones para moderar.',
          children: posts
              .map(
                (post) => _AdminActionRow(
                  title: _safeText(post['authorUsername'], fallback: 'post'),
                  subtitle:
                      '${_truncateText(_safeText(post['content']), 140)}\nLikes: ${_safeInt(post['likesCount'])} · Comentarios: ${_safeInt(post['commentsCount'])} · Reportes: ${_safeInt(post['reportsCount'])}',
                  icon: Icons.article_outlined,
                  actionIcon: Icons.delete_outline_rounded,
                  actionColor: const Color(0xFFBF3B30),
                  onPressed: () => onDeletePost(_safeInt(post['id'])),
                ),
              )
              .toList(),
        ),
        _AdminModerationBlock(
          title: 'Comentarios',
          icon: Icons.mode_comment_outlined,
          emptyDescription: 'No hay comentarios para moderar.',
          children: comments
              .map(
                (comment) => _AdminActionRow(
                  title: _safeText(
                    comment['authorUsername'],
                    fallback: 'comentario',
                  ),
                  subtitle:
                      '${_truncateText(_safeText(comment['content']), 120)}\nReportes: ${_safeInt(comment['reportsCount'])} · Me gusta: ${_safeInt(comment['likesCount'])}',
                  icon: Icons.chat_bubble_outline_rounded,
                  actionIcon: Icons.delete_outline_rounded,
                  actionColor: const Color(0xFFBF3B30),
                  onPressed: () => onDeleteComment(_safeInt(comment['id'])),
                ),
              )
              .toList(),
        ),
        _AdminModerationBlock(
          title: 'Historias',
          icon: Icons.auto_stories_outlined,
          emptyDescription: 'No hay historias para moderar.',
          children: stories
              .map(
                (story) => _AdminActionRow(
                  title: _safeText(story['username'], fallback: 'story'),
                  subtitle:
                      'Estado: ${story['deletedAt'] == null ? 'Activa' : 'Archivada'}\n${_safeText(story['imagePath'])}',
                  icon: Icons.auto_stories_outlined,
                  actionIcon: Icons.archive_outlined,
                  actionColor: const Color(0xFF6B4C32),
                  onPressed: () => onArchiveStory(_safeInt(story['id'])),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _AdminCatalogTab extends StatelessWidget {
  final List<Map<String, dynamic>> exercises;
  final List<Map<String, dynamic>> foods;
  final List<Map<String, dynamic>> sports;
  final List<Map<String, dynamic>> workoutTemplates;
  final List<Map<String, dynamic>> nutritionTemplates;
  final Future<void> Function() onCreateExercise;
  final Future<void> Function(Map<String, dynamic> item) onEditExercise;
  final Future<void> Function(Map<String, dynamic> item) onDeleteExercise;
  final Future<void> Function() onCreateFood;
  final Future<void> Function(Map<String, dynamic> item) onEditFood;
  final Future<void> Function(Map<String, dynamic> item) onDeleteFood;
  final Future<void> Function() onCreateSport;
  final Future<void> Function(Map<String, dynamic> item) onEditSport;
  final Future<void> Function(Map<String, dynamic> item) onDeleteSport;
  final Future<void> Function() onCreateWorkoutTemplate;
  final Future<void> Function(Map<String, dynamic> item) onEditWorkoutTemplate;
  final Future<void> Function(Map<String, dynamic> item)
      onDeleteWorkoutTemplate;
  final Future<void> Function() onCreateNutritionTemplate;
  final Future<void> Function(Map<String, dynamic> item)
      onEditNutritionTemplate;
  final Future<void> Function(Map<String, dynamic> item)
      onDeleteNutritionTemplate;

  const _AdminCatalogTab({
    required this.exercises,
    required this.foods,
    required this.sports,
    required this.workoutTemplates,
    required this.nutritionTemplates,
    required this.onCreateExercise,
    required this.onEditExercise,
    required this.onDeleteExercise,
    required this.onCreateFood,
    required this.onEditFood,
    required this.onDeleteFood,
    required this.onCreateSport,
    required this.onEditSport,
    required this.onDeleteSport,
    required this.onCreateWorkoutTemplate,
    required this.onEditWorkoutTemplate,
    required this.onDeleteWorkoutTemplate,
    required this.onCreateNutritionTemplate,
    required this.onEditNutritionTemplate,
    required this.onDeleteNutritionTemplate,
  });

  Widget _buildSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onCreate,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _AdminGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: FeedPalette.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: FeedPalette.accent),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FeedPalette.text,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(color: FeedPalette.muted),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: Icon(Icons.add),
                  label: Text('Crear'),
                ),
              ],
            ),
            SizedBox(height: 14),
            if (children.isEmpty)
              const _AdminEmptyState(
                icon: Icons.inventory_2_outlined,
                title: 'Sin elementos',
                subtitle: 'Crea el primer elemento desde este bloque.',
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        const _AdminSectionTitle(
          title: 'Catalogos y plantillas',
          subtitle:
              'Ejercicios y alimentos aparecen en Entrenamiento y Recetas. Las plantillas son rutinas/objetivos sugeridos para futuras guias rapidas.',
        ),
        SizedBox(height: 10),
        _AdminGlassCard(
          padding: const EdgeInsets.all(14),
          child: Text(
            'Plantillas de entrenamiento: rutinas tipo WOD o fuerza para la seccion Entrenamiento. '
            'Plantillas de nutricion: objetivos caloricos (volumen/definicion) para Nutricion.',
            style:
                TextStyle(color: FeedPalette.muted, height: 1.4, fontSize: 13),
          ),
        ),
        SizedBox(height: 14),
        _buildSection(
          title: 'Ejercicios',
          subtitle: '${exercises.length} ejercicio(s)',
          icon: Icons.fitness_center_rounded,
          onCreate: () => onCreateExercise(),
          children: exercises
              .map(
                (item) => _AdminActionRow(
                  title: _safeText(item['name']),
                  subtitle:
                      _safeText(item['category'], fallback: 'Sin categoria'),
                  icon: Icons.sports_gymnastics_rounded,
                  onEdit: () => onEditExercise(item),
                  onDelete: () => onDeleteExercise(item),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Alimentos',
          subtitle: '${foods.length} alimento(s)',
          icon: Icons.restaurant_menu_rounded,
          onCreate: () => onCreateFood(),
          children: foods
              .map(
                (item) => _AdminActionRow(
                  title: _safeText(item['name']),
                  subtitle:
                      '${_safeText(item['category'], fallback: 'Mantenimiento')} · Kcal ${_safeInt(item['calories'])} · P ${_safeInt(item['protein'])}',
                  icon: Icons.local_dining_outlined,
                  onEdit: () => onEditFood(item),
                  onDelete: () => onDeleteFood(item),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Categorias deportivas',
          subtitle: '${sports.length} categoria(s)',
          icon: Icons.category_outlined,
          onCreate: () => onCreateSport(),
          children: sports
              .map(
                (item) => _AdminActionRow(
                  title: _safeText(item['name']),
                  subtitle: _safeText(item['description'],
                      fallback: 'Categoria deportiva'),
                  icon: Icons.sell_outlined,
                  onEdit: () => onEditSport(item),
                  onDelete: () => onDeleteSport(item),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Plantillas de entrenamiento',
          subtitle: '${workoutTemplates.length} plantilla(s)',
          icon: Icons.view_timeline_outlined,
          onCreate: () => onCreateWorkoutTemplate(),
          children: workoutTemplates
              .map(
                (item) => _AdminActionRow(
                  title: _safeText(item['title']),
                  subtitle:
                      '${_safeText(item['sport'], fallback: 'General')} · ${_safeText(item['difficulty'], fallback: 'Media')}',
                  icon: Icons.playlist_add_check_circle_outlined,
                  onEdit: () => onEditWorkoutTemplate(item),
                  onDelete: () => onDeleteWorkoutTemplate(item),
                ),
              )
              .toList(),
        ),
        _buildSection(
          title: 'Plantillas de nutricion',
          subtitle: '${nutritionTemplates.length} plantilla(s)',
          icon: Icons.monitor_heart_outlined,
          onCreate: () => onCreateNutritionTemplate(),
          children: nutritionTemplates
              .map(
                (item) => _AdminActionRow(
                  title: _safeText(item['title']),
                  subtitle:
                      '${_safeText(item['goal'], fallback: 'Sin objetivo')} · ${_safeInt(item['calories'])} kcal',
                  icon: Icons.menu_book_outlined,
                  onEdit: () => onEditNutritionTemplate(item),
                  onDelete: () => onDeleteNutritionTemplate(item),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _AdminAuditLogsTab extends StatelessWidget {
  final List<Map<String, dynamic>> logs;
  final DateTime loadedAt;

  const _AdminAuditLogsTab({required this.logs, required this.loadedAt});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _AdminSectionTitle(
          title: 'Logs de auditoria',
          subtitle:
              'Ultima carga del panel: ${_formatAdminDateTime(loadedAt.toIso8601String())}',
        ),
        SizedBox(height: 14),
        if (logs.isEmpty)
          const _AdminEmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Sin actividad registrada',
            subtitle: 'Las acciones administrativas apareceran aqui.',
          )
        else
          ...logs.map(
            (log) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AdminGlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _safeText(log['action'], fallback: 'accion'),
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1A1512),
                            ),
                          ),
                        ),
                        _AdminBadge(
                          label: _safeText(log['targetType']),
                          backgroundColor: const Color(0xFFF4ECE4),
                          foregroundColor: const Color(0xFF7E5232),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _AdminInfoPill(
                          label: 'Admin',
                          value: _safeText(log['adminUsername']),
                        ),
                        _AdminInfoPill(
                          label: 'Target',
                          value: _safeText(log['targetId']),
                        ),
                        _AdminInfoPill(
                          label: 'Fecha',
                          value: _formatAdminDateTime(log['createdAt']),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AdminModerationBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final String emptyDescription;
  final List<Widget> children;

  const _AdminModerationBlock({
    required this.title,
    required this.icon,
    required this.emptyDescription,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _AdminGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: FeedPalette.surfaceSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: FeedPalette.accent),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: FeedPalette.text,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 14),
            if (children.isEmpty)
              _AdminEmptyState(
                icon: icon,
                title: 'Nada que revisar',
                subtitle: emptyDescription,
              )
            else
              ...children,
          ],
        ),
      ),
    );
  }
}

class _AdminSectionLoad<T> {
  final String label;
  final T value;
  final String? error;

  const _AdminSectionLoad({
    required this.label,
    required this.value,
    this.error,
  });
}

class _AdminSectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _AdminSectionTitle({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: FeedPalette.text,
                ),
              ),
              SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: FeedPalette.muted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdminGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _AdminGlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: FeedPalette.border),
        boxShadow: [
          BoxShadow(
            color: FeedPalette.text.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _AdminBadge({
    required this.label,
    required this.backgroundColor,
    this.foregroundColor = const Color(0xFF5B3B24),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foregroundColor,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _AdminInfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _AdminInfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FeedPalette.border),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style.copyWith(height: 1.3),
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                color: FeedPalette.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(
              text: value,
              style: TextStyle(
                color: FeedPalette.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _AdminEmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return _AdminGlassCard(
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: FeedPalette.surfaceSoft,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: FeedPalette.accent, size: 28),
          ),
          SizedBox(height: 14),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: FeedPalette.text,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: FeedPalette.muted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _AdminActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData actionIcon;
  final Color actionColor;
  final VoidCallback? onPressed;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _AdminActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionIcon = Icons.edit_outlined,
    this.onPressed,
    this.onEdit,
    this.onDelete,
    this.actionColor = const Color(0xFF6A4A30),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: FeedPalette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: FeedPalette.accent),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: FeedPalette.text,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: FeedPalette.muted, height: 1.4),
                ),
              ],
            ),
          ),
          if (onEdit != null)
            IconButton(
              onPressed: onEdit,
              tooltip: 'Editar',
              icon: Icon(Icons.edit_outlined, color: FeedPalette.accent),
            ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              tooltip: 'Eliminar',
              icon: const Icon(Icons.delete_outline, color: Color(0xFFBF3B30)),
            ),
          if (onPressed != null && onEdit == null && onDelete == null)
            IconButton(
              onPressed: onPressed,
              icon: Icon(actionIcon, color: actionColor),
            ),
        ],
      ),
    );
  }
}

String _metricLabel(String key) {
  switch (key) {
    case 'users':
      return 'Usuarios';
    case 'blockedUsers':
      return 'Bloqueados';
    case 'posts':
      return 'Posts';
    case 'comments':
      return 'Comentarios';
    case 'activeStories':
      return 'Historias activas';
    case 'reports':
      return 'Reportes';
    case 'openReports':
      return 'Reportes abiertos';
    case 'exercises':
      return 'Ejercicios';
    case 'foods':
      return 'Alimentos';
    case 'sportCategories':
      return 'Categorias';
    case 'workoutTemplates':
      return 'Plantillas de entreno';
    case 'nutritionTemplates':
      return 'Plantillas de nutricion';
    case 'passwordResetsLast24h':
      return 'Recovery 24h';
    default:
      return key;
  }
}

IconData _metricIcon(String key) {
  switch (key) {
    case 'users':
      return Icons.groups_rounded;
    case 'blockedUsers':
      return Icons.block_rounded;
    case 'posts':
      return Icons.grid_view_rounded;
    case 'comments':
      return Icons.chat_bubble_rounded;
    case 'activeStories':
      return Icons.auto_stories_rounded;
    case 'reports':
      return Icons.flag_rounded;
    case 'openReports':
      return Icons.priority_high_rounded;
    case 'exercises':
      return Icons.fitness_center_rounded;
    case 'foods':
      return Icons.restaurant_rounded;
    case 'sportCategories':
      return Icons.category_rounded;
    case 'workoutTemplates':
      return Icons.view_list_rounded;
    case 'nutritionTemplates':
      return Icons.monitor_heart_rounded;
    case 'passwordResetsLast24h':
      return Icons.password_rounded;
    default:
      return Icons.insights_rounded;
  }
}

String _roleLabel(String role) {
  switch (role) {
    case 'admin':
      return 'Admin';
    case 'moderator':
      return 'Moderador';
    default:
      return 'Usuario';
  }
}

Color _roleColor(String role) {
  switch (role) {
    case 'admin':
      return const Color(0xFFFBE1D2);
    case 'moderator':
      return const Color(0xFFE3ECFF);
    default:
      return const Color(0xFFF0ECE8);
  }
}

Color _reportStatusColor(String status) {
  switch (status) {
    case 'resolved':
      return const Color(0xFFE4F5EA);
    case 'dismissed':
      return const Color(0xFFF0ECE8);
    case 'in_review':
      return const Color(0xFFFFF0D7);
    default:
      return const Color(0xFFFFE3E1);
  }
}

String _reportStatusLabel(String status) {
  switch (status) {
    case 'resolved':
      return 'Resuelto';
    case 'dismissed':
      return 'Descartado';
    case 'in_review':
      return 'En revision';
    default:
      return 'Abierto';
  }
}

String _safeText(dynamic value, {String fallback = '-'}) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') {
    return fallback;
  }

  return text;
}

int _safeInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _truncateText(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength).trim()}...';
}

String _formatAdminDateTime(dynamic value) {
  final raw = value?.toString();
  if (raw == null || raw.isEmpty) {
    return '-';
  }

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }

  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _initialsFromText(String text) {
  final parts = text
      .split(RegExp(r'\s+|_|-'))
      .where((part) => part.trim().isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }

  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }

  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
