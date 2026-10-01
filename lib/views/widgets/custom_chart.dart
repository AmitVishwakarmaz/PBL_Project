import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class RssiChart extends StatelessWidget {
  final List<int> rssiSamples;
  final List<double> timeSamples;
  final double durationSeconds;

  const RssiChart({
    super.key,
    required this.rssiSamples,
    required this.timeSamples,
    required this.durationSeconds,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: CustomPaint(
        painter: _RssiChartPainter(
          rssiSamples: rssiSamples,
          timeSamples: timeSamples,
          durationSeconds: durationSeconds,
        ),
      ),
    );
  }
}

class _RssiChartPainter extends CustomPainter {
  final List<int> rssiSamples;
  final List<double> timeSamples;
  final double durationSeconds;

  static const double minRssi = -100.0;
  static const double maxRssi = -35.0;

  _RssiChartPainter({
    required this.rssiSamples,
    required this.timeSamples,
    required this.durationSeconds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double width = size.width;
    final double height = size.height;

    // Paints
    final paintGrid = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1.0;

    final paintAxes = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5;

    final paintRaw = Paint()
      ..color = AppColors.primaryAccentLight
      ..strokeWidth = 1.5
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = AppColors.primaryAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Draw Grid Lines (Y-Axis splits)
    const int ySplits = 5;
    for (int i = 0; i <= ySplits; i++) {
      final double y = height - (i * (height / ySplits));
      canvas.drawLine(Offset(0, y), Offset(width, y), paintGrid);

      // Y-axis labels (dBm values)
      final double rssiVal = minRssi + (i * ((maxRssi - minRssi) / ySplits));
      textPainter.text = TextSpan(
        text: '${rssiVal.toInt()} dBm',
        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(5, y - 10));
    }

    // Draw Grid Lines (X-Axis splits - time in seconds)
    const int xSplits = 6; // Every 10 seconds for 60s
    for (int i = 0; i <= xSplits; i++) {
      final double x = i * (width / xSplits);
      canvas.drawLine(Offset(x, 0), Offset(x, height), paintGrid);

      // X-axis labels (Seconds)
      final double timeVal = i * (durationSeconds / xSplits);
      textPainter.text = TextSpan(
        text: '${timeVal.toInt()}s',
        style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(x - 5, height - 12));
    }

    // Draw outer axes
    canvas.drawLine(Offset(0, 0), Offset(0, height), paintAxes);
    canvas.drawLine(Offset(0, height), Offset(width, height), paintAxes);

    if (rssiSamples.isEmpty) {
      // Draw placeholder text
      textPainter.text = const TextSpan(
        text: 'Awaiting signal samples...',
        style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontStyle: FontStyle.italic),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(width / 2 - 80, height / 2 - 10));
      return;
    }

    // Map points to canvas coordinates
    final List<Offset> points = [];
    for (int i = 0; i < rssiSamples.length; i++) {
      final double time = i < timeSamples.length ? timeSamples[i] : (i * (durationSeconds / rssiSamples.length));
      final double rssi = rssiSamples[i].toDouble().clamp(minRssi, maxRssi);

      // Normalization to [0, 1] range
      final double pctX = time / durationSeconds;
      final double pctY = (rssi - minRssi) / (maxRssi - minRssi);

      // Coordinates
      final double cx = pctX * width;
      final double cy = height - (pctY * height);
      points.add(Offset(cx, cy));
    }

    // Plot connection lines for trends
    if (points.length > 1) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      canvas.drawPath(path, paintLine);
    }

    // Plot raw samples as points
    for (var pt in points) {
      canvas.drawCircle(pt, 2.5, paintRaw);
    }
  }

  @override
  bool shouldRepaint(covariant _RssiChartPainter oldDelegate) {
    return oldDelegate.rssiSamples.length != rssiSamples.length ||
        oldDelegate.timeSamples.length != timeSamples.length;
  }
}
