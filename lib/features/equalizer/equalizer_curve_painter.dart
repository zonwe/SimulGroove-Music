import 'package:flutter/material.dart';

/// 均衡器曲线绘制：0dB 基线、平滑贝塞尔曲线、渐变填充与控制点。
class EqualizerCurvePainter extends CustomPainter {
  EqualizerCurvePainter({
    required this.gains,
    required this.enabled,
    required this.primaryColor,
    required this.gridColor,
  });

  final List<double> gains;
  final bool enabled;
  final Color primaryColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;
    final midY = height / 2;

    final dashPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.7)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // 0dB Center line
    canvas.drawLine(Offset(0, midY), Offset(width, midY), dashPaint);

    if (gains.isEmpty) return;

    // Convert gains to canvas points
    final points = <Offset>[];
    final step = width / (gains.length - 1);

    for (var i = 0; i < gains.length; i++) {
      final x = i * step;
      // Map gain [-12, +12] to y [height - 8, 8]
      final g = enabled ? gains[i].clamp(-12.0, 12.0) : 0.0;
      final y = midY - (g / 12.0) * (midY - 12);
      points.add(Offset(x, y));
    }

    // Build smooth cubic bezier curve
    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    // Fill area under curve with gradient
    final fillPath = Path.from(path)
      ..lineTo(width, height)
      ..lineTo(0, height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (enabled ? primaryColor : Colors.grey).withValues(alpha: 0.35),
          (enabled ? primaryColor : Colors.grey).withValues(alpha: 0.02),
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height));

    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final linePaint = Paint()
      ..color = enabled ? primaryColor : Colors.grey
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, linePaint);

    // Draw dots at control points
    final dotPaint = Paint()
      ..color = enabled ? primaryColor : Colors.grey
      ..style = PaintingStyle.fill;

    for (final point in points) {
      canvas.drawCircle(point, 3.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerCurvePainter oldDelegate) {
    return oldDelegate.enabled != enabled ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.gains != gains;
  }
}
