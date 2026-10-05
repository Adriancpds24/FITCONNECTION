import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rms/core/utils/media_permissions.dart';
import '../../shared/themes/feed_palette.dart';
import '../../shared/widgets/common/smart_image.dart';
import '../social/social_state.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final SocialState _socialState = SocialState();
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  late TextEditingController _imageController;
  String _selectedSport = '';
  bool _isPrivate = false;
  bool _isSaving = false;
  bool _hasPendingPhoto = false;
  final ImagePicker _picker = ImagePicker();

  String get _avatarUrl {
    final pending = _imageController.text.trim();
    if (pending.isNotEmpty) return pending;
    return _socialState.currentUser.userImage;
  }

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: _socialState.currentUser.displayName,
    );
    _usernameController = TextEditingController(
      text: _socialState.currentUser.username,
    );
    _bioController = TextEditingController(text: _socialState.currentUser.bio);
    _imageController = TextEditingController(
      text: _socialState.currentUser.userImage,
    );
    _selectedSport = _socialState.currentUser.sport;
    _isPrivate = _socialState.currentUser.isPrivate;
    if (![
      'Gimnasio',
      'Running',
      'Ciclismo',
      'Natación',
      'Yoga',
      'Fitness',
      'Global',
    ].contains(_selectedSport)) {
      _selectedSport = 'Global';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    setState(() => _isSaving = true);
    try {
      await _socialState.updateProfile(
        displayName: _nameController.text,
        username: _usernameController.text,
        bio: _bioController.text,
        imagePath: _imageController.text,
        sports: [_selectedSport],
        isPrivate: _isPrivate,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Perfil actualizado con éxito!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al guardar cambios: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FeedPalette.background,
      appBar: AppBar(
        backgroundColor: FeedPalette.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: FeedPalette.text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Editar perfil',
          style: TextStyle(
            color: FeedPalette.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_isSaving)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: FeedPalette.accent,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(Icons.check, color: FeedPalette.accent),
              onPressed: _saveProfile,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: FeedPalette.surfaceSoft,
                      child: ClipOval(
                        child: SizedBox(
                          width: 96,
                          height: 96,
                          child: SmartImage(
                            imageUrl: _avatarUrl,
                            fit: BoxFit.cover,
                            placeholder: Icon(
                              Icons.person,
                              size: 48,
                              color: FeedPalette.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_hasPendingPhoto)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: FeedPalette.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Vista previa',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _showImageOptions,
                  child: Text(
                    'Cambiar foto de perfil',
                    style: TextStyle(
                      color: FeedPalette.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildField('Nombre', _nameController),
          const SizedBox(height: 20),
          _buildField('Usuario', _usernameController),
          const SizedBox(height: 20),
          _buildField('Biografía', _bioController, maxLines: 3),
          const SizedBox(height: 20),
          Text(
            'Deporte Principal',
            style: TextStyle(color: FeedPalette.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FeedPalette.inputFill,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: FeedPalette.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedSport,
                isExpanded: true,
                dropdownColor: FeedPalette.surface,
                style: TextStyle(color: FeedPalette.text),
                items: [
                  'Gimnasio',
                  'Running',
                  'Ciclismo',
                  'Natación',
                  'Yoga',
                  'Fitness',
                  'Global',
                ]
                    .map(
                      (s) => DropdownMenuItem(
                        value: s,
                        child:
                            Text(s, style: TextStyle(color: FeedPalette.text)),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedSport = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 32),
          Divider(color: FeedPalette.border),
          const SizedBox(height: 16),
          SwitchListTile(
            activeThumbColor: FeedPalette.accent,
            activeTrackColor: FeedPalette.accent.withValues(alpha: 0.5),
            title: Text(
              'Cuenta privada',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: FeedPalette.text,
              ),
            ),
            subtitle: Text(
              'Solo las personas que apruebes podrán ver tus fotos y vídeos.',
              style: TextStyle(fontSize: 12, color: FeedPalette.muted),
            ),
            value: _isPrivate,
            onChanged: (val) {
              setState(() => _isPrivate = val);
            },
            secondary: Icon(
              _isPrivate ? Icons.lock : Icons.lock_open,
              color: _isPrivate ? FeedPalette.accent : FeedPalette.muted,
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: FeedPalette.muted, fontSize: 13)),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: FeedPalette.text),
          decoration: FeedPalette.textFieldDecoration(
            hint: label,
          ).copyWith(
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FeedPalette.border),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FeedPalette.accent, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final permission = await requestMediaPermission(source);
    if (permission != MediaPermissionStatus.granted) {
      if (mounted) {
        showMediaPermissionSnackBar(context, source, permission);
      }
      return;
    }

    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        setState(() {
          _imageController.text = base64String;
          _hasPendingPhoto = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al capturar imagen: $e')));
      }
    }
  }

  void _showImageOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: FeedPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: FeedPalette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.photo_library, color: FeedPalette.accent),
              title: Text(
                'Elegir de la galería',
                style: TextStyle(color: FeedPalette.text),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: Icon(Icons.camera_alt, color: FeedPalette.accent),
              title: Text(
                'Hacer una foto',
                style: TextStyle(color: FeedPalette.text),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
