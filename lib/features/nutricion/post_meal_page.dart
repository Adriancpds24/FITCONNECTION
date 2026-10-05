import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../social/social_service.dart';
import '../social/social_state.dart';
import '../../shared/themes/feed_palette.dart';

class PostMealPage extends StatefulWidget {
  final String? initialMealDesc;
  const PostMealPage({super.key, this.initialMealDesc});

  @override
  State<PostMealPage> createState() => _PostMealPageState();
}

class _PostMealPageState extends State<PostMealPage> {
  final TextEditingController _descController = TextEditingController();
  Uint8List? _imageBytes;
  bool _isPosting = false;
  String _destination = 'Post'; // 'Post' o 'Historia'

  @override
  void initState() {
    super.initState();
    if (widget.initialMealDesc != null) {
      _descController.text = widget.initialMealDesc!;
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final img = await picker.pickImage(source: ImageSource.gallery);
    if (img != null) {
      final bytes = await img.readAsBytes();
      setState(() => _imageBytes = bytes);
    }
  }

  Future<void> _publish() async {
    if (_descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, añade una descripción')),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final socialService = SocialService();
      String imageToSend =
          'https://images.unsplash.com/photo-1547592166-23ac45744acd?w=800&q=80';
      if (_imageBytes != null) {
        final b64 = base64Encode(_imageBytes!);
        imageToSend = 'data:image/jpeg;base64,$b64';
      }

      if (_destination == 'Post') {
        await socialService.createPost(_descController.text, imageToSend);
        SocialState().syncPosts();
      } else {
        await socialService.createStory(imageToSend);
        SocialState().syncStories();
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Publicado como $_destination correctamente'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('❌ Error al publicar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Registrar Comida',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Comparte tu progreso nutricional',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sube una foto de tu plato y cuéntanos qué tal ha ido.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.grey.shade200, width: 2),
                ),
                child: _imageBytes == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.add_a_photo_outlined,
                            size: 48,
                            color: Colors.deepOrange,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Añadir foto del plato',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.memory(
                          _imageBytes!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _descController,
              maxLines: 3,
              style: FeedPalette.bodyTextStyle,
              decoration: FeedPalette.textFieldDecoration(
                hint: 'Ej. Deliciosa comida post-workout: Pollo con arroz...',
                radius: 16,
                contentPadding: const EdgeInsets.all(20),
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              '¿Dónde quieres publicar?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildDestOption('Post', Icons.grid_on),
                const SizedBox(width: 16),
                _buildDestOption('Historia', Icons.history),
              ],
            ),
            const SizedBox(height: 48),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPosting ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
                child: _isPosting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        'PUBLICAR AHORA',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDestOption(String label, IconData icon) {
    bool isSelected = _destination == label;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _destination = label),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? Colors.deepOrange.withValues(alpha: 0.1)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? Colors.deepOrange : Colors.grey.shade200,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.deepOrange : Colors.grey),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.deepOrange : Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
