import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../features/social/social_service.dart';
import '../../features/social/social_state.dart';
import '../../features/social/story_service.dart';

class CameraModule extends StatefulWidget {
  final VoidCallback onCancel;

  const CameraModule({super.key, required this.onCancel});

  @override
  State<CameraModule> createState() => _CameraModuleState();
}

class _CameraModuleState extends State<CameraModule> {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isSwitchingCamera = false;
  bool _isRecording = false;
  XFile? _capturedFile;
  VideoPlayerController? _videoController;
  final TextEditingController _textController = TextEditingController();
  final GlobalKey _composedPreviewKey = GlobalKey();
  bool _isUploading = false;
  int _selectedFilterIndex = 0;
  bool _isFilterSelectorVisible = false;
  bool _isEditingText = false;
  bool _includeTextInCapture = true;
  final FocusNode _textFocusNode = FocusNode();

  // Text sticker transform (drag / scale / rotate)
  Offset _textOffset = Offset.zero;
  double _textScale = 1.0;
  double _textRotation = 0.0;
  Offset? _textStartFocal;
  Offset? _textStartOffset;
  double? _textStartScale;
  double? _textStartRotation;

  static const List<_StoryFilter> _filters = [
    _StoryFilter(name: 'Normal'),
    _StoryFilter(
      name: 'Noir',
      matrix: [
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    ),
    _StoryFilter(
      name: 'Vintage',
      matrix: [
        0.393,
        0.769,
        0.189,
        0,
        0,
        0.349,
        0.686,
        0.168,
        0,
        0,
        0.272,
        0.534,
        0.131,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
    ),
    _StoryFilter(
      name: 'Frio',
      overlayColor: Color(0xFF5BA6FF),
      overlayOpacity: 0.16,
      blendMode: BlendMode.screen,
    ),
    _StoryFilter(
      name: 'Calido',
      overlayColor: Color(0xFFFF8A3D),
      overlayOpacity: 0.20,
      blendMode: BlendMode.softLight,
    ),
    _StoryFilter(
      name: 'Dream',
      overlayColor: Color(0xFFFFC6E8),
      overlayOpacity: 0.18,
      blendMode: BlendMode.screen,
    ),
    _StoryFilter(
      name: 'Bosque',
      overlayColor: Color(0xFF2E8B57),
      overlayOpacity: 0.18,
      blendMode: BlendMode.overlay,
    ),
  ];

  bool get _hasFilterSelected => _selectedFilterIndex != 0;

  bool get _isCapturedVideo =>
      _capturedFile != null && _isVideoFile(_capturedFile!);

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  ImageFormatGroup? _preferredImageFormatGroup() {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return ImageFormatGroup.bgra8888;
      case TargetPlatform.android:
        return ImageFormatGroup.yuv420;
      default:
        return null;
    }
  }

  CameraController _createCameraController(
    CameraDescription description, {
    ResolutionPreset preset = ResolutionPreset.high,
  }) {
    return CameraController(
      description,
      preset,
      enableAudio: true,
      imageFormatGroup: _preferredImageFormatGroup(),
    );
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      await _setCamera(backCamera);
    } catch (e) {
      debugPrint('Error init camera: $e');
    }
  }

  Future<void> _initializeCameraController(CameraController controller) async {
    await controller.initialize();
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
  }

  Future<void> _setCamera(CameraDescription description) async {
    if (_isSwitchingCamera) return;
    _isSwitchingCamera = true;

    final previousController = _controller;
    if (mounted) {
      setState(() => _controller = null);
    }
    await previousController?.dispose();

    CameraController? nextController;
    try {
      nextController = _createCameraController(description);
      try {
        await _initializeCameraController(nextController);
      } catch (e) {
        debugPrint('Camera high preset failed, retrying medium: $e');
        await nextController.dispose();
        nextController = _createCameraController(
          description,
          preset: ResolutionPreset.medium,
        );
        await _initializeCameraController(nextController);
      }

      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _controller = nextController;
        _isSwitchingCamera = false;
      });
    } catch (e) {
      debugPrint('Error switching camera: $e');
      await nextController?.dispose();
      if (!mounted) return;

      final isFront = description.lensDirection == CameraLensDirection.front;
      if (isFront) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo activar la camara frontal. Prueba de nuevo.',
            ),
          ),
        );
      }

      if (_cameras.isNotEmpty) {
        final fallback = _cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras.first,
        );
        if (fallback.name != description.name) {
          _isSwitchingCamera = false;
          await _setCamera(fallback);
          return;
        }
      }

      if (mounted) {
        setState(() => _isSwitchingCamera = false);
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_isSwitchingCamera || _isRecording || _cameras.length <= 1) return;

    final current = _controller?.description;
    final wantsFront = current?.lensDirection != CameraLensDirection.front;

    final target = _cameras.firstWhere(
      (camera) =>
          camera.lensDirection ==
          (wantsFront ? CameraLensDirection.front : CameraLensDirection.back),
      orElse: () => _cameras.first,
    );

    if (current?.name == target.name) return;
    await _setCamera(target);
  }

  bool get _isFrontCamera =>
      _controller?.description.lensDirection == CameraLensDirection.front;

  bool _isVideoFile(XFile file) {
    final ext = file.name.split('.').last.toLowerCase();
    return ext == 'mp4' || ext == 'mov' || ext == 'avi' || ext == 'm4v';
  }

  @override
  void dispose() {
    _controller?.dispose();
    _videoController?.dispose();
    _textController.dispose();
    _textFocusNode.dispose();
    super.dispose();
  }

  /// La vista previa frontal suele verse en espejo, pero el archivo crudo no.
  /// Lo volteamos para que la foto guardada coincida con lo que ves al disparar.
  Future<Uint8List> _mirrorImageBytesHorizontally(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(image.width.toDouble(), 0);
    canvas.scale(-1, 1);
    canvas.drawImage(image, Offset.zero, Paint());
    final picture = recorder.endRecording();
    final flipped = await picture.toImage(image.width, image.height);
    image.dispose();

    final byteData = await flipped.toByteData(format: ui.ImageByteFormat.png);
    flipped.dispose();
    if (byteData == null) {
      throw Exception('No se pudo reflejar la imagen.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<XFile> _normalizeCapturedPhoto(XFile file) async {
    if (kIsWeb || !_isFrontCamera) return file;

    try {
      final mirrored = await _mirrorImageBytesHorizontally(
        await file.readAsBytes(),
      );
      await File(file.path).writeAsBytes(mirrored, flush: true);
    } catch (e) {
      debugPrint('CameraModule mirror front photo: $e');
    }
    return file;
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final file = await _normalizeCapturedPhoto(
        await _controller!.takePicture(),
      );
      setState(() {
        _capturedFile = file;
      });
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  Future<void> _toggleRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_isRecording) {
        final file = await _controller!.stopVideoRecording();
        setState(() {
          _isRecording = false;
          _capturedFile = file;
        });
        await _initVideoPlayer(file);
      } else {
        await _controller!.startVideoRecording();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      debugPrint('Error toggling recording: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();
    final file = await picker.pickMedia();
    if (file == null) return;

    setState(() => _capturedFile = file);
    if (_isVideoFile(file)) {
      await _initVideoPlayer(file);
    }
  }

  Future<void> _initVideoPlayer(XFile file) async {
    await _videoController?.dispose();

    if (kIsWeb) {
      _videoController = VideoPlayerController.networkUrl(Uri.parse(file.path));
    } else {
      _videoController = VideoPlayerController.file(File(file.path));
    }

    await _videoController?.initialize();
    await _videoController?.setLooping(true);
    await _videoController?.play();

    if (mounted) setState(() {});
  }

  Future<void> _resetCapturedState() async {
    await _videoController?.dispose();
    _videoController = null;

    if (!mounted) return;
    setState(() {
      _capturedFile = null;
      _selectedFilterIndex = 0;
      _isFilterSelectorVisible = false;
      _textController.clear();
      _textOffset = Offset.zero;
      _textScale = 1.0;
      _textRotation = 0.0;
      _isEditingText = false;
    });
  }

  _FilteredCaptureConfig _resolveFilteredCaptureConfig() {
    final renderContext = _composedPreviewKey.currentContext;
    if (renderContext == null) {
      throw Exception('No se pudo preparar la imagen filtrada.');
    }

    final boundary = renderContext.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      throw Exception('No se pudo capturar la previsualizacion.');
    }

    final view = View.maybeOf(renderContext);
    final pixelRatio = (view?.devicePixelRatio ??
            WidgetsBinding
                .instance.platformDispatcher.views.first.devicePixelRatio)
        .clamp(1.0, 3.0);

    return _FilteredCaptureConfig(boundary: boundary, pixelRatio: pixelRatio);
  }

  Future<void> _prepareStoryCapture() async {
    if (_isEditingText) {
      _closeTextEditor(keepText: true);
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 40));
  }

  Future<Uint8List> _captureFilteredImageBytes() async {
    await _prepareStoryCapture();
    if (!mounted) {
      throw Exception('La camara ya no esta disponible.');
    }

    final captureConfig = _resolveFilteredCaptureConfig();

    final image = await captureConfig.boundary.toImage(
      pixelRatio: captureConfig.pixelRatio,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw Exception('No se pudo convertir la imagen filtrada.');
    }

    return byteData.buffer.asUint8List();
  }

  Future<Uint8List> _buildImageBytesForUpload({required bool burnText}) async {
    if (_capturedFile == null) {
      throw Exception('No hay imagen seleccionada.');
    }

    final hasText = _textController.text.trim().isNotEmpty;
    final needsComposition = _hasFilterSelected || (burnText && hasText);

    // Sin composición: subimos la foto original (el texto del post va aparte).
    if (!needsComposition) {
      return _capturedFile!.readAsBytes();
    }

    if (mounted) {
      setState(() => _includeTextInCapture = burnText && hasText);
    }
    await WidgetsBinding.instance.endOfFrame;

    // Historias: imagen + filtro + texto. Posts: solo imagen + filtro.
    try {
      return await _captureFilteredImageBytes();
    } catch (e) {
      if (kIsWeb) {
        debugPrint(
          'CameraModule -> Fallo la captura en web, se sube la imagen original: $e',
        );
        return _capturedFile!.readAsBytes();
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => _includeTextInCapture = true);
      }
    }
  }

  Future<void> _uploadContent(bool toStory) async {
    if (_capturedFile == null || _isUploading) return;
    setState(() => _isUploading = true);

    try {
      if (_isCapturedVideo) {
        if (_hasFilterSelected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Los filtros de historias se aplican solo a fotos por ahora.',
              ),
            ),
          );
        }

        final bytes = await _capturedFile!.readAsBytes();
        final base64String = 'data:video/mp4;base64,${base64Encode(bytes)}';

        if (toStory) {
          await StoryService().createStoryFromImage(_capturedFile!);
        } else {
          await SocialService().createPost(_textController.text, base64String);
          await SocialState().syncPosts();
        }
      } else {
        final processedBytes =
            await _buildImageBytesForUpload(burnText: toStory);
        final imageData =
            'data:image/png;base64,${base64Encode(processedBytes)}';

        if (toStory) {
          await StoryService().createStoryFromBytes(
            processedBytes,
            fileName: _capturedFile!.name,
            mimeType: 'image/png',
          );
        } else {
          await SocialService().createPost(_textController.text, imageData);
          await SocialState().syncPosts();
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Publicado con exito como ${toStory ? "Historia" : "Post"}',
          ),
        ),
      );
      await _resetCapturedState();
      widget.onCancel();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al publicar: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Widget _applySelectedFilter(Widget child) {
    final filter = _filters[_selectedFilterIndex];
    Widget filteredChild = child;

    if (filter.matrix != null) {
      filteredChild = ColorFiltered(
        colorFilter: ColorFilter.matrix(filter.matrix!),
        child: filteredChild,
      );
    }

    if (filter.overlayColor != null && filter.overlayOpacity > 0) {
      filteredChild = ColorFiltered(
        colorFilter: ColorFilter.mode(
          filter.overlayColor!.withValues(alpha: filter.overlayOpacity),
          filter.blendMode,
        ),
        child: filteredChild,
      );
    }

    return filteredChild;
  }

  Widget _buildFilterSelector() {
    // Side panel (collapsed/expanded)
    return Positioned(
      top: 120,
      bottom: 120,
      right: 12,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: ListView.separated(
          itemCount: _filters.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final filter = _filters[index];
            final isSelected = index == _selectedFilterIndex;

            return GestureDetector(
              onTap: () => setState(() => _selectedFilterIndex = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.deepOrange.withValues(alpha: 0.30)
                      : Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? Colors.deepOrange : Colors.white24,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.12),
                        border: Border.all(color: Colors.white24),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        filter.name.substring(0, 1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        filter.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterButton() {
    final activeFilter = _filters[_selectedFilterIndex];
    final hasActiveFilter = _hasFilterSelected;
    final isActive = _isFilterSelectorVisible || hasActiveFilter;

    return GestureDetector(
      onTap: _isRecording
          ? null
          : () => setState(
                () => _isFilterSelectorVisible = !_isFilterSelectorVisible,
              ),
      child: Opacity(
        opacity: _isRecording ? 0.5 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isActive
                    ? Colors.deepOrange.withValues(alpha: 0.28)
                    : Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? Colors.deepOrange : Colors.white30,
                  width: isActive ? 2.5 : 1.4,
                ),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasActiveFilter ? activeFilter.name : 'Filtros',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewMedia() {
    if (_capturedFile == null) {
      return const SizedBox.shrink();
    }

    if (_isCapturedVideo) {
      if (_videoController != null && _videoController!.value.isInitialized) {
        return VideoPlayer(_videoController!);
      }

      return const Center(child: CircularProgressIndicator());
    }

    final imageWidget = kIsWeb
        ? Image.network(_capturedFile!.path, fit: BoxFit.cover)
        : Image.file(File(_capturedFile!.path), fit: BoxFit.cover);

    return RepaintBoundary(
      key: _composedPreviewKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _applySelectedFilter(imageWidget),
          if (_includeTextInCapture) _buildTextStickerOverlay(),
        ],
      ),
    );
  }

  void _openTextEditor() {
    if (!mounted) return;
    setState(() => _isEditingText = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _textFocusNode.requestFocus();
    });
  }

  void _closeTextEditor({bool keepText = true}) {
    if (!mounted) return;
    if (!keepText) {
      _textController.clear();
      _textOffset = Offset.zero;
      _textScale = 1.0;
      _textRotation = 0.0;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _isEditingText = false);
  }

  Widget _buildCenteredTextEditor() {
    if (!_isEditingText || _isCapturedVideo) return const SizedBox.shrink();

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _closeTextEditor(keepText: true),
        child: Container(
          color: Colors.black.withValues(alpha: 0.35),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      focusNode: _textFocusNode,
                      controller: _textController,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Añadir texto…',
                        hintStyle: TextStyle(color: Colors.white54),
                        border: InputBorder.none,
                      ),
                      maxLines: 4,
                      minLines: 1,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _closeTextEditor(keepText: false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white30),
                            ),
                            child: const Text('Cancelar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _closeTextEditor(keepText: true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                            ),
                            child: const Text('Listo'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextStickerOverlay() {
    final text = _textController.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();

    final sticker = Center(
      child: Transform.translate(
        offset: _textOffset,
        child: Transform.rotate(
          angle: _textRotation,
          child: Transform.scale(
            scale: _textScale,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      blurRadius: 10.0,
                      color: Colors.black,
                      offset: Offset(2, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _openTextEditor,
        onScaleStart: (details) {
          _textStartFocal = details.localFocalPoint;
          _textStartOffset = _textOffset;
          _textStartScale = _textScale;
          _textStartRotation = _textRotation;
        },
        onScaleUpdate: (details) {
          if (_isEditingText) return;
          final startFocal = _textStartFocal;
          final startOffset = _textStartOffset;
          final startScale = _textStartScale;
          final startRotation = _textStartRotation;
          if (startFocal == null ||
              startOffset == null ||
              startScale == null ||
              startRotation == null) {
            return;
          }

          final delta = details.localFocalPoint - startFocal;
          final nextOffset = startOffset + delta;
          final nextScale = (startScale * details.scale).clamp(0.5, 4.0);
          final nextRotation = startRotation + details.rotation;

          setState(() {
            _textOffset = nextOffset;
            _textScale = nextScale;
            _textRotation = nextRotation;
          });
        },
        child: sticker,
      ),
    );
  }

  Widget _buildFilterSideButton() {
    return Positioned(
      right: 16,
      top: 60,
      child: IconButton(
        onPressed: _isRecording
            ? null
            : () => setState(
                  () => _isFilterSelectorVisible = !_isFilterSelectorVisible,
                ),
        icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.35),
          padding: const EdgeInsets.all(12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.white24),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_controller == null ||
        !_controller!.value.isInitialized ||
        _isSwitchingCamera) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final controller = _controller!;
    final previewSize = controller.value.previewSize;
    if (previewSize == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    final preview = CameraPreview(controller);

    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: Alignment.center,
        child: SizedBox(
          width: previewSize.height,
          height: previewSize.width,
          child: preview,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_capturedFile != null) return _buildPreview();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraPreview(),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              onPressed: widget.onCancel,
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
            ),
          ),
          Positioned(
            top: 96,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Toca para foto, manten pulsado para video',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: _pickFromGallery,
                  icon: const Icon(
                    Icons.photo_library,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                _buildFilterButton(),
                GestureDetector(
                  onTap: _takePhoto,
                  onLongPress: _toggleRecording,
                  onLongPressUp: _toggleRecording,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 4),
                      color: _isRecording
                          ? Colors.red.withValues(alpha: 0.5)
                          : Colors.transparent,
                    ),
                  ),
                ),
                IconButton(
                  onPressed:
                      _isSwitchingCamera || _isRecording ? null : _flipCamera,
                  icon: Icon(
                    _isFrontCamera
                        ? Icons.camera_rear_outlined
                        : Icons.camera_front_outlined,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          if (_isFilterSelectorVisible) _buildFilterSelector(),
          if (_isRecording)
            const Positioned(
              top: 140,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'GRABANDO...',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openTextEditor,
            child: _buildPreviewMedia(),
          ),
          if (!_isCapturedVideo) _buildCenteredTextEditor(),
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              onPressed: _resetCapturedState,
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 30),
            ),
          ),
          if (!_isCapturedVideo) _buildFilterSideButton(),
          if (!_isCapturedVideo && _isFilterSelectorVisible)
            _buildFilterSelector(),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _uploadContent(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white24,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Historia'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _uploadContent(false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Post'),
                  ),
                ),
              ],
            ),
          ),
          if (_isUploading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _StoryFilter {
  final String name;
  final List<double>? matrix;
  final Color? overlayColor;
  final double overlayOpacity;
  final BlendMode blendMode;

  const _StoryFilter({
    required this.name,
    this.matrix,
    this.overlayColor,
    this.overlayOpacity = 0,
    this.blendMode = BlendMode.srcATop,
  });
}

class _FilteredCaptureConfig {
  final RenderRepaintBoundary boundary;
  final double pixelRatio;

  const _FilteredCaptureConfig({
    required this.boundary,
    required this.pixelRatio,
  });
}
