import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rms/shared/themes/feed_palette.dart';
import 'nutrition_ai_service.dart';

class NutritionChatbotPage extends StatefulWidget {
  const NutritionChatbotPage({super.key});

  @override
  State<NutritionChatbotPage> createState() => _NutritionChatbotPageState();
}

class _NutritionChatbotPageState extends State<NutritionChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final NutritionAIService _aiService = NutritionAIService();
  final List<Map<String, String>> _chatContext = [];

  static const List<String> _mealSlots = <String>[
    'Desayuno',
    'Almuerzo',
    'Comida',
    'Merienda',
    'Cena',
  ];

  bool _isLoading = false;
  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String _loadingLabel = 'Analizando imagen...';

  @override
  void initState() {
    super.initState();
    _addBotMessage(
      '¡Hola! Soy tu asistente nutricional IA.\n\nPuedes:\n- Enviarme una foto y te estimo calorías y macros.\n- Preguntarme sobre comidas, recetas, ideas de menú o cómo ajustar tu dieta a tu objetivo.\n\nNota: solo respondo sobre nutrición/comida.',
    );
  }

  void _addBotMessage(String text, {NutritionAnalysis? analysis}) {
    setState(() {
      _messages.add(ChatMessage(text: text, isBot: true, analysis: analysis));
    });
  }

  void _addUserMessage(String text, {Uint8List? imageBytes}) {
    setState(() {
      _messages.add(
        ChatMessage(text: text, isBot: false, imageBytes: imageBytes),
      );
    });
  }

  Future<String?> _pickMealSlotForToday() async {
    Set<String> occupied = <String>{};
    try {
      final meals = await _aiService.getTodayMeals();
      for (final meal in meals) {
        final type = (meal['mealType'] ?? '').toString();
        if (_mealSlots.contains(type)) occupied.add(type);
      }
    } catch (_) {
      // If loading fails, still allow choosing a slot and let the backend enforce uniqueness.
      occupied = <String>{};
    }

    if (!mounted) return null;

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿En qué apartado lo guardo?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: _mealSlots.map((slot) {
              final isUsed = occupied.contains(slot);
              return ListTile(
                leading: Icon(
                  isUsed
                      ? Icons.lock_outline_rounded
                      : Icons.check_circle_outline_rounded,
                  color: isUsed ? Colors.grey : FeedPalette.accent,
                ),
                title: Text(slot),
                subtitle: isUsed
                    ? const Text('Ya hay una comida registrada hoy')
                    : null,
                enabled: !isUsed,
                onTap: isUsed ? null : () => Navigator.pop(context, slot),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty && _selectedImageBytes == null) return;

    final userText = _messageController.text.trim().isEmpty
        ? 'Foto de comida'
        : _messageController.text.trim();
    _addUserMessage(userText, imageBytes: _selectedImageBytes);
    _messageController.clear();
    final bytesToAnalyze = _selectedImageBytes;
    setState(() {
      _selectedImageBytes = null;
      _selectedImageName = null;
      _isLoading = true;
      _loadingLabel =
          bytesToAnalyze != null ? 'Analizando imagen...' : 'Pensando...';
    });

    if (bytesToAnalyze != null) {
      try {
        final analysis = await _aiService.analyzeImage(bytesToAnalyze);

        if (analysis != null) {
          setState(() => _isLoading = false);

          final slot = await _pickMealSlotForToday();
          if (slot == null || slot.trim().isEmpty) {
            _addBotMessage(
                'Vale, no lo guardo. Si quieres, vuelve a enviarme la foto y elige un apartado.');
            return;
          }

          setState(() {
            _isLoading = true;
            _loadingLabel = 'Guardando en $slot...';
          });

          await _aiService.saveMealFromAI(
            mealType: slot,
            analysis: analysis,
            imageBytes: bytesToAnalyze,
          );

          _addBotMessage(
            'He analizado tu comida. Aquí está el desglose nutricional:',
            analysis: analysis,
          );
          _addBotMessage('✅ Guardado en tu día de hoy.');

          if (!mounted) return;
          Navigator.pop(context);
          return;
        } else {
          _addBotMessage(
            'Lo siento, no he podido analizar la imagen. Intenta tomar una foto más clara con buena iluminación.',
          );
        }
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('Ya has registrado') ||
            msg.contains('ya has registrado')) {
          _addBotMessage(
              'Ese apartado ya tiene una comida hoy. Elige otro apartado e inténtalo otra vez.');
        } else {
          _addBotMessage(
            'Ha ocurrido un error al analizar/guardar la imagen. Por favor, inténtalo de nuevo.',
          );
        }
      }
    } else {
      try {
        _chatContext.add({'role': 'user', 'content': userText});
        final reply = await _aiService.chat(
            messages: List<Map<String, String>>.from(_chatContext));
        _chatContext.add({'role': 'assistant', 'content': reply});
        _addBotMessage(reply);
      } catch (e) {
        _addBotMessage(
            'No he podido responder ahora mismo. Revisa tu conexión/servidor y prueba otra vez.');
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 600,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = pickedFile.name;
      });
    }
  }

  Future<void> _takePhoto() async {
    final pickedFile = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 800,
      maxHeight: 600,
      imageQuality: 85,
    );

    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = pickedFile.name;
      });
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seleccionar imagen'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Tomar foto'),
              onTap: () {
                Navigator.pop(context);
                _takePhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galería'),
              onTap: () {
                Navigator.pop(context);
                _pickImage();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        title: Text(
          'Nutrición IA',
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: FeedPalette.background,
        elevation: 0,
        iconTheme: IconThemeData(color: FeedPalette.text),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_isLoading)
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(
                      FeedPalette.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _loadingLabel,
                    style: TextStyle(color: FeedPalette.accent),
                  ),
                ],
              ),
            ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            message.isBot ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (message.isBot) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: FeedPalette.accent,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.smart_toy, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: message.isBot
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                if (message.imageBytes != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        message.imageBytes!,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                if (message.analysis != null)
                  _buildAnalysisCard(message.analysis!)
                else
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: message.isBot
                          ? FeedPalette.surfaceSoft
                          : FeedPalette.accent,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      message.text,
                      style: TextStyle(
                        color: message.isBot ? FeedPalette.text : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!message.isBot) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, color: Colors.white, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisCard(NutritionAnalysis analysis) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: FeedPalette.accent.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            analysis.comida,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: FeedPalette.accent,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMacroChip(
                'Proteínas',
                '${analysis.proteinas}g',
                Colors.blue,
              ),
              const SizedBox(width: 8),
              _buildMacroChip(
                'Carbos',
                '${analysis.carbohidratos}g',
                Colors.orange,
              ),
              const SizedBox(width: 8),
              _buildMacroChip('Grasas', '${analysis.grasas}g', Colors.green),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: FeedPalette.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${analysis.calorias} kcal',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: FeedPalette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FeedPalette.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_selectedImageBytes != null)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: FeedPalette.inputFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _selectedImageBytes!,
                      height: 60,
                      width: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedImageName ?? 'Imagen seleccionada',
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _selectedImageBytes = null;
                        _selectedImageName = null;
                      });
                    },
                  ),
                ],
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: _showImageSourceDialog,
                icon: Icon(Icons.attach_file, color: FeedPalette.accent),
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  style: FeedPalette.bodyTextStyle,
                  decoration: FeedPalette.textFieldDecoration(
                    hint: 'Describe tu comida o envía una foto...',
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
                  child: const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isBot;
  final Uint8List? imageBytes;
  final NutritionAnalysis? analysis;

  ChatMessage({
    required this.text,
    required this.isBot,
    this.imageBytes,
    this.analysis,
  });
}
