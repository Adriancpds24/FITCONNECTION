import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../auth/auth_service.dart';
import '../../core/constants/api_constants.dart';
import 'package:rms/shared/themes/feed_palette.dart';

class UserMetricsForm extends StatefulWidget {
  final VoidCallback onSaved;
  const UserMetricsForm({super.key, required this.onSaved});

  @override
  State<UserMetricsForm> createState() => _UserMetricsFormState();
}

class _UserMetricsFormState extends State<UserMetricsForm> {
  final _formKey = GlobalKey<FormState>();

  double _weight = 70.0;
  double _height = 175.0;
  int _age = 25;
  String _sex = 'masculino';
  String _activityLevel = 'moderado';
  String _goal = 'Definición';

  bool _isSaving = false;

  Future<void> _saveMetrics() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();

    setState(() => _isSaving = true);

    try {
      final token = AuthService().token;
      final response = await http.post(
        Uri.parse('${ApiConstants.apiHost}/nutrition/metrics'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'weight': _weight,
          'height': _height,
          'age': _age,
          'sex': _sex,
          'activityLevel': _activityLevel,
          'goal': _goal,
        }),
      );

      if (response.statusCode == 200) {
        widget.onSaved();
      } else {
        throw Exception('Error al guardar métricas: ${response.body}');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    // Leave a small clearance so the bottom nav doesn't overlap the CTA.
    // Keep it tight so the button doesn't "float" too high.
    const bottomBarApproxHeight = 72.0;
    final bottomBarClearance = bottomBarApproxHeight + bottomInset + 2;

    return SingleChildScrollView(
      padding: EdgeInsets.only(bottom: bottomBarClearance + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configura tu Plan Inteligente',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Introduce tus datos para que calculemos tus macros exactos.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              children: [
                _buildMetricField(
                  'Peso (kg)',
                  Icons.monitor_weight_outlined,
                  (v) => _weight = double.parse(v!),
                ),
                const SizedBox(height: 16),
                _buildMetricField(
                  'Altura (cm)',
                  Icons.height,
                  (v) => _height = double.parse(v!),
                ),
                const SizedBox(height: 16),
                _buildMetricField(
                  'Edad',
                  Icons.calendar_today_outlined,
                  (v) => _age = int.parse(v!),
                ),
                const SizedBox(height: 24),
                _buildDropdown(
                    'Sexo',
                    _sex,
                    [
                      'masculino',
                      'femenino',
                    ],
                    (v) => setState(() => _sex = v!)),
                const SizedBox(height: 16),
                _buildDropdown(
                  'Actividad',
                  _activityLevel,
                  ['sedentario', 'ligero', 'moderado', 'activo', 'muy_activo'],
                  (v) => setState(() => _activityLevel = v!),
                ),
                const SizedBox(height: 16),
                _buildDropdown(
                    'Objetivo',
                    _goal,
                    [
                      'Volumen',
                      'Definición',
                      'Mantenimiento',
                    ],
                    (v) => setState(() => _goal = v!)),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveMetrics,
                    icon: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _isSaving ? 'Calculando…' : 'CALCULAR MI PLAN',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: FeedPalette.primaryButtonStyle(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricField(
    String label,
    IconData icon,
    Function(String?) onSave,
  ) {
    return TextFormField(
      initialValue: label.contains('Peso')
          ? '70'
          : (label.contains('Altura') ? '175' : '25'),
      style: FeedPalette.bodyTextStyle,
      decoration: FeedPalette.textFieldDecoration(
        hint: label,
        prefixIcon: Icon(icon, color: FeedPalette.accent),
      ).copyWith(labelText: label),
      keyboardType: TextInputType.number,
      onSaved: onSave,
    );
  }

  Widget _buildDropdown(
    String label,
    String value,
    List<String> items,
    Function(String?) onChange,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      dropdownColor: FeedPalette.surface,
      style: FeedPalette.bodyTextStyle,
      decoration: FeedPalette.textFieldDecoration(
        hint: label,
        prefixIcon: Icon(Icons.tune, color: FeedPalette.accent),
      ).copyWith(labelText: label),
      items: items
          .map(
            (i) => DropdownMenuItem(
              value: i,
              child: Text(i, style: FeedPalette.bodyTextStyle),
            ),
          )
          .toList(),
      onChanged: onChange,
    );
  }
}
