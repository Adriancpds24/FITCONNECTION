import 'dart:async';
import 'package:flutter/material.dart';
import '../social/post_model.dart' show Highlight;
import '../social/social_state.dart';
import '../../core/constants/api_constants.dart';

class HighlightViewer extends StatefulWidget {
  final List<Highlight> highlights;
  final int initialHighlightIndex;
  final bool isOwnProfile;

  const HighlightViewer({
    super.key,
    required this.highlights,
    required this.initialHighlightIndex,
    this.isOwnProfile = false,
  });

  @override
  State<HighlightViewer> createState() => _HighlightViewerState();
}

class _HighlightViewerState extends State<HighlightViewer> {
  late PageController _pageController;
  late int _currentHighlightIndex;
  int _currentIndex = 0;
  double _progress = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _currentHighlightIndex = widget.initialHighlightIndex;
    _pageController = PageController();
    _startProgress();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startProgress() {
    _timer?.cancel();
    _progress = 0.0;
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _progress += 0.01;
        if (_progress >= 1.0) {
          _progress = 1.0;
          timer.cancel();
          _nextHighlight();
        }
      });
    });
  }

  void _nextHighlight() {
    final currentHighlight = widget.highlights[_currentHighlightIndex];
    if (_currentIndex < currentHighlight.storyImages.length - 1) {
      setState(() {
        _currentIndex++;
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _startProgress();
      });
    } else {
      // Move to next highlight bundle
      if (_currentHighlightIndex < widget.highlights.length - 1) {
        setState(() {
          _currentHighlightIndex++;
          _currentIndex = 0;
          _pageController.jumpToPage(0);
          _startProgress();
        });
      } else {
        Navigator.pop(context);
      }
    }
  }

  void _previousHighlight() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _pageController.animateToPage(
          _currentIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        _startProgress();
      });
    } else {
      // Move to previous highlight bundle
      if (_currentHighlightIndex > 0) {
        setState(() {
          _currentHighlightIndex--;
          final prevHighlight = widget.highlights[_currentHighlightIndex];
          _currentIndex = prevHighlight.storyImages.length - 1;
          _pageController.jumpToPage(_currentIndex);
          _startProgress();
        });
      } else {
        _startProgress(); // Reset progress if at very first
      }
    }
  }

  void _deleteHighlight() {
    _timer?.cancel();
    final currentHighlight = widget.highlights[_currentHighlightIndex];
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar historia destacada'),
        content: const Text(
          '¿Estás seguro de que quieres eliminar esta historia destacada?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _startProgress(); // resume
            },
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              // Optimistically update or wait
              await SocialState().deleteHighlight(currentHighlight);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Historia destacada eliminada')),
              );
              Navigator.pop(context, true); // Return true to indicate deletion
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _resolveUrl(String url) {
    if (url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) return url;

    // Si es una ruta relativa de la API
    final apiOrigin = ApiConstants.apiHost.replaceFirst(RegExp(r'/api$'), '');
    return '$apiOrigin$url';
  }

  @override
  Widget build(BuildContext context) {
    final currentHighlight = widget.highlights[_currentHighlightIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previousHighlight();
          } else {
            _nextHighlight();
          }
        },
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: currentHighlight.storyImages.length,
              itemBuilder: (context, index) {
                return Center(
                  child: Image.network(
                    _resolveUrl(currentHighlight.storyImages[index]),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.broken_image, color: Colors.white, size: 50),
                        SizedBox(height: 10),
                        Text(
                          'No se pudo cargar la imagen',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: List.generate(
                        currentHighlight.storyImages.length,
                        (index) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: LinearProgressIndicator(
                              value: index == _currentIndex
                                  ? _progress
                                  : (index < _currentIndex ? 1.0 : 0.0),
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 15,
                          backgroundColor: Colors.white24,
                          child: Icon(
                            Icons.person,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          currentHighlight.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (widget.isOwnProfile ||
                            SocialState().currentUser.username == 'admin')
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.white),
                            onPressed: _deleteHighlight,
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
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
