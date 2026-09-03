import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../providers/dashboard_providers.dart';

/// Fixed categorical palette (validated for colorblind-safe adjacent
/// contrast), reused from the web dashboard artifact for visual continuity.
/// The trailing gray is reserved for the "Other" bucket, not a real slot.
const _sliceColors = [
  Color(0xFF2A78D6), // blue
  Color(0xFFEB6834), // orange
  Color(0xFF1BAF7A), // aqua
  Color(0xFFEDA100), // yellow
  Color(0xFFE87BA4), // magenta
  Color(0xFF008300), // green
  Color(0xFF4A3AA7), // violet
];
const _otherColor = Color(0xFFB9B7AE);

Color colorForSlice(int index, bool isOther) {
  if (isOther) return _otherColor;
  return _sliceColors[index % _sliceColors.length];
}

/// A simple donut chart of [slices] with a centered total label — no
/// per-slice interactivity, just a clean static breakdown (the legend below
/// it carries the detail).
class UsageDonutChart extends StatelessWidget {
  const UsageDonutChart({
    super.key,
    required this.slices,
    required this.centerLabel,
  });

  final List<UsageSlice> slices;
  final String centerLabel;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: CustomPaint(
        painter: _DonutPainter(slices: slices, theme: Theme.of(context)),
        child: Center(
          child: Text(
            centerLabel,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.slices, required this.theme});

  final List<UsageSlice> slices;
  final ThemeData theme;

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold<int>(
      0,
      (sum, s) => sum + s.duration.inMilliseconds,
    );
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final strokeWidth = outerRadius * 0.36;
    final radius = outerRadius - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    const gapRadians = 0.025;
    var startAngle = -math.pi / 2;
    for (var i = 0; i < slices.length; i++) {
      final isOther =
          i == slices.length - 1 &&
          slices.length > 1 &&
          slices[i].label.startsWith('Other');
      final fraction = slices[i].duration.inMilliseconds / total;
      final sweep = fraction * 2 * math.pi;
      final paint = Paint()
        ..color = colorForSlice(i, isOther)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      final drawSweep = (sweep - gapRadians).clamp(0.0, sweep);
      canvas.drawArc(
        rect,
        startAngle + gapRadians / 2,
        drawSweep,
        false,
        paint,
      );
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices;
}
