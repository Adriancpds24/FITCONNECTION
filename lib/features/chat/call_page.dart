import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../social/post_model.dart';
import '../../shared/widgets/common/smart_image.dart';
import 'chat_platform_tools.dart'
    if (dart.library.js_interop) 'chat_platform_tools_web.dart';

class CallPage extends StatefulWidget {
  final UserProfile user;
  final bool isIncoming;

  const CallPage({super.key, required this.user, this.isIncoming = false});

  @override
  State<CallPage> createState() => _CallPageState();
}

class _CallPageState extends State<CallPage>
    with SingleTickerProviderStateMixin {
  bool _isAccepted = false;
  bool _isMuted = false;
  bool _isSpeaker = false;
  bool _isVideoOff = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  CameraController? _cameraController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _playRinging();

    if (!widget.isIncoming) {
      // Si somos los que llamamos, simulamos que contestan a los 4 segundos
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted && !_isAccepted) _acceptCall();
      });
    }

    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isNotEmpty) {
        final frontCamera = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
          orElse: () => cameras.first,
        );
        _cameraController = CameraController(
          frontCamera,
          ResolutionPreset.low,
          enableAudio: true,
        );
        await _cameraController!.initialize();
        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Error initializing camera: $e");
    }
  }

  Future<void> _playRinging() async {
    try {
      playRingAudio();
    } catch (_) {}
  }

  Future<void> _playHangup() async {
    try {
      stopRingAudio();
      playHangupAudio();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      stopRingAudio();
    } catch (_) {}
    _cameraController?.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _acceptCall() {
    try {
      stopRingAudio();
    } catch (_) {}
    setState(() => _isAccepted = true);
  }

  Future<void> _endCall() async {
    await _playHangup();
    if (mounted) {
      setState(() {});
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        _cameraController?.dispose();
        Navigator.of(context).pop();
      }
    }
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _showToast(_isMuted ? "Micrófono silenciado" : "Micrófono activado");
  }

  void _toggleSpeaker() {
    setState(() => _isSpeaker = !_isSpeaker);
    _showToast(_isSpeaker ? "Altavoz activado" : "Altavoz desactivado");
  }

  void _toggleVideo() {
    setState(() => _isVideoOff = !_isVideoOff);
    _showToast(_isVideoOff ? "Cámara desactivada" : "Cámara activada");
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.only(bottom: 120, left: 40, right: 40),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Fondo - Desenfoque Premium (Glassmorphism)
          SmartImage(
            imageUrl: widget.user.userImage,
            fit: BoxFit.cover,
            errorWidget: Container(color: Colors.grey.shade900),
          ),

          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0),
            child: Container(color: Colors.black.withAlpha(120)),
          ),

          // Interfaz Principal
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Controles Superiores
                if (_isAccepted)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                            size: 36,
                          ),
                          onPressed: _endCall,
                        ),
                        const Icon(
                          Icons.person_add_alt_1,
                          color: Colors.white,
                          size: 28,
                        ),
                      ],
                    ),
                  ),

                // Avatar central pulsante (Llamando/Entrante)
                if (!_isAccepted) ...[
                  const Spacer(),
                  ScaleTransition(
                    scale: _pulseAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withAlpha(50),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 65,
                        backgroundImage: NetworkImage(widget.user.userImage),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    widget.user.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isIncoming
                        ? "Llamada de vídeo entrante..."
                        : "Llamando...",
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 18,
                    ),
                  ),
                  const Spacer(),
                ],

                // Vista de tu propia cámara (Simulada cuando aceptan)
                if (_isAccepted)
                  Expanded(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Container(
                          width: 110,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade900,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withAlpha(80),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(50),
                                blurRadius: 10,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: _isVideoOff
                                ? const Center(
                                    child: Icon(
                                      Icons.videocam_off,
                                      color: Colors.white54,
                                      size: 40,
                                    ),
                                  )
                                : _cameraController != null &&
                                        _cameraController!.value.isInitialized
                                    ? Transform.scale(
                                        scaleX: -1, // Espejo cámara frontal
                                        alignment: Alignment.center,
                                        child: SizedBox(
                                          width: 110,
                                          height: 160,
                                          child: FittedBox(
                                            fit: BoxFit.cover,
                                            alignment: Alignment.center,
                                            child: SizedBox(
                                              width: _cameraController!.value
                                                      .previewSize?.height ??
                                                  110,
                                              height: _cameraController!.value
                                                      .previewSize?.width ??
                                                  160,
                                              child: CameraPreview(
                                                _cameraController!,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : const Center(
                                        child: CircularProgressIndicator(
                                          color: Colors.white24,
                                        ),
                                      ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // Controles Inferiores (Glassmorphism Container)
                if (widget.isIncoming && !_isAccepted)
                  // Controles de llamada entrante
                  Padding(
                    padding: const EdgeInsets.only(bottom: 60),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallButton(
                          icon: Icons.call_end,
                          color: Colors.redAccent,
                          onTap: _endCall,
                          label: "Rechazar",
                        ),
                        _CallButton(
                          icon: Icons.videocam,
                          color: Colors.greenAccent.shade700,
                          onTap: _acceptCall,
                          label: "Aceptar",
                        ),
                      ],
                    ),
                  )
                else
                  // Controles de llamada activa / saliente
                  Container(
                    margin: const EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: 40,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(20),
                      borderRadius: BorderRadius.circular(40),
                      border: Border.all(color: Colors.white.withAlpha(40)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _CallControlButton(
                          icon:
                              _isVideoOff ? Icons.videocam_off : Icons.videocam,
                          isActive: !_isVideoOff,
                          onTap: _toggleVideo,
                        ),
                        _CallControlButton(
                          icon: _isMuted ? Icons.mic_off : Icons.mic,
                          isActive: !_isMuted,
                          onTap: _toggleMute,
                        ),
                        _CallControlButton(
                          icon:
                              _isSpeaker ? Icons.volume_up : Icons.volume_down,
                          isActive: _isSpeaker,
                          onTap: _toggleSpeaker,
                        ),
                        GestureDetector(
                          onTap: _endCall,
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.call_end,
                              color: Colors.white,
                              size: 30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String label;

  const _CallButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withAlpha(100),
                  blurRadius: 25,
                  spreadRadius: 8,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _CallControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _CallControlButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.white.withAlpha(60)
              : Colors.white.withAlpha(20),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white70,
          size: 30,
        ),
      ),
    );
  }
}
