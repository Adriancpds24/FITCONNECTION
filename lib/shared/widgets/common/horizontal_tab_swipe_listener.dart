import 'package:flutter/material.dart';

/// Distancia mínima horizontal (px) para considerar un deslizamiento válido.
const double kHorizontalTabSwipeDistanceThreshold = 110;

/// Duración mínima del gesto para evitar toques accidentales.
const Duration kHorizontalTabSwipeMinDuration = Duration(milliseconds: 220);

/// Relación mínima horizontal/vertical: el movimiento debe ser claramente horizontal.
const double kHorizontalTabSwipeDominanceRatio = 1.45;

/// Detecta deslizamientos horizontales para cambiar pestañas principales
/// (o sub-pestañas si se pasa [innerTabController]).
class HorizontalTabSwipeListener extends StatefulWidget {
  final Widget child;
  final ValueChanged<int>? onMainTabSwipe;

  /// Si se indica, un deslizamiento en el borde interior cambia sub-pestaña
  /// antes de saltar a la pestaña principal siguiente/anterior.
  final TabController? innerTabController;

  const HorizontalTabSwipeListener({
    super.key,
    required this.child,
    this.onMainTabSwipe,
    this.innerTabController,
  });

  @override
  State<HorizontalTabSwipeListener> createState() =>
      _HorizontalTabSwipeListenerState();
}

class _HorizontalTabSwipeListenerState
    extends State<HorizontalTabSwipeListener> {
  double _totalDx = 0;
  double _totalDy = 0;
  int? _activePointer;
  DateTime? _pointerDownAt;

  void _resetTracking() {
    _totalDx = 0;
    _totalDy = 0;
    _activePointer = null;
    _pointerDownAt = null;
  }

  void _handleSwipeEnd() {
    final dx = _totalDx;
    final dy = _totalDy;
    final startedAt = _pointerDownAt;
    _resetTracking();

    if (dx.abs() < kHorizontalTabSwipeDistanceThreshold) return;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) < kHorizontalTabSwipeMinDuration) {
      return;
    }
    if (dx.abs() < dy.abs() * kHorizontalTabSwipeDominanceRatio) return;

    final swipeLeft = dx < 0;
    final swipeRight = dx > 0;
    final inner = widget.innerTabController;

    if (inner != null) {
      if (swipeRight && inner.index > 0) {
        inner.animateTo(inner.index - 1);
        return;
      }
      if (swipeLeft && inner.index < inner.length - 1) {
        inner.animateTo(inner.index + 1);
        return;
      }
    }

    if (swipeLeft) {
      widget.onMainTabSwipe?.call(1);
    } else if (swipeRight) {
      widget.onMainTabSwipe?.call(-1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _activePointer ??= event.pointer;
        if (_activePointer != event.pointer) return;
        _totalDx = 0;
        _totalDy = 0;
        _pointerDownAt = DateTime.now();
      },
      onPointerMove: (event) {
        if (_activePointer != event.pointer) return;
        _totalDx += event.delta.dx;
        _totalDy += event.delta.dy;
      },
      onPointerUp: (event) {
        if (_activePointer != event.pointer) return;
        _handleSwipeEnd();
      },
      onPointerCancel: (event) {
        if (_activePointer != event.pointer) return;
        _resetTracking();
      },
      child: widget.child,
    );
  }
}
