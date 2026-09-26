import 'dart:math';
import 'package:flutter/material.dart';
import '../models/anchor_network.dart';
import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';

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
        backgroundColor: const Color(0xFFD946EF),
      ),
    );
  }

  void _stopCalibration() {
    widget.measurementRepository.stopActiveTest();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Calibration session stopped. Processing results...'),
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
      backgroundColor: const Color(0xFF171721),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24.0),
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
                      fontFamily: 'Outfit',
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00F0FF),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      anchor.anchorId == selfId ? 'Origin Anchor' : 'Anchor',
                      style: const TextStyle(fontSize: 10, color: Colors.white60),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailItem('Relative X', '${anchor.x.toStringAsFixed(2)} m'),
                  _buildDetailItem('Relative Y', '${anchor.y.toStringAsFixed(2)} m'),
                ],
              ),
              const SizedBox(height: 16),
              if (stats != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDetailItem('Sample Count', '${stats.sampleCount} pkts'),
                    _buildDetailItem('Median RSSI', '${stats.median.toStringAsFixed(1)} dBm'),
                  ],
                ),
                const SizedBox(height: 16),
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
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white38),
                ),
              ] else ...[
                const Text(
                  'Local phone serving as relative origin coordinate point.',
                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.white38),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00F0FF),
                    foregroundColor: Colors.black,
                  ),
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
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
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
          appBar: AppBar(
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
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF171721),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: activeMap != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(16),
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
                                top: 12,
                                left: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'Grid Unit: 1 Meter',
                                    style: TextStyle(fontSize: 10, color: Colors.white70),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.map_rounded,
                                  size: 64,
                                  color: Colors.white10,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No Calibration Map Solved Yet',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white30),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Set your phones in triangle position, configure duration, and click Start Calibration to begin.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: Colors.white24),
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
        padding: const EdgeInsets.all(12),
        color: const Color(0xFFD946EF).withOpacity(0.15),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2.0, color: Color(0xFFD946EF)),
            ),
            const SizedBox(width: 12),
            Text(
              'Calibrating network... $secs seconds remaining',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD946EF)),
            ),
          ],
        ),
      );
    }

    if (lockedMap != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFF00F0FF).withOpacity(0.1),
        child: Row(
          children: [
            const Icon(Icons.lock_rounded, color: Color(0xFF00F0FF), size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Map Locked: ${lockedMap.anchors.length} Nodes • Err: ${lockedMap.overallCalibrationError.toStringAsFixed(2)}m • Conf: ${lockedMap.confidence.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)),
              ),
            ),
          ],
        ),
      );
    }

    if (currentCalib != null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: const Color(0xFFEAB308).withOpacity(0.15),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEAB308), size: 16),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Previewing Calibration Session (Unlocked) • Conf: ${currentCalib.confidence.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEAB308)),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white.withOpacity(0.02),
      child: const Row(
        children: [
          Icon(Icons.satellite_alt_rounded, color: Colors.white30, size: 16),
          SizedBox(width: 12),
          Text(
            'Anchor Map: Uncalibrated',
            style: TextStyle(fontSize: 12, color: Colors.white30),
          ),
        ],
      ),
    );
  }

  Widget _buildControlPanel(bool isCalibrating, AnchorMap? lockedMap, AnchorMap? currentCalib) {
    if (isCalibrating) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _stopCalibration,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
            icon: const Icon(Icons.stop_rounded),
            label: const Text('STOP CALIBRATION'),
          ),
        ),
      );
    }

    if (currentCalib != null) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const Text(
              'Dynamic Solve Summary',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricColumn('AB', currentCalib.measuredPairwiseDistances['AB'] != null ? '${currentCalib.measuredPairwiseDistances['AB']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('AC', currentCalib.measuredPairwiseDistances['AC'] != null ? '${currentCalib.measuredPairwiseDistances['AC']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('BC', currentCalib.measuredPairwiseDistances['BC'] != null ? '${currentCalib.measuredPairwiseDistances['BC']!.toStringAsFixed(2)}m' : 'N/A'),
                _buildMetricColumn('Error', '${currentCalib.overallCalibrationError.toStringAsFixed(2)}m'),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: currentCalib.anchors.map((a) {
                return ActionChip(
                  label: Text('${a.anchorId} (${a.x.toStringAsFixed(1)}, ${a.y.toStringAsFixed(1)})'),
                  onPressed: () => _showAnchorDetails(a, currentCalib),
                  backgroundColor: Colors.white10,
                  side: BorderSide.none,
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
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
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.measurementRepository.acceptAndLockAnchorMap(currentCalib);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Anchor map calibration accepted and locked locally.'),
                          backgroundColor: Color(0xFF00F0FF),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                    ),
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
        padding: const EdgeInsets.all(16.0),
        decoration: const BoxDecoration(
          color: Color(0xFF13131A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            const Text(
              'Locked Nodes (Tap to Inspect)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white24),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: lockedMap.anchors.map((a) {
                return ActionChip(
                  label: Text('${a.anchorId} (${a.x.toStringAsFixed(1)}, ${a.y.toStringAsFixed(1)})'),
                  onPressed: () => _showAnchorDetails(a, lockedMap),
                  backgroundColor: const Color(0xFF00F0FF).withOpacity(0.05),
                  side: BorderSide(color: const Color(0xFF00F0FF).withOpacity(0.2)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.measurementRepository.recalibrateAnchorMap();
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('RECALIBRATE'),
              ),
            ),
          ],
        ),
      );
    }

    // Default Uncalibrated Control Slider
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: const BoxDecoration(
        color: Color(0xFF13131A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Calibration Duration',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
              ),
              Text(
                '$_calibrationDurationSeconds Seconds',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD946EF)),
              )
            ],
          ),
          Slider(
            value: _calibrationDurationSeconds.toDouble(),
            min: 10,
            max: 60,
            divisions: 10,
            activeColor: const Color(0xFFD946EF),
            onChanged: (val) {
              setState(() {
                _calibrationDurationSeconds = val.round();
              });
            },
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _startCalibration,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD946EF),
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.play_arrow_rounded),
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
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white30)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
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
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 1.0;
    
    final int startY = minY.floor();
    final int endY = maxY.ceil();
    for (int y = startY; y <= endY; y++) {
      final p1 = toScreen(minX, y.toDouble());
      final p2 = toScreen(maxX, y.toDouble());
      canvas.drawLine(p1, p2, gridPaint);
      
      final tp = TextPainter(
        text: TextSpan(text: '${y}m', style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 8)),
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
        text: TextSpan(text: '${x}m', style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 8)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p1 + const Offset(5, 5));
    }

    // 2. Draw Axes
    final axisPaint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..strokeWidth = 1.5;
    canvas.drawLine(toScreen(minX, 0), toScreen(maxX, 0), axisPaint);
    canvas.drawLine(toScreen(0, minY), toScreen(0, maxY), axisPaint);

    // 3. Draw Links between all solved anchors
    final linkPaint = Paint()
      ..color = const Color(0xFF00F0FF).withOpacity(0.15)
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
      ..color = const Color(0xFF00F0FF)
      ..style = PaintingStyle.fill;

    final selfAnchorPaint = Paint()
      ..color = const Color(0xFFD946EF)
      ..style = PaintingStyle.fill;

    for (final anchor in map.anchors) {
      final pos = toScreen(anchor.x, anchor.y);
      final isSelf = anchor.anchorId == selfId;
      
      // Node glow
      final glowPaint = Paint()
        ..color = (isSelf ? const Color(0xFFD946EF) : const Color(0xFF00F0FF)).withOpacity(0.15)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, 14.0, glowPaint);
      
      // Inner Circle
      canvas.drawCircle(pos, 6.0, isSelf ? selfAnchorPaint : anchorPaint);

      // Node Label text
      final labelSpan = TextSpan(
        text: '${anchor.anchorId}${isSelf ? " (Self)" : ""}\n(${anchor.x.toStringAsFixed(1)}, ${anchor.y.toStringAsFixed(1)})',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withOpacity(0.5),
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
