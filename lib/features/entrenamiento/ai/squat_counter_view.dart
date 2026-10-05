import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

class AITrainingView extends StatefulWidget {
  const AITrainingView({super.key});

  @override
  State<AITrainingView> createState() => _AITrainingViewState();
}

class _AITrainingViewState extends State<AITrainingView> {
  CameraController? _cameraController;
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(),
  );
  bool _isBusy = false;

  // Training state
  String _selectedExercise = 'Sentadillas';
  int _reps = 0;
  bool _isGoingDown = false;
  String _feedbackText = 'Ponte en posición';
  Color _feedbackColor = Colors.orange;

  // Debouncing to avoid reading too fast
  DateTime _lastDetectionTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (kIsWeb) return;
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      _cameraController!.startImageStream((CameraImage image) {
        if (_isBusy) return;
        _isBusy = true;
        _processCameraImage(image);
      });

      setState(() {});
    } catch (e) {
      debugPrint('Error initializing camera: $e');
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    // Solo procesar 5 frames por segundo para no saturar
    if (DateTime.now().difference(_lastDetectionTime).inMilliseconds < 200) {
      _isBusy = false;
      return;
    }
    _lastDetectionTime = DateTime.now();

    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final imageRotation = InputImageRotationValue.fromRawValue(
            _cameraController!.description.sensorOrientation,
          ) ??
          InputImageRotation.rotation0deg;

      final inputImageFormat =
          InputImageFormatValue.fromRawValue(image.format.raw) ??
              InputImageFormat.nv21;

      final planeData = image.planes.map((Plane plane) {
        return InputImageMetadata(
          bytesPerRow: plane.bytesPerRow,
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: imageRotation,
          format: inputImageFormat,
        );
      }).toList();

      // En Android, formato nv21 o yuv420
      // Usaremos un enfoque seguro para MLKit
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: planeData.first,
      );

      final poses = await _poseDetector.processImage(inputImage);
      if (poses.isNotEmpty) {
        _analyzePose(poses.first);
      }
    } catch (e) {
      // Ignorar errores de procesamiento
    }

    _isBusy = false;
  }

  void _analyzePose(Pose pose) {
    if (_selectedExercise == 'Sentadillas') {
      _analyzeSquat(pose);
    } else if (_selectedExercise == 'Flexiones') {
      _analyzePushup(pose);
    }
  }

  void _analyzeSquat(Pose pose) {
    final hip = pose.landmarks[PoseLandmarkType.leftHip];
    final knee = pose.landmarks[PoseLandmarkType.leftKnee];
    final ankle = pose.landmarks[PoseLandmarkType.leftAnkle];

    if (hip != null && knee != null && ankle != null) {
      if (hip.likelihood > 0.5 &&
          knee.likelihood > 0.5 &&
          ankle.likelihood > 0.5) {
        final angle = _calculateAngle(
          hip.x,
          hip.y,
          knee.x,
          knee.y,
          ankle.x,
          ankle.y,
        );

        if (angle < 100) {
          if (!_isGoingDown) {
            setState(() {
              _feedbackText = '¡Sube!';
              _feedbackColor = Colors.green;
              _isGoingDown = true;
            });
          }
        } else if (angle > 150) {
          if (_isGoingDown) {
            setState(() {
              _reps++;
              _feedbackText = '¡Perfecto! Baja despacio';
              _feedbackColor = Colors.orange;
              _isGoingDown = false;
            });
          }
        }
      } else {
        setState(() {
          _feedbackText = 'Aléjate para ver todo el cuerpo';
          _feedbackColor = Colors.red;
        });
      }
    }
  }

  void _analyzePushup(Pose pose) {
    final shoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final elbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final wrist = pose.landmarks[PoseLandmarkType.leftWrist];

    if (shoulder != null && elbow != null && wrist != null) {
      if (shoulder.likelihood > 0.5 &&
          elbow.likelihood > 0.5 &&
          wrist.likelihood > 0.5) {
        final angle = _calculateAngle(
          shoulder.x,
          shoulder.y,
          elbow.x,
          elbow.y,
          wrist.x,
          wrist.y,
        );

        if (angle < 90) {
          // Brazo flexionado
          if (!_isGoingDown) {
            setState(() {
              _feedbackText = '¡Sube con fuerza!';
              _feedbackColor = Colors.green;
              _isGoingDown = true;
            });
          }
        } else if (angle > 150) {
          // Brazo estirado
          if (_isGoingDown) {
            setState(() {
              _reps++;
              _feedbackText = '¡Así se hace! Otra vez';
              _feedbackColor = Colors.orange;
              _isGoingDown = false;
            });
          }
        }
      } else {
        setState(() {
          _feedbackText = 'Asegúrate de que se vea tu brazo entero';
          _feedbackColor = Colors.red;
        });
      }
    }
  }

  double _calculateAngle(
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    var angle = math.atan2(y3 - y2, x3 - x2) - math.atan2(y1 - y2, x1 - x2);
    angle = angle * 180 / math.pi;
    if (angle < 0) {
      angle += 360;
    }
    if (angle > 180) {
      angle = 360 - angle;
    }
    return angle;
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _poseDetector.close();
    super.dispose();
  }

  Widget _buildCameraSurface() {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final previewSize = controller.value.previewSize;
    final previewWidth = previewSize?.height ?? 1080;
    final previewHeight = previewSize?.width ?? 1920;

    return ColoredBox(
      color: Colors.black,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.center,
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_off_outlined,
                size: 80,
                color: Colors.deepOrange,
              ),
              const SizedBox(height: 24),
              const Text(
                'IA Visual: Solo en Móvil',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                child: Text(
                  'El reconocimiento de postura por cámara requiere acceso a hardware nativo. ¡Prueba el APK en Android para ver esta función en acción!',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text('Entendido'),
              ),
            ],
          ),
        ),
      );
    }

    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: DropdownButton<String>(
          value: _selectedExercise,
          dropdownColor: Colors.black87,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
          underline: const SizedBox(),
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.deepOrange),
          items: ['Sentadillas', 'Flexiones']
              .map(
                (e) =>
                    DropdownMenuItem(value: e, child: Text(' Contador: $e ')),
              )
              .toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedExercise = val;
                _reps = 0;
                _isGoingDown = false;
              });
            }
          },
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraSurface(),

          // Overlay de información
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 20),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '$_reps',
                    style: const TextStyle(
                      fontSize: 72,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black.withAlpha(0), Colors.black87],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _feedbackColor.withAlpha(230),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _feedbackText,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          // Mostrar resumen y ganar FitCoins
                          _finishWorkout();
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Completar Rutina'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
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

  void _finishWorkout() {
    Navigator.pop(context, {'reps': _reps, 'exercise': _selectedExercise});
  }
}
