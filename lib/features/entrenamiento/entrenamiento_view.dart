import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/constants/api_constants.dart';
import 'training_service.dart';
import 'workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../social/social_state.dart';
import '../social/duel_service.dart';
import '../auth/auth_service.dart';
import 'ai/squat_counter_view.dart';
import 'package:rms/core/constants/admin_catalog_options.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'package:rms/shared/widgets/common/horizontal_tab_swipe_listener.dart';

class EntrenamientoView extends StatefulWidget {
  final ValueChanged<int>? onHorizontalTabSwipe;

  const EntrenamientoView({super.key, this.onHorizontalTabSwipe});

  @override
  State<EntrenamientoView> createState() => _EntrenamientoViewState();
}

class _EntrenamientoViewState extends State<EntrenamientoView> {
  static const int _minDefaultExercises = 6;
  bool _isTraining = false;
  int _secondsElapsed = 0;
  Timer? _timer;

  // Persistence state
  bool _isLoading = true;
  WorkoutSession? _currentSession;
  List<dynamic> _todayExercises = [];
  final TrainingService _trainingService = TrainingService();

  // Timeline state
  DateTime _selectedDate = DateTime.now();
  final Set<String> _trainedDates = {};

  // Configuración de perfil
  bool _isFemale = false;
  Map<int, bool> _trainingDays = {
    1: true, // Lunes
    2: true, // Martes
    3: true, // Miércoles
    4: true, // Jueves
    5: true, // Viernes
    6: false, // Sábado (Descanso)
    7: false, // Domingo (Descanso)
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadTrainedDates();
    _loadWorkoutForDate(_selectedDate);
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isFemale = prefs.getBool('is_female') ?? false;
      // Cargar días de entrenamiento (serializados como string)
      final daysStr = prefs.getString('training_days');
      if (daysStr != null) {
        final Map<String, dynamic> decoded = jsonDecode(daysStr);
        _trainingDays = decoded
            .map((key, value) => MapEntry(int.parse(key), value as bool));
      }
    });
  }

  Future<void> _loadWorkoutForDate(DateTime date) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final session = await _trainingService.getWorkoutForDate(date);
    List<dynamic> exercises = [];

    if (session != null) {
      if (session.exercisesList.isNotEmpty) {
        exercises = List.from(session.exercisesList);
      } else if (_isSameDay(date, DateTime.now())) {
        exercises = List.from(_getRoutineForDay(date));
      }
    } else if (_isSameDay(date, DateTime.now())) {
      exercises = List.from(_getRoutineForDay(date));
    }

    if (mounted) {
      setState(() {
        _currentSession = session;
        _todayExercises = _ensureMinimumExercises(
          List<Map<String, dynamic>>.from(
            exercises.map((e) => Map<String, dynamic>.from(e as Map)),
          ),
          date,
        );
        _isLoading = false;
        if (session?.isCompleted == true) {
          _trainedDates.add(_formatDateKey(date));
        }
      });
    }
  }

  Future<void> _loadTodayWorkout() async {
    await _loadWorkoutForDate(DateTime.now());
  }

  Future<void> _persistProgress() async {
    if (!_isSameDay(_selectedDate, DateTime.now())) return;
    if (_currentSession?.isCompleted == true) return;

    await _trainingService.saveTodayProgress(
      _currentSession?.workoutId,
      _todayExercises,
      durationSeconds: _secondsElapsed,
    );
  }

  String _formatDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isTraining = false;
      _timer?.cancel();
    });
    _loadWorkoutForDate(date);
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_female', _isFemale);
    await prefs.setString('training_days',
        jsonEncode(_trainingDays.map((k, v) => MapEntry(k.toString(), v))));
    _loadTodayWorkout(); // Recargar para aplicar cambios
  }

  List<Map<String, dynamic>> _getRoutineForDay(DateTime date) {
    final int weekday = date.weekday;
    final bool isTrainingDay = _trainingDays[weekday] ?? false;

    if (!isTrainingDay) {
      return []; // Lista vacía indica Descanso Activo
    }

    // Lógica de generación basada en sexo
    if (_isFemale) {
      return _getFemaleRoutine(weekday);
    } else {
      return _getMaleRoutine(weekday);
    }
  }

  List<Map<String, dynamic>> _getFemaleRoutine(int weekday) {
    // Prioridad Tren Inferior
    final routines = [
      [
        {'nombre': 'Sentadillas Copa', 'series': '4 x 12', 'completado': false},
        {'nombre': 'Hip Thrust', 'series': '4 x 15', 'completado': false},
        {'nombre': 'Zancadas Atrás', 'series': '3 x 12', 'completado': false},
        {
          'nombre': 'Peso Muerto Rumano',
          'series': '3 x 12',
          'completado': false
        },
        {
          'nombre': 'Abducción en Máquina',
          'series': '3 x 15',
          'completado': false
        },
        {'nombre': 'Gemelos de Pie', 'series': '4 x 18', 'completado': false},
      ],
      [
        {
          'nombre': 'Press Militar Manc',
          'series': '3 x 12',
          'completado': false
        },
        {'nombre': 'Jalón al Pecho', 'series': '3 x 12', 'completado': false},
        {'nombre': 'Remo en Polea', 'series': '3 x 12', 'completado': false},
        {'nombre': 'Plancha Lateral', 'series': '3 x 45s', 'completado': false},
        {
          'nombre': 'Elevaciones Laterales',
          'series': '3 x 15',
          'completado': false
        },
        {'nombre': 'Crunch en Polea', 'series': '3 x 18', 'completado': false},
      ],
    ];
    return routines[weekday % routines.length];
  }

  List<Map<String, dynamic>> _getMaleRoutine(int weekday) {
    // Prioridad Torso/Equilibrado
    final routines = [
      [
        {'nombre': 'Press de Banca', 'series': '4 x 10', 'completado': false},
        {'nombre': 'Press Inclinado', 'series': '3 x 12', 'completado': false},
        {'nombre': 'Aperturas Polea', 'series': '3 x 15', 'completado': false},
        {'nombre': 'Flexiones', 'series': '3 x fallo', 'completado': false},
        {
          'nombre': 'Fondos en Paralelas',
          'series': '3 x 10',
          'completado': false
        },
        {'nombre': 'Plancha', 'series': '3 x 60s', 'completado': false},
      ],
      [
        {'nombre': 'Dominadas', 'series': '4 x 8', 'completado': false},
        {'nombre': 'Remo con Barra', 'series': '3 x 10', 'completado': false},
        {'nombre': 'Sentadillas', 'series': '3 x 12', 'completado': false},
        {'nombre': 'Curl Bíceps', 'series': '3 x 12', 'completado': false},
        {'nombre': 'Face Pull', 'series': '3 x 15', 'completado': false},
        {'nombre': 'Ab Wheel', 'series': '3 x 12', 'completado': false},
      ],
    ];
    return routines[weekday % routines.length];
  }

  List<Map<String, dynamic>> _ensureMinimumExercises(
    List<Map<String, dynamic>> base,
    DateTime date,
  ) {
    if (base.isEmpty) return [];
    final result = List<Map<String, dynamic>>.from(base);
    if (result.length >= _minDefaultExercises) return result;

    final fallback = _isFemale
        ? _getFemaleRoutine(date.weekday)
        : _getMaleRoutine(date.weekday);

    int fallbackIndex = 0;
    while (result.length < _minDefaultExercises && fallback.isNotEmpty) {
      final exercise = Map<String, dynamic>.from(
        fallback[fallbackIndex % fallback.length],
      );
      final name = exercise['nombre']?.toString().trim().toLowerCase();
      final exists = result.any(
        (e) => e['nombre']?.toString().trim().toLowerCase() == name,
      );
      if (!exists) {
        exercise['completado'] = false;
        result.add(exercise);
      }
      fallbackIndex++;
      if (fallbackIndex > 24) break;
    }
    return result;
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
      });
    });
  }

  void _stopTraining() async {
    if (!_isSameDay(_selectedDate, DateTime.now())) return;

    _timer?.cancel();
    final elapsedSeconds = _secondsElapsed;
    final allCompleted = _todayExercises.isNotEmpty &&
        _todayExercises.every((e) => e['completado'] == true);

    setState(() {
      _isTraining = false;
    });

    if (allCompleted) {
      setState(() => _isLoading = true);
      final response = await _trainingService.completeWorkout(
        _currentSession?.workoutId,
        _todayExercises,
        durationSeconds: elapsedSeconds,
      );
      if (response != null) {
        final dateStr = _formatDateKey(_selectedDate);
        setState(() => _trainedDates.add(dateStr));
        await _saveTrainedDate(dateStr);
        await SocialState().syncCurrentUser();
        final duelService = DuelService();
        final duelPts = await duelService.checkAndCalculateDuelPoints();
        if (duelPts['isCompletedToday'] == true) {
          await duelService.applyTrainingPointsToDuels(
            duelPts['points'] as int? ?? 100,
          );
        }
        await _loadTodayWorkout();

        if (mounted && response['rewards'] != null) {
          _showRewardsDialog(response['rewards']);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '✅ Entrenamiento completado - ${_selectedDate.day}/${_selectedDate.month}',
              ),
              backgroundColor: FeedPalette.accent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
      setState(() => _isLoading = false);
    } else {
      await _persistProgress();
    }

    if (mounted) {
      _showSummary(elapsedSeconds);
      setState(() => _secondsElapsed = 0);
    }
  }

  Future<void> _saveTrainedDate(String dateStr) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final trainedDates = prefs.getStringList('trained_dates') ?? [];
      if (!trainedDates.contains(dateStr)) {
        trainedDates.add(dateStr);
        await prefs.setStringList('trained_dates', trainedDates);
      }
    } catch (e) {
      debugPrint('Error saving trained date: $e');
    }
  }

  Future<void> _loadTrainedDates() async {
    try {
      final history = await _trainingService.getHistory();
      final fromApi = history.where((h) => h['isCompleted'] == true).map((h) {
        final raw = h['date'];
        if (raw == null) return '';
        final s = raw.toString();
        return s.length >= 10 ? s.substring(0, 10) : s;
      }).where((d) => d.isNotEmpty);

      final prefs = await SharedPreferences.getInstance();
      final localDates = prefs.getStringList('trained_dates') ?? [];

      if (mounted) {
        setState(() {
          _trainedDates
            ..clear()
            ..addAll({...fromApi, ...localDates});
        });
      }
    } catch (e) {
      debugPrint('Error loading trained dates: $e');
    }
  }

  void _showRewardsDialog(Map<String, dynamic> rewards) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¡EXCELENTE TRABAJO!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.accent,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildRewardItem(
                    icon: Icons.flash_on,
                    value: '+${rewards['xpEarned']}',
                    label: 'XP Gānada',
                    color: Colors.amber,
                  ),
                  _buildRewardItem(
                    icon: Icons.monetization_on,
                    value: '+${rewards['coinsEarned']}',
                    label: 'FitCoins',
                    color: Colors.blue,
                  ),
                ],
              ),
              if (rewards['leveledUp'] == true) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FeedPalette.surfaceSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FeedPalette.muted),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.trending_up, color: Colors.green),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          '¡HAS SUBIDO DE NIVEL!',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ),
                      Text(
                        'Nv. ${rewards['newLevel']}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.local_fire_department, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text(
                    'Racha actual: ${rewards['streak']} días',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: FeedPalette.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FeedPalette.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'CONTINUAR',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRewardItem({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(26),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 30),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: FeedPalette.text,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: FeedPalette.muted),
        ),
      ],
    );
  }

  void _showSummary(int elapsedSeconds) {
    final displayTime = _formatTime(elapsedSeconds);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FeedPalette.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: FeedPalette.accent,
                  size: 50,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '¡SESIÓN FINALIZADA!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.text,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Has dado un paso más hacia tu mejor versión hoy. ¡Sigue así!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: FeedPalette.muted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: FeedPalette.surfaceSoft,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: FeedPalette.border.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      color: FeedPalette.accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TIEMPO TOTAL',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: FeedPalette.muted,
                          ),
                        ),
                        Text(
                          displayTime,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: FeedPalette.text,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FeedPalette.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 8,
                    shadowColor: FeedPalette.accent.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    '¡ENTENDIDO!',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    int mins = seconds ~/ 60;
    int secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _empezarRutina() {
    if (!_isSameDay(_selectedDate, DateTime.now())) return;
    if (_currentSession?.isCompleted == true) return;

    if (_isTraining) {
      _stopTraining();
    } else {
      setState(() {
        _isTraining = true;
        _secondsElapsed = _currentSession?.durationSeconds ?? 0;
      });
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: FeedPalette.background,
        body: Center(
          child: CircularProgressIndicator(color: FeedPalette.accent),
        ),
      );
    }

    var ejercicios = _todayExercises;
    int total = ejercicios.length;
    int completados = ejercicios.where((e) => e['completado'] == true).length;
    final bool isViewingToday = _isSameDay(_selectedDate, DateTime.now());
    bool sessionCompletedToday =
        isViewingToday && (_currentSession?.isCompleted ?? false);
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final bottomContentPadding = 96.0 + bottomSafeArea;
    final floatingButtonBottom = 96.0 + bottomSafeArea;

    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _isSameDay(_selectedDate, DateTime.now())
              ? (_currentSession?.workoutTitle ?? 'Entrenamiento')
              : 'Entrenamiento - ${_selectedDate.day}/${_selectedDate.month}',
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
        actions: [
          IconButton(
            icon:
                Icon(Icons.settings_suggest_rounded, color: FeedPalette.accent),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            icon: Icon(Icons.history, color: FeedPalette.muted),
            onPressed: _showHistory,
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: FeedPalette.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today, color: FeedPalette.accent, size: 16),
                const SizedBox(width: 4),
                Text(
                  '${_trainedDates.length} días',
                  style: TextStyle(
                    color: FeedPalette.accent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: HorizontalTabSwipeListener(
        onMainTabSwipe: widget.onHorizontalTabSwipe,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(gradient: FeedPalette.screenGradient),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.fromLTRB(16, 16, 16, bottomContentPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDaySelector(),
                    const SizedBox(height: 24),
                    _buildResumenHoy(completados, total, sessionCompletedToday),
                    const SizedBox(height: 24),
                    _buildListaEjercicios(ejercicios, sessionCompletedToday),
                    const SizedBox(height: 2),
                    _buildAddExerciseButton(),
                    const SizedBox(height: 4),
                    _buildAITrainingButton(),
                    const SizedBox(height: 6),
                    _buildSugerenciasEjercicios(),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: floatingButtonBottom,
              right: 16,
              child: _buildChatBotFab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final daysOfWeek = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: FeedPalette.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FeedPalette.border),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        itemCount: 7,
        itemBuilder: (context, index) {
          final date = startOfWeek.add(Duration(days: index));
          final isSelected = _isSameDay(date, _selectedDate);
          final isToday = _isSameDay(date, now);
          final isTrained = _trainedDates.contains(_formatDateKey(date));

          return GestureDetector(
            onTap: () => _selectDate(date),
            child: Container(
              width: 50,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: isSelected ? FeedPalette.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? FeedPalette.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    daysOfWeek[index],
                    style: TextStyle(
                      color: isSelected ? Colors.white : FeedPalette.muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isToday ? FeedPalette.accent : FeedPalette.text),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isTrained)
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  Widget _buildWeekendRestCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: FeedPalette.border),
        boxShadow: [
          BoxShadow(
            color: FeedPalette.accent.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: FeedPalette.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.self_improvement, color: Colors.grey, size: 30),
          ),
          const SizedBox(height: 16),
          Text(
            'Descanso Activo',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: FeedPalette.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Hoy toca recuperar. Te sugerimos una actividad ligera como salir a caminar 30 min o un paseo suave en bicicleta.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: FeedPalette.text,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _completeWeekendActivity,
              icon: Icon(Icons.check_circle_outline),
              label: Text('Completar Actividad'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF9E9E9E),
                foregroundColor: FeedPalette.muted,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _completeWeekendActivity() {
    final dateStr = _formatDateKey(_selectedDate);
    setState(() {
      _trainedDates.add(dateStr);
    });
    _saveTrainedDate(dateStr);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Actividad de fin de semana completada'),
        backgroundColor: Color(0xFF9E9E9E),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildAddExerciseButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _showAddExerciseDialog,
        icon: Icon(Icons.add_circle_outline, color: FeedPalette.accent),
        label: Text(
          'Añadir ejercicio personalizado',
          style: TextStyle(
            color: FeedPalette.accent,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildAITrainingButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AITrainingView()),
          );

          if (!mounted) return;

          if (result != null && result is Map<String, dynamic>) {
            final reps = result['reps'] as int;
            final exercise = result['exercise'] as String;

            if (reps > 0) {
              // Añadir a la rutina de hoy
              setState(() {
                _todayExercises.add({
                  'nombre': '$exercise AI',
                  'series': '$reps reps',
                  'completado': true,
                });
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('¡Completaste $reps $exercise con IA! 🎉'),
                ),
              );
            }
          }
        },
        icon: Icon(Icons.center_focus_strong, color: Colors.white),
        label: Text(
          'Corrección por IA (Cámara)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple.shade600,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
        ),
      ),
    );
  }

  Future<void> _showAddExerciseDialog() async {
    final catalog = await _trainingService.getCatalogExercises();
    if (!mounted) return;

    if (catalog.isNotEmpty) {
      final grouped = <String, List<Map<String, dynamic>>>{
        for (final category in AdminCatalogOptions.exerciseCategories)
          category: <Map<String, dynamic>>[],
      };
      for (final item in catalog) {
        final category =
            (item['category']?.toString().trim().isNotEmpty == true)
                ? item['category'].toString().trim()
                : 'Sin categoria';
        grouped.putIfAbsent(category, () => []).add(item);
      }
      grouped.removeWhere((_, items) => items.isEmpty);

      final picked = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        backgroundColor: FeedPalette.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) {
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  'Catalogo de ejercicios',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: FeedPalette.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Elige un ejercicio creado en el centro de control.',
                  style: TextStyle(color: FeedPalette.muted),
                ),
                const SizedBox(height: 12),
                ...grouped.entries.expand((entry) {
                  return [
                    Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 6),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: FeedPalette.accent,
                        ),
                      ),
                    ),
                    ...entry.value.map(
                      (exercise) => ListTile(
                        leading: Icon(
                          Icons.fitness_center,
                          color: FeedPalette.accent,
                        ),
                        title: Text(
                          exercise['name']?.toString() ?? 'Ejercicio',
                          style: TextStyle(color: FeedPalette.text),
                        ),
                        subtitle: Text(
                          exercise['description']?.toString() ?? '',
                          style: TextStyle(color: FeedPalette.muted),
                        ),
                        onTap: () => Navigator.pop(context, exercise),
                      ),
                    ),
                  ];
                }),
                ListTile(
                  leading:
                      Icon(Icons.add_circle_outline, color: FeedPalette.accent),
                  title: Text(
                    'Crear ejercicio manual',
                    style: TextStyle(color: FeedPalette.text),
                  ),
                  onTap: () => Navigator.pop(context, const {}),
                ),
              ],
            ),
          );
        },
      );

      if (picked != null) {
        if (picked.isEmpty) {
          _showManualAddExerciseDialog();
          return;
        }
        setState(() {
          _todayExercises.add({
            'nombre': picked['name']?.toString() ?? 'Ejercicio',
            'series': '3 x 10',
            'completado': false,
            'categoria': picked['category']?.toString() ?? 'Sin categoria',
          });
        });
        await _persistProgress();
        return;
      }
      return;
    }

    _showManualAddExerciseDialog();
  }

  void _showManualAddExerciseDialog() {
    final nombreCtrl = TextEditingController();
    final seriesCtrl = TextEditingController();
    final categoriaCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: FeedPalette.surface,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: FeedPalette.accent.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.fitness_center_rounded,
                  color: FeedPalette.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Nuevo Ejercicio',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.text,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Personaliza tu rutina de hoy',
                style: TextStyle(color: FeedPalette.muted, fontSize: 13),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: nombreCtrl,
                style: TextStyle(color: FeedPalette.text),
                decoration: FeedPalette.inputDecoration(
                  hint: 'Nombre (ej: Dominadas)',
                  icon: Icons.edit_note_rounded,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: seriesCtrl,
                style: TextStyle(color: FeedPalette.text),
                decoration: FeedPalette.inputDecoration(
                  hint: 'Series x Reps (ej: 4 x 10)',
                  icon: Icons.repeat_one_rounded,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoriaCtrl,
                style: TextStyle(color: FeedPalette.text),
                decoration: FeedPalette.inputDecoration(
                  hint: 'Categoria (ej: Fuerza)',
                  icon: Icons.category_outlined,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'CANCELAR',
                        style: TextStyle(
                          color: FeedPalette.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (nombreCtrl.text.isNotEmpty) {
                          setState(() {
                            _todayExercises.add({
                              'nombre': nombreCtrl.text,
                              'series': seriesCtrl.text.isEmpty
                                  ? '3 x 10'
                                  : seriesCtrl.text,
                              'completado': false,
                              'categoria': categoriaCtrl.text.trim().isEmpty
                                  ? 'Personalizado'
                                  : categoriaCtrl.text.trim(),
                            });
                          });
                          Navigator.pop(context);
                        }
                      },
                      style: FeedPalette.primaryButtonStyle(radius: 16),
                      child: Text(
                        'AÑADIR',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatBotFab() {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: FeedPalette.accent.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: _showChatBot,
        backgroundColor: FeedPalette.accent,
        heroTag: 'chatbot_training',
        elevation: 0,
        child: Icon(Icons.auto_awesome_rounded, color: Colors.white),
      ),
    );
  }

  void _showChatBot() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => const _FitChatBot(),
    );
  }

  void _showHistory() async {
    // Mostrar un indicador de carga opcional o simplemente esperar
    final history = await _trainingService.getHistory();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => _WorkoutHistoryDialog(history: history),
    );
  }

  Widget _buildResumenHoy(int completados, int total, bool isAlreadyCompleted) {
    double progreso = total > 0 ? completados / total : 0;
    if (isAlreadyCompleted) progreso = 1.0;
    return Card(
      elevation: 4,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              FeedPalette.accent,
              FeedPalette.accent.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Progreso de Hoy',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$completados de $total ejercicios',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isAlreadyCompleted &&
                        (_currentSession?.durationSeconds ?? 0) > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Tiempo: ${_formatTime(_currentSession!.durationSeconds)}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progreso,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                        strokeWidth: 6,
                      ),
                      Text(
                        '${(progreso * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isTraining) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timer, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(_secondsElapsed),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 15),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isAlreadyCompleted ? null : _empezarRutina,
                icon: Icon(
                  isAlreadyCompleted
                      ? Icons.check_circle
                      : (_isTraining ? Icons.stop : Icons.play_arrow),
                ),
                label: Text(
                  isAlreadyCompleted
                      ? 'COMPLETADO'
                      : (_isTraining ? 'FINALIZAR' : 'EMPEZAR'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAlreadyCompleted
                      ? Colors.green
                      : (_isTraining ? Colors.red : Colors.white),
                  foregroundColor: isAlreadyCompleted
                      ? Colors.white
                      : (_isTraining ? Colors.white : FeedPalette.accent),
                  disabledBackgroundColor: Colors.green,
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addNewExerciseManual() {
    final nombreCtrl = TextEditingController();
    final seriesCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Añadir nuevo ejercicio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(
                labelText: 'Nombre del ejercicio',
              ),
            ),
            TextField(
              controller: seriesCtrl,
              decoration: const InputDecoration(
                labelText: 'Series x Reps (ej: 3x12)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nombreCtrl.text.isNotEmpty) {
                setState(() {
                  _todayExercises.add({
                    'nombre': nombreCtrl.text,
                    'series':
                        seriesCtrl.text.isEmpty ? '3 x 10' : seriesCtrl.text,
                    'completado': false,
                  });
                });
                _persistProgress();
                Navigator.pop(context);
              }
            },
            child: Text('AÑADIR'),
          ),
        ],
      ),
    );
  }

  Widget _buildListaEjercicios(
    List<dynamic> ejercicios,
    bool isAlreadyCompleted,
  ) {
    final isRestDay = !(_trainingDays[_selectedDate.weekday] ?? true);

    if (isRestDay) {
      return _buildWeekendRestCard();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Rutina del Día',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.text),
            ),
            if (!isAlreadyCompleted)
              TextButton.icon(
                onPressed: _addNewExerciseManual,
                icon: Icon(Icons.add, size: 18),
                label: Text('Añadir'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ejercicios.length,
          itemBuilder: (context, index) {
            var ex = ejercicios[index];
            bool isCompleted = ex['completado'] == true || isAlreadyCompleted;
            return _buildExerciseCard(
              index,
              ex,
              isCompleted,
              isAlreadyCompleted,
              isLast: index == ejercicios.length - 1,
            );
          },
        ),
      ],
    );
  }

  Widget _buildExerciseCard(
    int index,
    dynamic ex,
    bool isCompleted,
    bool isAlreadyCompleted, {
    bool isLast = false,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 2 : 10),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? Colors.green.withValues(alpha: 0.3)
              : FeedPalette.border,
        ),
      ),
      child: ListTile(
        onTap: (_isTraining &&
                !isAlreadyCompleted &&
                _isSameDay(_selectedDate, DateTime.now()))
            ? () async {
                setState(() {
                  ex['completado'] = !isCompleted;
                });
                await _persistProgress();
                final allCompleted = _todayExercises.every(
                  (e) => e['completado'] == true,
                );
                if (allCompleted) {
                  _stopTraining();
                }
              }
            : (isAlreadyCompleted || !_isSameDay(_selectedDate, DateTime.now()))
                ? null
                : () => _editExercise(index),
        leading: Icon(
          isCompleted ? Icons.check_circle : Icons.fitness_center,
          color: isCompleted ? Colors.green : FeedPalette.accent,
        ),
        title: Text(
          ex['nombre'],
          style: TextStyle(
            fontWeight: FontWeight.bold,
            decoration: isCompleted ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(ex['series']),
        trailing: Icon(
          isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
          color: isCompleted ? Colors.green : FeedPalette.border,
        ),
      ),
    );
  }

  void _editExercise(int index) {
    final ex = _todayExercises[index];
    final nombreCtrl = TextEditingController(text: ex['nombre']);
    final seriesCtrl = TextEditingController(text: ex['series']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Editar ejercicio'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nombreCtrl,
              decoration: const InputDecoration(labelText: 'Nombre'),
            ),
            TextField(
              controller: seriesCtrl,
              decoration: const InputDecoration(labelText: 'Series/Reps'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _todayExercises[index]['nombre'] = nombreCtrl.text;
                _todayExercises[index]['series'] = seriesCtrl.text;
              });
              _persistProgress();
              Navigator.pop(context);
            },
            child: Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  Widget _buildSugerenciasEjercicios() {
    final bool isRestDay = !(_trainingDays[_selectedDate.weekday] ?? true);

    List<Widget> suggestions = [];

    if (isRestDay) {
      // Sugerencias de Descanso Activo (Baja intensidad)
      suggestions = [
        _buildSugerenciaCard(
          'Caminata 30min',
          'Recuperación suave',
          Icons.directions_walk,
          'Ligero',
          'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?q=80&w=500',
        ),
        _buildSugerenciaCard(
          'Yoga/Movilidad',
          'Mejora tu rango',
          Icons.self_improvement,
          '15 min',
          'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?q=80&w=500',
        ),
      ];
    } else {
      if (_isFemale) {
        // Sugerencias Prioridad Pierna/Glúteo
        suggestions = [
          _buildSugerenciaCard(
            'Glute Bridge',
            'Aísla el glúteo',
            Icons.fitness_center,
            '3 x 20',
            'https://images.unsplash.com/photo-1434608519344-49d77a699e1d?q=80&w=500',
          ),
          _buildSugerenciaCard(
            'Abductores',
            'Tonificación lateral',
            Icons.accessibility_new,
            '3 x 15',
            'https://images.unsplash.com/photo-1518310383802-640c2de311b2?q=80&w=500',
          ),
        ];
      } else {
        // Sugerencias Prioridad Torso
        suggestions = [
          _buildSugerenciaCard(
            'Dominadas',
            'Ensancha tu espalda',
            Icons.nordic_walking,
            '4 x 10',
            'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?q=80&w=500',
          ),
          _buildSugerenciaCard(
            'Burpees',
            'HIIT explosivo',
            Icons.flash_on,
            '3 x 15',
            'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?q=80&w=500',
          ),
        ];
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sugerencias AI',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: FeedPalette.text,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 160,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: suggestions,
          ),
        ),
      ],
    );
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: FeedPalette.surface,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon and Title
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4632B).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.settings_suggest,
                      color: Color(0xFFD4632B), size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'Personalizar Plan',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: FeedPalette.text,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ajusta tu rutina a tus necesidades',
                  style: TextStyle(
                      color: FeedPalette.text.withValues(alpha: 0.6),
                      fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Female Profile Card
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isFemale
                        ? const Color(0xFFD4632B).withValues(alpha: 0.05)
                        : FeedPalette.surfaceSoft,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _isFemale
                          ? const Color(0xFFD4632B).withValues(alpha: 0.3)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isFemale ? Icons.woman : Icons.man,
                        color: _isFemale
                            ? const Color(0xFFD4632B)
                            : FeedPalette.muted,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Perfil Femenino',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: FeedPalette.text,
                              ),
                            ),
                            Text(
                              'Prioriza glúteos y piernas',
                              style: TextStyle(
                                  fontSize: 12, color: FeedPalette.muted),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        activeThumbColor: const Color(0xFFD4632B),
                        value: _isFemale,
                        onChanged: (v) {
                          setState(() => _isFemale = v);
                          setModalState(() => _isFemale = v);
                          _saveSettings();
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Days Selector Title
                Row(
                  children: [
                    Icon(Icons.calendar_today,
                        size: 16, color: FeedPalette.muted),
                    const SizedBox(width: 8),
                    Text(
                      'Días de entrenamiento',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: FeedPalette.text,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Days Wrap
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [1, 2, 3, 4, 5, 6, 7].map((day) {
                    final daysNames = ['', 'L', 'M', 'X', 'J', 'V', 'S', 'D'];
                    final isSelected = _trainingDays[day] ?? false;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _trainingDays[day] = !isSelected);
                        setModalState(() => _trainingDays[day] = !isSelected);
                        _saveSettings();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSelected
                              ? const Color(0xFFD4632B)
                              : FeedPalette.surfaceSoft,
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFFD4632B)
                                        .withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            daysNames[day],
                            style: TextStyle(
                              color:
                                  isSelected ? Colors.white : FeedPalette.muted,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),

                // Done Button
                Container(
                  width: double.infinity,
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD4632B), Color(0xFFE88A54)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFD4632B).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text(
                      'Guardar Cambios',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSugerenciaCard(
    String title,
    String desc,
    IconData icon,
    String sets,
    String imageUrl,
  ) {
    return InkWell(
      onTap: () {
        setState(() {
          _todayExercises.add({
            'nombre': title,
            'series': sets,
            'completado': false,
          });
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('He añadido $title a tu rutina de hoy')),
        );
      },
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: FeedPalette.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: FeedPalette.accent.withAlpha(51)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => Container(
                          color: FeedPalette.accent.withAlpha(26),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  FeedPalette.accent,
                                ),
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: FeedPalette.surfaceSoft,
                          child: const Center(
                            child: Icon(
                              Icons.fitness_center,
                              color: Colors.grey,
                              size: 24,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(15),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withAlpha(77),
                        ],
                      ),
                    ),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(icon, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: FeedPalette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sets,
                    style: TextStyle(
                      fontSize: 11,
                      color: FeedPalette.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.add_circle,
                        size: 16,
                        color: FeedPalette.muted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Añadir',
                        style: TextStyle(
                          fontSize: 10,
                          color: FeedPalette.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkoutHistoryDialog extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _WorkoutHistoryDialog({required this.history});

  static DateTime? _parseHistoryDate(dynamic raw) {
    if (raw == null) return null;
    try {
      return DateTime.parse(raw.toString()).toLocal();
    } catch (_) {
      return null;
    }
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
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];

  static List<String> _historyDetailLines(Map<String, dynamic> item) {
    final completedAt = _parseHistoryDate(item['completedAt']) ??
        _parseHistoryDate(item['date']);
    final durationSeconds = int.tryParse('${item['durationSeconds']}') ?? 0;

    if (completedAt == null) {
      return const ['Sin datos de hora'];
    }

    final day = _weekdayNames[completedAt.weekday - 1];
    final month = _monthNames[completedAt.month - 1];
    final dateLine = '$day, ${completedAt.day} $month ${completedAt.year}';
    final time =
        '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')}';

    String durationLabel = '';
    if (durationSeconds > 0) {
      final mins = durationSeconds ~/ 60;
      final secs = durationSeconds % 60;
      if (mins > 0) {
        durationLabel = '$mins min ${secs.toString().padLeft(2, '0')} seg';
      } else {
        durationLabel = '$secs seg';
      }
    }

    if (durationLabel.isEmpty) {
      return [dateLine, time];
    }
    return [dateLine, '$time · $durationLabel'];
  }

  @override
  Widget build(BuildContext context) {
    final completed = history.where((h) => h['isCompleted'] == true).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      height: MediaQuery.of(context).size.height * 0.7,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: FeedPalette.muted,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Historial de Entrenos',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: FeedPalette.text,
                ),
              ),
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          Text(
            history.isEmpty
                ? 'Aún no has registrado entrenos.'
                : '$completed completados · ${history.length} en total',
            style: TextStyle(
              color: FeedPalette.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Text(
                      'No hay entrenamientos registrados aún.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      final isDone = item['isCompleted'] == true;
                      return _buildHistoryItem(
                        _historyDetailLines(item),
                        item['workoutTitle']?.toString() ?? 'Entrenamiento',
                        isDone,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    List<String> detailLines,
    String title,
    bool completed,
  ) {
    final accent = completed ? Colors.green : FeedPalette.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
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
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                completed ? Icons.check_rounded : Icons.fitness_center_rounded,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: FeedPalette.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...detailLines.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        line,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: FeedPalette.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                completed ? 'Hecho' : 'Pendiente',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FitChatBot extends StatefulWidget {
  const _FitChatBot();
  @override
  State<_FitChatBot> createState() => _FitChatBotState();
}

class _FitChatBotState extends State<_FitChatBot> {
  final List<Map<String, String>> _messages = [
    {
      'role': 'bot',
      'text': '¡Hola! Soy tu FitBot. ¿En qué puedo ayudarte hoy?',
    },
  ];
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;

  Future<void> _sendMessage() async {
    if (_controller.text.isEmpty) return;

    String userText = _controller.text;

    setState(() {
      _messages.add({'role': 'user', 'text': userText});
      _isLoading = true;
    });
    _controller.clear();

    try {
      final token = AuthService().token;
      if (token == null || token.isEmpty) {
        setState(() {
          _messages.add({
            'role': 'bot',
            'text': '⚠️ Necesitas iniciar sesión para hablar conmigo.',
          });
        });
        return;
      }

      final response = await http.post(
        Uri.parse('${ApiConstants.trainingBaseUrl}/fitbot/chat'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'messages': _messages
              .map(
                (m) => {
                  'role': m['role'] == 'bot' ? 'assistant' : 'user',
                  'content': m['text'],
                },
              )
              .toList(),
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = data['choices'][0]['message']['content'];
        setState(() {
          _messages.add({'role': 'bot', 'text': reply});
        });
      } else {
        setState(() {
          _messages.add({
            'role': 'bot',
            'text':
                'Vaya, he perdido la conexión con el gimnasio. Intenta de nuevo. 🏋️',
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'bot',
            'text': 'Uf... se me resbaló una mancuerna. Falló mi red. 🔧',
          });
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: FeedPalette.muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'FitBot AI 🏋️',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: FeedPalette.text,
            ),
          ),
          Text(
            'Tu entrenador personal 24/7',
            style: TextStyle(
              fontSize: 12,
              color: FeedPalette.muted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final m = _messages[index];
                bool isBot = m['role'] == 'bot';
                return Align(
                  alignment:
                      isBot ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          isBot ? FeedPalette.surfaceSoft : FeedPalette.accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      m['text']!,
                      style: TextStyle(
                        color: isBot ? FeedPalette.text : Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Builder(
            builder: (context) {
              final mediaQuery = MediaQuery.of(context);
              final keyboardInset = mediaQuery.viewInsets.bottom;
              final safeBottom = mediaQuery.padding.bottom;
              final bottomPadding = keyboardInset > 0
                  ? keyboardInset + 12.0
                  : (safeBottom > 0 ? safeBottom + 12.0 : 16.0);

              return Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, bottomPadding),
                decoration: BoxDecoration(
                  color: FeedPalette.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 14,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: Icon(
                        Icons.attach_file,
                        color: FeedPalette.accent,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        onSubmitted: (_) => _sendMessage(),
                        style: FeedPalette.bodyTextStyle,
                        decoration: FeedPalette.textFieldDecoration(
                          hint: 'Pregunta sobre tu entrenamiento...',
                          radius: 25,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                        ).copyWith(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: _isLoading ? null : _sendMessage,
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: FeedPalette.accent,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
