import 'dart:math';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../services/central_server_service.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../models/anchor_network.dart';
import '../models/ble_device.dart';
import 'calibration_view.dart';
import '../utils/app_theme.dart';
import 'widgets/server_config_dialog.dart';

class TrackedMapView extends StatefulWidget {
  final StorageService storageService;
  final MeasurementRepository measurementRepository;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final CentralServerService centralServerService;
  final VoidCallback onSwitchRole;

  const TrackedMapView({
    super.key,
    required this.storageService,
    required this.measurementRepository,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.centralServerService,
    required this.onSwitchRole,
  });

  @override
  State<TrackedMapView> createState() => _TrackedMapViewState();
}

class _TrackedMapViewState extends State<TrackedMapView> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _startServices();
  }

  Future<void> _startServices() async {
    try {
      if (!widget.bleScanner.isScanning) {
        await widget.bleScanner.startScanning();
      }
      if (!widget.bleAdvertiser.isAdvertising) {
        await widget.bleAdvertiser.startAdvertising();
      }
    } catch (e) {
      debugPrint("BLE startup notice in TrackedMapView: $e");
    }

    final host = widget.storageService.getServerHost();
    final port = widget.storageService.getServerPort();
    if (host.isNotEmpty) {
      widget.centralServerService.startClientSync(
        targetDeviceId: widget.storageService.getDeviceId(),
        host: host,
        port: port,
      );
    }
  }

  @override
  void dispose() {
    widget.centralServerService.stopClientSync();
    _pulseController.dispose();
    super.dispose();
  }

  void _editServerHostDialog() {
    ServerConfigDialog.show(
      context,
      storageService: widget.storageService,
      centralServerService: widget.centralServerService,
      onSaved: () {
        final host = widget.storageService.getServerHost();
        final port = widget.storageService.getServerPort();
        widget.centralServerService.startClientSync(
          targetDeviceId: widget.storageService.getDeviceId(),
          host: host,
          port: port,
        );
        setState(() {});
      },
    );
  }

  void _openCalibrationDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, controller) {
            return CalibrationView(
              storageService: widget.storageService,
              measurementRepository: widget.measurementRepository,
              scrollController: controller,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.measurementRepository, widget.centralServerService]),
      builder: (context, _) {
        final TrackedLocation? location = widget.measurementRepository.trackedLocation;
        final List<BleDevice> anchorDevices = widget.measurementRepository.devices
            .where((d) => d.role == 'ANCHOR' || d.deviceId.startsWith('TEST-A'))
            .where((d) => d.rawRssiHistory.isNotEmpty)
            .toList();

        final String currentRoom = location?.roomName ?? widget.storageService.getAssignedRoom();
        final double posX = location?.x ?? 0.0;
        final double posY = location?.y ?? 0.0;
        final double confidence = location?.confidence ?? (anchorDevices.isEmpty ? 0.0 : 75.0);
        final String source = location?.source == 'CENTRAL_SERVER'
            ? 'Central Server (${widget.centralServerService.serverUrl})'
            : 'Local BLE Trilateration (No GPS)';

        return Scaffold(
          backgroundColor: AppColors.primaryBg,
          appBar: AppBar(
            backgroundColor: AppColors.primaryBg,
            elevation: 0,
            title: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Flexible(
                  child: Text(
                    'Indoor Navigation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              // Configure Server IP
              IconButton(
                icon: const Icon(Icons.dns_rounded, color: AppColors.primaryAccent, size: 20),
                tooltip: 'Server Address',
                onPressed: _editServerHostDialog,
              ),
              // Switch Role
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.textSecondary, size: 22),
                tooltip: 'Switch to Anchor Mode',
                onPressed: widget.onSwitchRole,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
          ),
          body: Column(
            children: [
              // 1. Prominent Room & Position Card
              _buildLocationBanner(
                currentRoom: currentRoom,
                posX: posX,
                posY: posY,
                confidence: confidence,
                source: source,
                anchorCount: anchorDevices.length,
              ),

              // 2. Interactive 2D Indoor Room Map
              Expanded(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: Stack(
                      children: [
                        InteractiveViewer(
                          minScale: 0.2,
                          maxScale: 3.5,
                          boundaryMargin: const EdgeInsets.all(80),
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, _) {
                              return CustomPaint(
                                size: Size.infinite,
                                painter: IndoorMapPainter(
                                  roomName: currentRoom,
                                  userX: posX,
                                  userY: posY,
                                  anchors: anchorDevices,
                                  lockedMap: widget.centralServerService.activeAnchorMap ?? widget.measurementRepository.lockedAnchorMap,
                                  pulseValue: _pulseController.value,
                                  estimator: widget.measurementRepository,
                                ),
                              );
                            },
                          ),
                        ),

                        // Map Legend / Scale in Corner
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHighlight.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primaryAccent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Grid: 1.0 m  •  Room: $currentRoom',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Re-center / Calibrate FAB
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: FloatingActionButton.small(
                            backgroundColor: AppColors.primaryAccent,
                            foregroundColor: Colors.white,
                            elevation: 2,
                            onPressed: _openCalibrationDialog,
                            tooltip: 'Calibrate Distance',
                            child: const Icon(Icons.straighten_rounded, size: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Compact Anchors Summary Drawer / Footer
              _buildAnchorFooter(anchorDevices),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationBanner({
    required String currentRoom,
    required double posX,
    required double posY,
    required double confidence,
    required String source,
    required int anchorCount,
  }) {
    final bool hasSignal = anchorCount > 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: hasSignal ? AppColors.success.withValues(alpha: 0.4) : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Room badge
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: hasSignal ? AppColors.successSubtle : AppColors.surfaceSubtle,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Icon(
                      Icons.meeting_room_rounded,
                      color: hasSignal ? AppColors.success : AppColors.textSecondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CURRENT LOCATION',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentRoom,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: hasSignal ? AppColors.textPrimary : AppColors.textSecondary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // Confidence badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hasSignal ? AppColors.successSubtle : AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: hasSignal ? AppColors.success.withValues(alpha: 0.3) : AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      hasSignal ? '${confidence.toStringAsFixed(0)}% Conf.' : 'Searching',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: hasSignal ? AppColors.success : AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '$anchorCount Anchors Active',
                      style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Coordinates: (${posX.toStringAsFixed(2)}m, ${posY.toStringAsFixed(2)}m)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              InkWell(
                onTap: _editServerHostDialog,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_outlined, size: 11, color: AppColors.primaryAccent),
                      const SizedBox(width: 4),
                      Text(
                        source,
                        style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnchorFooter(List<BleDevice> anchors) {
    if (anchors.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryAccent),
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Scanning for nearby BLE Anchors in Room A...',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'DETECTED ANCHOR NODES',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: AppColors.primaryAccent),
              ),
              Text(
                '${anchors.length} detected',
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: anchors.map((a) {
                final dist = widget.measurementRepository.getDistanceToDevice(a.deviceId);
                final rssi = a.rawRssiHistory.isNotEmpty ? a.rawRssiHistory.last : -100;

                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: AppColors.primaryAccent, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        a.friendlyName,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${dist > 0 ? dist.toStringAsFixed(1) : "?"}m',
                        style: const TextStyle(color: AppColors.primaryAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$rssi dBm',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class IndoorMapPainter extends CustomPainter {
  final String roomName;
  final double userX;
  final double userY;
  final List<BleDevice> anchors;
  final AnchorMap? lockedMap;
  final double pulseValue;
  final MeasurementRepository estimator;

  IndoorMapPainter({
    required this.roomName,
    required this.userX,
    required this.userY,
    required this.anchors,
    required this.lockedMap,
    required this.pulseValue,
    required this.estimator,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Determine World Dimensions & Anchor Coordinates
    final defaultPositions = [
      const Offset(0.0, 0.0),
      const Offset(6.0, 0.0),
      const Offset(3.0, 5.0),
      const Offset(0.0, 5.0),
      const Offset(6.0, 5.0),
    ];

    final Map<String, Offset> anchorPos = {};
    if (lockedMap != null && lockedMap!.anchors.isNotEmpty) {
      for (var a in lockedMap!.anchors) {
        anchorPos[a.anchorId] = Offset(a.x, a.y);
      }
    }

    for (int i = 0; i < anchors.length; i++) {
      final dev = anchors[i];
      if (!anchorPos.containsKey(dev.deviceId)) {
        anchorPos[dev.deviceId] = defaultPositions[i % defaultPositions.length];
      }
    }

    // Include user position and anchors in bounds
    double minX = 0.0;
    double maxX = 6.0;
    double minY = 0.0;
    double maxY = 5.0;

    for (var pos in anchorPos.values) {
      minX = min(minX, pos.dx);
      maxX = max(maxX, pos.dx);
      minY = min(minY, pos.dy);
      maxY = max(maxY, pos.dy);
    }
    minX = min(minX, userX);
    maxX = max(maxX, userX);
    minY = min(minY, userY);
    maxY = max(maxY, userY);

    // Padding 1.5 meters around room
    minX -= 1.5;
    maxX += 1.5;
    minY -= 1.5;
    maxY += 1.5;

    final double worldW = maxX - minX;
    final double worldH = maxY - minY;

    final double scaleX = size.width / (worldW > 0 ? worldW : 1.0);
    final double scaleY = size.height / (worldH > 0 ? worldH : 1.0);
    final double scale = min(scaleX, scaleY);

    final double offsetX = (size.width - worldW * scale) / 2.0 - minX * scale;
    final double offsetY = (size.height - worldH * scale) / 2.0 - minY * scale;

    Offset toScreen(double x, double y) {
      final double sx = offsetX + x * scale;
      final double sy = size.height - (offsetY + y * scale); // Invert Y
      return Offset(sx, sy);
    }

    // 2. Draw 1-Meter Grid
    final gridPaint = Paint()
      ..color = AppColors.borderLight
      ..strokeWidth = 1.0;

    final int startY = minY.floor();
    final int endY = maxY.ceil();
    for (int y = startY; y <= endY; y++) {
      final p1 = toScreen(minX, y.toDouble());
      final p2 = toScreen(maxX, y.toDouble());
      canvas.drawLine(p1, p2, gridPaint);
    }

    final int startX = minX.floor();
    final int endX = maxX.ceil();
    for (int x = startX; x <= endX; x++) {
      final p1 = toScreen(x.toDouble(), minY);
      final p2 = toScreen(x.toDouble(), maxY);
      canvas.drawLine(p1, p2, gridPaint);
    }

    // 3. Draw Room Boundary (Room A blueprint rectangle)
    final roomRect = Rect.fromPoints(toScreen(0.0, 5.0), toScreen(6.0, 0.0));
    final roomPaint = Paint()
      ..color = AppColors.surfaceSubtle.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;
    final roomBorderPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(RRect.fromRectAndRadius(roomRect, const Radius.circular(8)), roomPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(roomRect, const Radius.circular(8)), roomBorderPaint);

    // Room Blueprint Watermark Label
    final roomLabelSpan = TextSpan(
      text: roomName.toUpperCase(),
      style: TextStyle(
        color: AppColors.border.withValues(alpha: 0.7),
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 4.0,
      ),
    );
    final roomTp = TextPainter(text: roomLabelSpan, textDirection: TextDirection.ltr)..layout();
    roomTp.paint(canvas, roomRect.center - Offset(roomTp.width / 2.0, roomTp.height / 2.0));

    // 4. Draw Radial Distance Lines from User to Anchors
    final userPos = toScreen(userX, userY);

    for (var dev in anchors) {
      if (!anchorPos.containsKey(dev.deviceId)) continue;
      final aPos = toScreen(anchorPos[dev.deviceId]!.dx, anchorPos[dev.deviceId]!.dy);
      final dist = estimator.getDistanceToDevice(dev.deviceId);

      // Subtle dash line
      final linePaint = Paint()
        ..color = AppColors.border
        ..strokeWidth = 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawLine(userPos, aPos, linePaint);

      // Distance tag on the line
      if (dist > 0) {
        final mid = Offset((userPos.dx + aPos.dx) / 2.0, (userPos.dy + aPos.dy) / 2.0);
        final distSpan = TextSpan(
          text: '${dist.toStringAsFixed(1)}m',
          style: const TextStyle(
            color: AppColors.primaryAccent,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            backgroundColor: AppColors.surfaceHighlight,
          ),
        );
        final dtp = TextPainter(text: distSpan, textDirection: TextDirection.ltr)..layout();
        dtp.paint(canvas, mid - Offset(dtp.width / 2.0, dtp.height / 2.0));
      }
    }

    // 5. Draw Anchor Nodes (Warm Amber Beacons)
    final anchorNodePaint = Paint()
      ..color = AppColors.secondaryAccent
      ..style = PaintingStyle.fill;

    for (var dev in anchors) {
      if (!anchorPos.containsKey(dev.deviceId)) continue;
      final pos = toScreen(anchorPos[dev.deviceId]!.dx, anchorPos[dev.deviceId]!.dy);

      // Outer ring
      canvas.drawCircle(pos, 9.0, Paint()..color = AppColors.secondaryAccentSubtle..style = PaintingStyle.fill);
      // Center dot
      canvas.drawCircle(pos, 4.5, anchorNodePaint);

      // Anchor text label
      final labelSpan = TextSpan(
        text: '${dev.friendlyName}\n(${anchorPos[dev.deviceId]!.dx.toStringAsFixed(1)}, ${anchorPos[dev.deviceId]!.dy.toStringAsFixed(1)})',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 8,
          fontWeight: FontWeight.bold,
          backgroundColor: AppColors.surfaceHighlight,
        ),
      );
      final tp = TextPainter(text: labelSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout();
      tp.paint(canvas, pos + Offset(-tp.width / 2.0, 10));
    }

    // 6. Draw Tracked Device / User Marker with Vibrant Orange Pulse Pin
    if (anchors.isNotEmpty) {
      // Pulse ring animation
      final double pulseRadius = 12.0 + pulseValue * 20.0;
      final double pulseOpacity = max(0.0, 1.0 - pulseValue);
      final pulsePaint = Paint()
        ..color = AppColors.primaryAccent.withValues(alpha: pulseOpacity * 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(userPos, pulseRadius, pulsePaint);

      // User Core Dot (High-visibility Orange Location Pin)
      final userGlow = Paint()
        ..color = AppColors.primaryAccentSubtle
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userPos, 11.0, userGlow);

      final userDot = Paint()
        ..color = AppColors.primaryAccent
        ..style = PaintingStyle.fill;
      canvas.drawCircle(userPos, 6.5, userDot);

      // User Label
      final userLabelSpan = TextSpan(
        text: 'YOU\n(${userX.toStringAsFixed(1)}m, ${userY.toStringAsFixed(1)}m)',
        style: const TextStyle(
          color: AppColors.primaryAccent,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          backgroundColor: AppColors.surfaceHighlight,
        ),
      );
      final utp = TextPainter(text: userLabelSpan, textDirection: TextDirection.ltr, textAlign: TextAlign.center)..layout();
      utp.paint(canvas, userPos + Offset(-utp.width / 2.0, -utp.height - 8));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
