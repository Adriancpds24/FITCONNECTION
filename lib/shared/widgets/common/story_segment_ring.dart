import 'dart:math' as math;

import 'package:flutter/material.dart';

class StorySegmentRing extends StatelessWidget {
  final int segmentCount;
  final double size;
  final double strokeWidth;
  final bool viewed;
  final Widget child;

  const StorySegmentRing({
    super.key,
    required this.segmentCount,
    required this.size,
    required this.child,
    this.strokeWidth = 3,
    this.viewed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (segmentCount < 1) {
      return SizedBox(width: size, height: size, child: Center(child: child));
    }

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _StorySegmentRingPainter(
          segmentCount: segmentCount,
          strokeWidth: strokeWidth,
          viewed: viewed,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _StorySegmentRingPainter extends CustomPainter {
  final int segmentCount;
  final double strokeWidth;
  final bool viewed;

  const _StorySegmentRingPainter({
    required this.segmentCount,
    required this.strokeWidth,
    required this.viewed,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = viewed
          ? const Color(0xFFD4CCC3)
          : const Color(0xFFF38A5A).withValues(alpha: 0.25)
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, background);

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = viewed ? const Color(0xFFBEB3A8) : const Color(0xFFFF6A2A)
      ..strokeCap = StrokeCap.round;

    final count = segmentCount.clamp(1, 24);
    final segmentSweep = (2 * math.pi) / count;
    final gap = math.min(0.20, segmentSweep * 0.18);
    final visibleSweep = (segmentSweep - gap).clamp(0.04, 2 * math.pi);
    final startBase = -math.pi / 2;

    for (var i = 0; i < count; i++) {
      final start = startBase + i * segmentSweep + gap / 2;
      canvas.drawArc(rect, start, visibleSweep, false, active);
    }
  }

  @override
  bool shouldRepaint(covariant _StorySegmentRingPainter oldDelegate) {
    return oldDelegate.segmentCount != segmentCount ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.viewed != viewed;
  }
}
