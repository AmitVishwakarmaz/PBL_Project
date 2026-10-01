import 'dart:async';
import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../services/central_server_service.dart';
import '../models/ble_device.dart';
import '../utils/app_theme.dart';
import 'widgets/expandable_text.dart';
import 'widgets/server_config_dialog.dart';

class AnchorNodeView extends StatefulWidget {
  final StorageService storageService;
  final MeasurementRepository measurementRepository;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final CentralServerService centralServerService;
  final VoidCallback onSwitchRole;

  const AnchorNodeView({
    super.key,
    required this.storageService,
    required this.measurementRepository,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.centralServerService,
    required this.onSwitchRole,
  });

  @override
  State<AnchorNodeView> createState() => _AnchorNodeViewState();
}

class _AnchorNodeViewState extends State<AnchorNodeView> {
  Timer? _heartbeatTimer;

  @override
  void initState() {
    super.initState();
    _startBleServices();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) => _sendHeartbeat());
    Future.microtask(() => _sendHeartbeat());
  }

  Future<void> _startBleServices() async {
    try {
      if (!widget.bleScanner.isScanning) {
        await widget.bleScanner.startScanning();
      }
      if (!widget.bleAdvertiser.isAdvertising) {
        await widget.bleAdvertiser.startAdvertising();
      }
    } catch (e) {
      debugPrint("BLE startup notice in AnchorNodeView: $e");
    }
  }

  Future<void> _sendHeartbeat() async {
    final host = widget.storageService.getServerHost();
    final port = widget.storageService.getServerPort();
    if (host.isNotEmpty) {
      await widget.centralServerService.sendAnchorHeartbeat(
        serverHost: host,
        serverPort: port,
        anchorId: widget.storageService.getDeviceId(),
        friendlyName: widget.storageService.getFriendlyName(),
        roomName: widget.storageService.getAssignedRoom(),
        x: widget.storageService.getAnchorX(),
        y: widget.storageService.getAnchorY(),
      );
    }
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _editAnchorCoordinates() {
    final xCtrl = TextEditingController(text: widget.storageService.getAnchorX().toString());
    final yCtrl = TextEditingController(text: widget.storageService.getAnchorY().toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Text('Anchor Coordinates (Room A)', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Space: Room A',
                style: TextStyle(color: AppColors.primaryAccent, fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: xCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(labelText: 'X (meters)'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: yCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: const InputDecoration(labelText: 'Y (meters)'),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: () async {
                final double? x = double.tryParse(xCtrl.text);
                final double? y = double.tryParse(yCtrl.text);
                if (x != null && y != null) {
                  await widget.storageService.setAnchorCoordinates(x, y);
                  await widget.storageService.setAssignedRoom('Room A');
                  _sendHeartbeat();
                  setState(() {});
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _editServerHostDialog() {
    ServerConfigDialog.show(
      context,
      storageService: widget.storageService,
      centralServerService: widget.centralServerService,
      onSaved: () {
        _sendHeartbeat();
        setState(() {});
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.measurementRepository, widget.centralServerService, widget.bleAdvertiser]),
      builder: (context, _) {
        final String anchorId = widget.storageService.getDeviceId();
        final String roomName = widget.storageService.getAssignedRoom();
        final double anchorX = widget.storageService.getAnchorX();
        final double anchorY = widget.storageService.getAnchorY();
        final bool isBroadcasting = widget.bleAdvertiser.isAdvertising;
        final bool isServerRunning = widget.centralServerService.isServerRunning;
        final String serverUrl = widget.centralServerService.serverUrl;

        final List<BleDevice> trackedDevices = widget.measurementRepository.devices
            .where((d) => d.role == 'TRACKED' || d.deviceId.startsWith('TEST-C'))
            .where((d) => d.rawRssiHistory.isNotEmpty)
            .toList();

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
                  decoration: BoxDecoration(
                    color: isBroadcasting ? AppColors.success : AppColors.warning,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Text(
                  'Anchor Node',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.swap_horiz_rounded, color: AppColors.textSecondary),
                tooltip: 'Switch to Tracked Device Mode',
                onPressed: widget.onSwitchRole,
              ),
              const SizedBox(width: AppSpacing.xxs),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Anchor Identity & Position Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryAccentSubtle,
                                  borderRadius: BorderRadius.circular(AppRadii.md),
                                ),
                                child: const Icon(Icons.cell_tower_rounded, color: AppColors.primaryAccent, size: 22),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.storageService.getFriendlyName(),
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    'ID: $anchorId  •  Room: $roomName',
                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, color: AppColors.primaryAccent, size: 18),
                            onPressed: _editAnchorCoordinates,
                            tooltip: 'Edit Position & Room',
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Divider(height: 1, color: AppColors.border),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricItem('Assigned Room', roomName, AppColors.textPrimary),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: _buildMetricItem(
                              'Coordinates',
                              '(${anchorX.toStringAsFixed(1)}m, ${anchorY.toStringAsFixed(1)}m)',
                              AppColors.primaryAccent,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                await _startBleServices();
                                _sendHeartbeat();
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              child: _buildMetricItem(
                                'Status',
                                isBroadcasting ? 'Broadcasting' : 'Inactive (Tap)',
                                isBroadcasting ? AppColors.success : AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // 2. Central Server Target Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryAccentSubtle,
                                    borderRadius: BorderRadius.circular(AppRadii.sm),
                                  ),
                                  child: const Icon(Icons.dns_rounded, color: AppColors.primaryAccent, size: 18),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Central Server',
                                        style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'Target: ${widget.storageService.getServerHost()}:${widget.storageService.getServerPort()}',
                                        style: const TextStyle(color: AppColors.primaryAccent, fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textSecondary),
                            tooltip: 'Change Server IP',
                            onPressed: _editServerHostDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ExpandableText(
                        text: isServerRunning
                            ? 'Local server is active on this phone ($serverUrl). Other anchors can sync calculations here.'
                            : 'Anchors send BLE distance measurements to this server to calculate positions. Running standalone python server? This toggle can stay off.',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, height: 1.3),
                        linkColor: AppColors.primaryAccent,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Host server on this phone:',
                            style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                          ),
                          Switch(
                            value: isServerRunning,
                            activeColor: AppColors.primaryAccent,
                            onChanged: (val) async {
                              if (val) {
                                await widget.centralServerService.startServer();
                              } else {
                                await widget.centralServerService.stopServer();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // 3. Peer Anchors & Fixed Network Calibration Card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                      color: widget.measurementRepository.lockedAnchorMap != null
                          ? AppColors.success.withValues(alpha: 0.5)
                          : AppColors.border,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.hub_rounded,
                                  color: widget.measurementRepository.lockedAnchorMap != null
                                      ? AppColors.success
                                      : AppColors.primaryAccent,
                                  size: 18,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                const Expanded(
                                  child: Text(
                                    'Fixed Anchor Grid',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: widget.measurementRepository.lockedAnchorMap != null
                                  ? AppColors.successSubtle
                                  : AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Text(
                              widget.measurementRepository.lockedAnchorMap != null ? 'LOCKED' : 'DISCOVERING',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: widget.measurementRepository.lockedAnchorMap != null
                                    ? AppColors.success
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ExpandableText(
                        text: 'Anchors measure pairwise BLE distances to calculate relative room coordinates (Anchor A at 0,0; Anchor B on X-axis; Anchor C in 2D space).',
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                        linkColor: AppColors.primaryAccent,
                      ),
                      const SizedBox(height: AppSpacing.sm),

                      // Show peer anchors
                      Builder(builder: (context) {
                        final peerAnchors = widget.measurementRepository.devices
                            .where((d) => d.role == 'ANCHOR' || d.deviceId.startsWith('TEST-A'))
                            .where((d) => d.deviceId != anchorId)
                            .toList();

                        if (peerAnchors.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHighlight,
                              borderRadius: BorderRadius.circular(AppRadii.md),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: const Row(
                              children: [
                                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryAccent)),
                                SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    'Listening for other peer anchors in Room A...',
                                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return Column(
                          children: peerAnchors.map((p) {
                            final dist = widget.measurementRepository.getDistanceToDevice(p.deviceId);
                            final rssi = p.rawRssiHistory.isNotEmpty ? p.rawRssiHistory.last : -100;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceHighlight,
                                borderRadius: BorderRadius.circular(AppRadii.md),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${p.friendlyName} (${p.deviceId})',
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Distance: ${dist > 0 ? dist.toStringAsFixed(2) : "?"}m  ($rssi dBm)',
                                    style: const TextStyle(color: AppColors.primaryAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }),
                      const SizedBox(height: AppSpacing.sm),

                      // Locked coordinates display
                      if (widget.measurementRepository.lockedAnchorMap != null) ...[
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Calculated Fixed Anchor Points:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.success),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      await widget.measurementRepository.recalibrateAnchorMap();
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Fixed anchor grid reset. No stale coordinates.')),
                                      );
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      child: Text('CLEAR', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.error)),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ...widget.measurementRepository.lockedAnchorMap!.anchors.map((a) {
                                final isMe = a.anchorId == anchorId;
                                final label = isMe ? "${widget.storageService.getFriendlyName()} (This Phone)" : a.anchorId;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                                  child: Text(
                                    '• $label:  X = ${a.x.toStringAsFixed(2)}m,  Y = ${a.y.toStringAsFixed(2)}m',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isMe ? AppColors.primaryAccent : AppColors.textSecondary,
                                      fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],

                      // Solve & Lock or Reset Action Buttons
                      if (widget.measurementRepository.lockedAnchorMap != null)
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: SizedBox(
                                height: 42,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final map = widget.measurementRepository.solveCoordinates();
                                    if (map != null) {
                                      await widget.measurementRepository.acceptAndLockAnchorMap(map);
                                      widget.centralServerService.registerAnchorNetwork(map);
                                      final host = widget.storageService.getServerHost();
                                      final port = widget.storageService.getServerPort();
                                      if (host.isNotEmpty) {
                                        await widget.centralServerService.sendAnchorNetworkToServer(
                                          serverHost: host,
                                          serverPort: port,
                                          map: map,
                                        );
                                      }
                                      final myCoord = map.anchors.where((a) => a.anchorId == anchorId);
                                      if (myCoord.isNotEmpty) {
                                        await widget.storageService.setAnchorCoordinates(myCoord.first.x, myCoord.first.y);
                                      }
                                      _sendHeartbeat();
                                      setState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Fixed points re-calibrated & synced to server!'),
                                          backgroundColor: AppColors.success,
                                        ),
                                      );
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Need at least 2 active peer anchors to re-solve.')),
                                      );
                                    }
                                  },
                                  icon: const Icon(Icons.refresh_rounded, size: 16),
                                  label: const Text('RE-CALIBRATE & SYNC'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryAccent,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                                    textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Expanded(
                              flex: 2,
                              child: SizedBox(
                                height: 42,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await widget.measurementRepository.recalibrateAnchorMap();
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Fixed anchor grid reset. Zero cached coordinates.')),
                                    );
                                  },
                                  icon: const Icon(Icons.delete_outline_rounded, size: 16, color: AppColors.error),
                                  label: const Text('RESET', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.error),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      else
                        SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final map = widget.measurementRepository.solveCoordinates();
                              if (map != null) {
                                await widget.measurementRepository.acceptAndLockAnchorMap(map);
                                widget.centralServerService.registerAnchorNetwork(map);
                                final host = widget.storageService.getServerHost();
                                final port = widget.storageService.getServerPort();
                                if (host.isNotEmpty) {
                                  await widget.centralServerService.sendAnchorNetworkToServer(
                                    serverHost: host,
                                    serverPort: port,
                                    map: map,
                                  );
                                }
                                final myCoord = map.anchors.where((a) => a.anchorId == anchorId);
                                if (myCoord.isNotEmpty) {
                                  await widget.storageService.setAnchorCoordinates(myCoord.first.x, myCoord.first.y);
                                }
                                _sendHeartbeat();
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Fixed Anchor Points Solved & Synced to Central Server!'),
                                    backgroundColor: AppColors.success,
                                  ),
                                );
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Need at least 2 active peer anchors to solve fixed points.')),
                                );
                              }
                            },
                            icon: const Icon(Icons.lock_outline_rounded, size: 16),
                            label: const Text('AUTO-CALIBRATE & LOCK FIXED POINTS'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryAccent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // 4. Detected Central / Tracked Devices in this room
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'DETECTED MOBILE DEVICES',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.0,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: trackedDevices.isNotEmpty ? AppColors.successSubtle : AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                            ),
                            child: Text(
                              '${trackedDevices.length} in range',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: trackedDevices.isNotEmpty ? AppColors.success : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (trackedDevices.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 20.0),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.radar_rounded, size: 32, color: AppColors.border),
                                const SizedBox(height: 8),
                                const Text(
                                  'Listening for mobile devices entering this room...',
                                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: trackedDevices.length,
                          separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 16),
                          itemBuilder: (context, idx) {
                            final dev = trackedDevices[idx];
                            final dist = widget.measurementRepository.getDistanceToDevice(dev.deviceId);
                            final rssi = dev.rawRssiHistory.isNotEmpty ? dev.rawRssiHistory.last : -100;

                            return Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.successSubtle,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.phone_android_rounded, size: 16, color: AppColors.success),
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dev.friendlyName,
                                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          'RSSI: $rssi dBm  •  Room A',
                                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceHighlight,
                                    borderRadius: BorderRadius.circular(AppRadii.sm),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Text(
                                    '${dist.toStringAsFixed(2)} m',
                                    style: const TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricItem(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
