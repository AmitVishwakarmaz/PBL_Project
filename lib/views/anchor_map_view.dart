import 'dart:math';
import 'package:flutter/material.dart';
import '../models/anchor_network.dart';
import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/app_theme.dart';

class AnchorMapView extends StatefulWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;

  const AnchorMapView({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
  });

  @override
  State<AnchorMapView> createState() => _AnchorMapViewState();
}

class _AnchorMapViewState extends State<AnchorMapView> {
  int _calibrationDurationSeconds = 30; // default duration

  void _startCalibration() {
    // Request repository to start calibration
    widget.measurementRepository.clearMeasurements();
    widget.measurementRepository.startTest(
      testType: "AnchorCalibration",
      targetDeviceId: "All",
      actualDistance: 1.0,
      orientation: "Default",
      obstruction: "None",
      durationSeconds: _calibrationDurationSeconds,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Starting anchor calibration session ($_calibrationDurationSeconds seconds)...'),
        backgroundColor: AppColors.primaryAccent,
      ),
    );
  }

  void _stopCalibration() {
    widget.measurementRepository.stopActiveTest();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calibration session stopped. Processing results...'),
        backgroundColor: AppColors.charcoal,
      ),
    );
  }

  void _showAnchorDetails(AnchorCoordinate anchor, AnchorMap map) {
    final String selfId = widget.storageService.getDeviceId();
    
    // Attempt to retrieve statistics from raw scanned device if available
    final repoDevice = widget.measurementRepository.devices.firstWhere(
      (d) => d.deviceId == anchor.anchorId,
      orElse: () => BleDevice(
        deviceId: anchor.anchorId,
        friendlyName: anchor.anchorId,
        lastSeen: DateTime.now(),
        rssi: -100,
      ),
    );
    
    final stats = repoDevice.rawRssiHistory.isNotEmpty
        ? repoDevice.getStats(widget.measurementRepository.devices.isEmpty 
            ? RssiProcessor() 
            : RssiProcessor())
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    anchor.anchorId == selfId ? '${anchor.anchorId} (Self)' : anchor.anchorId,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      anchor.anchorId == selfId ? 'Origin Anchor' : 'Anchor',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                  )
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(color: AppColors.border),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailItem('Relative X', '${anchor.x.toStringAsFixed(2)} m'),
                  _buildDetailItem('Relative Y', '${anchor.y.toStringAsFixed(2)} m'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (stats != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDetailItem('Sample Count', '${stats.sampleCount} pkts'),
                    _buildDetailItem('Median RSSI', '${stats.median.toStringAsFixed(1)} dBm'),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDetailItem('Mean RSSI', '${stats.mean.toStringAsFixed(1)} dBm'),
                    _buildDetailItem('RSSI Std Dev', '${stats.stdDev.toStringAsFixed(1)} dB'),
                  ],
                ),
              ] else if (anchor.anchorId != selfId) ...[
                const Text(
                  'Scanned remotely via P2P relay advertisement.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textTertiary),
                ),
              ] else ...[
                const Text(
                  'Local phone serving as relative origin coordinate point.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textTertiary),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final String selfId = widget.storageService.getDeviceId();
    
    return ListenableBuilder(
      listenable: widget.measurementRepository,
      builder: (context, _) {
        final bool isCalibrating = widget.measurementRepository.isTestActive &&
            widget.measurementRepository.activeTestType == "AnchorCalibration";
        
        final lockedMap = widget.measurementRepository.lockedAnchorMap;
        final currentCalib = widget.measurementRepository.currentCalibrationMap;
        final activeMap = lockedMap ?? currentCalib;
        
        return Scaffold(
          backgroundColor: AppColors.primaryBg,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.textPrimary,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1.0),
              child: Container(color: AppColors.border, height: 1.0),
            ),
            title: const Text('Anchor Map Localization'),
            actions: [
              if (activeMap != null)
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {
                    widget.measurementRepository.recalibrateAnchorMap();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Calibration cleared. Ready to recalibrate.')),
                    );
                  },
                  tooltip: 'Recalibrate Map',
                )
            ],
          ),
          body: Column(
            children: [
              // 1. Session Status Indicator Header
              _buildStatusHeader(isCalibrating, lockedMap, currentCalib),

              // 2. Map Canvas (CustomPainter)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: activeMap != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                          child: Stack(
                            children: [
                              InteractiveViewer(
                                minScale: 0.1,
                                maxScale: 4.0,
                                boundaryMargin: const EdgeInsets.all(100),
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: AnchorMapPainter(activeMap, selfId),
                                ),
                              ),
                              // Grid metric marker overlay
                              Positioned(
                                top: AppSpacing.sm,
                                left: AppSpacing.sm,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceSubtle,
                                    borderRadius: BorderRadius.circular(AppRadii.sm),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: const Text(
                                    'Grid Unit: 1 Meter',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.map_outlined,
                                  size: 56,
                                  color: AppColors.textTertiary.withOpacity(0.5),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                const Text(
                                  'No Calibration Map Solved Yet',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                const Text(
                                  'Set your phones in triangle position, configure duration, and click Start Calibration to begin.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),

              // 3. Control Panel Footer
              _buildControlPanel(isCalibrating, lockedMap, currentCalib),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusHeader(bool isCalibrating, AnchorMap? lockedMap, AnchorMap? currentCalib) {
    if (isCalibrating) {
      final secs = widget.measurementRepository.testSecondsRemaining;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.primaryAccentSubtle,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2.0, color: AppColors.primaryAccent),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Calibrating network... $secs seconds remaining',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryAccent),
            ),
          ],
        ),
      );
    }

    if (lockedMap != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.successSubtle,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppColors.success, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Map Locked: ${lockedMap.anchors.length} Nodes • Err: ${lockedMap.overallCalibrationError.toStringAsFixed(2)}m • Conf: ${lockedMap.confidence.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success),
              ),
            ),
          ],
        ),
      );
    }

    if (currentCalib != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
        decoration: const BoxDecoration(
          color: AppColors.primaryAccentSubtle,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: AppColors.primaryAccent, size: 16),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Previewing Calibration Session (Unlocked) • Conf: ${currentCalib.confidence.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primaryAccent),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: const Row(
        children: [
          Icon(Icons.satellite_alt_rounded, color: AppColors.textTertiary, size: 16),
          SizedBox(width: AppSpacing.sm),
          Text(
            'Anchor Map: Uncalibrated',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isCalibrating, AnchorMap? lockedMap, AnchorMap? currentCalib) {
    if (isCalibrating) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _stopCalibration,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error, width: 1.0),
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('STOP CALIBRATION'),
          ),
        ),
      );
    }

    if (currentCalib != null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          children: [
            const Text(
              'Dynamic Solve Summary',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn('AB', currentCalib.measuredPairwiseDistances['AB'] != null ? '${currentCalib.measuredPairwiseDistances['AB']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('AC', currentCalib.measuredPairwiseDistances['AC'] != null ? '${currentCalib.measuredPairwiseDistances['AC']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('BC', currentCalib.measuredPairwiseDistances['BC'] != null ? '${currentCalib.measuredPairwiseDistances['BC']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('Error', '${currentCalib.overallCalibrationError.toStringAsFixed(2)}m'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: currentCalib.anchors.map((a) {
                return ActionChip(
                  label: Text('${a.anchorId} (${a.x.toStringAsFixed(1)}, ${a.y.toStringAsFixed(1)})'),
                  onPressed: () => _showAnchorDetails(a, currentCalib),
                  backgroundColor: AppColors.surfaceSubtle,
                  side: const BorderSide(color: AppColors.border),
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.measurementRepository.recalibrateAnchorMap();
                    },
                    child: const Text('REJECT'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.measurementRepository.acceptAndLockAnchorMap(currentCalib);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Anchor map calibration accepted and locked locally.'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    },
                    child: const Text('ACCEPT & LOCK'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (lockedMap != null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Column(
          children: [
            const Text(
              'Locked Nodes (Tap to Inspect)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textSecondary, letterSpacing: 0.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: lockedMap.anchors.map((a) {
                return ActionChip(
                  label: Text('${a.anchorId} (${a.x.toStringAsFixed(1)}, ${a.y.toStringAsFixed(1)})'),
                  onPressed: () => _showAnchorDetails(a, lockedMap),
                  backgroundColor: AppColors.surfaceSubtle,
                  side: const BorderSide(color: AppColors.border),
                  labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.measurementRepository.recalibrateAnchorMap();
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('RECALIBRATE'),
              ),
            ),
          ],
        ),
      );
    }

    // Default Uncalibrated Control Slider
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Calibration Duration',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
              ),
              Text(
                '$_calibrationDurationSeconds Seconds',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primaryAccent),
              )
            ],
          ),
          Slider(
            value: _calibrationDurationSeconds.toDouble(),
            min: 10,
            max: 60,
            divisions: 10,
            activeColor: AppColors.primaryAccent,
            inactiveColor: AppColors.border,
            onChanged: (val) {
              setState(() {
                _calibrationDurationSeconds = val.round();
              });
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startCalibration,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('START ANCHOR CALIBRATION'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricColumn(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
      ],
    );
  }
}

class AnchorMapPainter extends CustomPainter {
  final AnchorMap map;
  final String selfId;

  AnchorMapPainter(this.map, this.selfId);

  @override
  void paint(Canvas canvas, Size size) {
    if (map.anchors.isEmpty) return;

    // Find bounding box
    double minX = map.anchors.map((a) => a.x).reduce(min);
    double maxX = map.anchors.map((a) => a.x).reduce(max);
    double minY = map.anchors.map((a) => a.y).reduce(min);
    double maxY = map.anchors.map((a) => a.y).reduce(max);

    // Padding (1 meter minimum boundary)
    minX -= 1.0;
    maxX += 1.0;
    minY -= 1.0;
    maxY += 1.0;

    final double worldW = maxX - minX;
    final double worldH = maxY - minY;

    // Dynamic scale to maintain aspect ratio
    final double scaleX = size.width / (worldW > 0 ? worldW : 1.0);
    final double scaleY = size.height / (worldH > 0 ? worldH : 1.0);
    final double scale = min(scaleX, scaleY);

    // Center offsets
    final double offsetX = (size.width - (maxX - minX) * scale) / 2.0 - minX * scale;
    final double offsetY = (size.height - (maxY - minY) * scale) / 2.0 - minY * scale;

    Offset toScreen(double x, double y) {
      final double sx = offsetX + x * scale;
      final double sy = size.height - (offsetY + y * scale); // Invert Y
      return Offset(sx, sy);
    }

    // 1. Draw Grid
    final gridPaint = Paint()
      ..color = AppColors.border.withOpacity(0.6)
      ..strokeWidth = 1.0;
    
    final int startY = minY.floor();
    final int endY = maxY.ceil();
    for (int y = startY; y <= endY; y++) {
      final p1 = toScreen(minX, y.toDouble());
      final p2 = toScreen(maxX, y.toDouble());
      canvas.drawLine(p1, p2, gridPaint);
      
      final tp = TextPainter(
        text: TextSpan(text: '${y}m', style: TextStyle(color: AppColors.textTertiary.withOpacity(0.7), fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p1 + const Offset(5, -10));
    }

    final int startX = minX.floor();
    final int endX = maxX.ceil();
    for (int x = startX; x <= endX; x++) {
      final p1 = toScreen(x.toDouble(), minY);
      final p2 = toScreen(x.toDouble(), maxY);
      canvas.drawLine(p1, p2, gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: '${x}m', style: TextStyle(color: AppColors.textTertiary.withOpacity(0.7), fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p1 + const Offset(5, 5));
    }

    // 2. Draw Axes
    final axisPaint = Paint()
      ..color = AppColors.borderStrong
      ..strokeWidth = 1.5;
    canvas.drawLine(toScreen(minX, 0), toScreen(maxX, 0), axisPaint);
    canvas.drawLine(toScreen(0, minY), toScreen(0, maxY), axisPaint);

    // 3. Draw Links between all solved anchors
    final linkPaint = Paint()
      ..color = AppColors.primaryAccent.withOpacity(0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    
    for (int i = 0; i < map.anchors.length; i++) {
      for (int j = i + 1; j < map.anchors.length; j++) {
        final p1 = toScreen(map.anchors[i].x, map.anchors[i].y);
        final p2 = toScreen(map.anchors[j].x, map.anchors[j].y);
        canvas.drawLine(p1, p2, linkPaint);
      }
    }

    // 4. Draw Anchor Nodes
    final anchorPaint = Paint()
      ..color = AppColors.primaryAccent
      ..style = PaintingStyle.fill;

    final selfAnchorPaint = Paint()
      ..color = AppColors.charcoal
      ..style = PaintingStyle.fill;

    for (final anchor in map.anchors) {
      final pos = toScreen(anchor.x, anchor.y);
      final isSelf = anchor.anchorId == selfId;
      
      // Node glow
      final glowPaint = Paint()
        ..color = (isSelf ? AppColors.charcoal.withOpacity(0.12) : AppColors.primaryAccent.withOpacity(0.15))
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 14.0, glowPaint);
      
      // Inner Circle
      canvas.drawCircle(pos, 6.0, isSelf ? selfAnchorPaint : anchorPaint);

      // Node Label text
      final labelSpan = TextSpan(
        text: '${anchor.anchorId}${isSelf ? " (Self)" : ""}\n(${anchor.x.toStringAsFixed(1)}, ${anchor.y.toStringAsFixed(1)})',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          backgroundColor: AppColors.surface,
        ),
      );
      final tp = TextPainter(
        text: labelSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      tp.paint(canvas, pos + Offset(-tp.width / 2.0, 10));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
