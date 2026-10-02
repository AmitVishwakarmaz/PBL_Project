import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/storage_service.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/distance_estimator.dart';
import '../utils/app_theme.dart';

class DashboardView extends StatefulWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;

  const DashboardView({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
  });

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  bool _permissionsGranted = false;
  Map<Permission, PermissionStatus> _permissionStatuses = {};

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  List<Permission> get _requiredPermissions {
    if (Platform.isIOS) {
      return [
        Permission.bluetooth,
      ];
    }
    return [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
    ];
  }

  Future<void> _checkPermissions() async {
    final Map<Permission, PermissionStatus> statuses = {};
    for (var permission in _requiredPermissions) {
      statuses[permission] = await permission.status;
    }

    final allGranted = statuses.values.every((status) => status.isGranted);

    setState(() {
      _permissionStatuses = statuses;
      _permissionsGranted = allGranted;
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await _requiredPermissions.request();

    final allGranted = statuses.values.every((status) => status.isGranted);

    setState(() {
      _permissionStatuses = statuses;
      _permissionsGranted = allGranted;
    });

    if (!allGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Some permissions were denied. BLE operations may fail.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showEditDeviceDialog() {
    final friendlyController = TextEditingController(text: widget.storageService.getFriendlyName());
    final indexController = TextEditingController(text: widget.storageService.getDeviceIndex().toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: const Text('Edit Device Identity', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: friendlyController,
                decoration: const InputDecoration(
                  labelText: 'Friendly Name',
                  hintText: 'e.g. Phone A',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: indexController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Device Index (e.g. 1 for TEST-A001)',
                  hintText: 'e.g. 1',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () async {
                final int? newIndex = int.tryParse(indexController.text);
                if (newIndex != null && newIndex > 0) {
                  await widget.storageService.setFriendlyName(friendlyController.text);
                  await widget.storageService.setDeviceIndex(newIndex);
                  
                  // Reload configurations
                  widget.measurementRepository.reloadConfig();
                  
                  // Restart advertising if active
                  if (widget.bleAdvertiser.isAdvertising) {
                    await widget.bleAdvertiser.stopAdvertising();
                    await widget.bleAdvertiser.startAdvertising();
                  }

                  setState(() {});
                  if (mounted) Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid numeric device index.')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWideScreen = MediaQuery.of(context).size.width > 600;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.bleAdvertiser,
        widget.bleScanner,
        widget.measurementRepository,
      ]),
      builder: (context, _) {
        final List<BleDevice> scannedDevices = widget.measurementRepository.devices;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Status Overview Row
              _buildPermissionsAndBluetoothCard(),
              const SizedBox(height: 16),

              // 2. Identity & Path Loss Parameters Card
              _buildDeviceIdentityCard(),
              const SizedBox(height: 16),

              // 3. Advertising & Scanning Toggle Cards
              isWideScreen
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildAdvertiserCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildScannerCard()),
                      ],
                    )
                  : Column(
                      children: [
                        _buildAdvertiserCard(),
                        const SizedBox(height: 16),
                        _buildScannerCard(),
                      ],
                    ),
              const SizedBox(height: 24),

              // 4. Live Scanned Devices Table Card
              _buildLiveScannedDevicesTable(scannedDevices),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPermissionsAndBluetoothCard() {
    final bool isBtOn = widget.bleScanner.isBluetoothOn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SYSTEM STATUS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
                _buildStatusIndicator(isBtOn, isBtOn ? 'Bluetooth ON' : 'Bluetooth OFF'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!_permissionsGranted) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.errorSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(
                      child: Text(
                        'BLE Permissions are missing! Scanning and advertising will fail.',
                        style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      ),
                    ),
                    TextButton(
                      onPressed: _requestPermissions,
                      child: const Text('GRANT', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryAccent)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            // Show individual permissions
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: _permissionStatuses.entries.map((entry) {
                final String name = entry.key.toString().replaceAll('Permission.', '').toUpperCase();
                final bool isGranted = entry.value.isGranted;
                return Chip(
                  avatar: Icon(
                    isGranted ? Icons.check_circle : Icons.cancel,
                    size: 14,
                    color: isGranted ? AppColors.success : AppColors.textTertiary,
                  ),
                  label: Text(
                    name,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isGranted ? AppColors.textPrimary : AppColors.textTertiary,
                    ),
                  ),
                  backgroundColor: AppColors.surfaceSubtle,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    side: BorderSide(color: isGranted ? AppColors.borderStrong : AppColors.border),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceIdentityCard() {
    final String deviceId = widget.storageService.getDeviceId();
    final String friendlyName = widget.storageService.getFriendlyName();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOCAL IDENTITY',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        friendlyName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          deviceId,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier',
                            color: AppColors.primaryAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _showEditDeviceDialog,
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: const Text('EDIT'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvertiserCard() {
    final bool isAdv = widget.bleAdvertiser.isAdvertising;
    final int packets = widget.bleAdvertiser.packetsSent;
    final int seq = widget.bleAdvertiser.sequenceNumber;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ADVERTISER',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary),
                ),
                _buildStatusIndicator(isAdv, isAdv ? 'ACTIVE' : 'IDLE'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Packets sent: $packets', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Sequence number: $seq', style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: isAdv
                  ? OutlinedButton(
                      onPressed: () => widget.bleAdvertiser.stopAdvertising(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error, width: 1.0),
                      ),
                      child: const Text('STOP ADVERTISING'),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        try {
                          await widget.bleAdvertiser.startAdvertising();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: ${e.toString()}')),
                          );
                        }
                      },
                      child: const Text('START ADVERTISING'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerCard() {
    final bool isScan = widget.bleScanner.isScanning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SCANNER',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary),
                ),
                _buildStatusIndicator(isScan, isScan ? 'SCANNING' : 'IDLE'),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Devices detected: ${widget.measurementRepository.devices.length}',
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 24),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: isScan
                  ? OutlinedButton(
                      onPressed: () => widget.bleScanner.stopScanning(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error, width: 1.0),
                      ),
                      child: const Text('STOP SCANNING'),
                    )
                  : ElevatedButton(
                      onPressed: () async {
                        try {
                          await widget.bleScanner.startScanning();
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed: ${e.toString()}')),
                          );
                        }
                      },
                      child: const Text('START SCANNING'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveScannedDevicesTable(List<BleDevice> scannedDevices) {
    final RssiProcessor processor = RssiProcessor();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LIVE DETECTED TEST DEVICES',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    '${scannedDevices.length} Online',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (scannedDevices.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(Icons.radar_outlined, size: 40, color: AppColors.textTertiary.withOpacity(0.6)),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'No test packets detected yet.\nEnsure other devices are actively advertising.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 18,
                  headingRowColor: MaterialStateProperty.all(AppColors.surfaceSubtle),
                  columns: const [
                    DataColumn(label: Text('Device ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Friendly Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Raw RSSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Median', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Average', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Est Dist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Seq Num', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                  ],
                  rows: scannedDevices.map((device) {
                    final stats = device.getStats(processor);
                    final double estDist = device.getEstimatedDistance(
                      processor,
                      DistanceEstimator(
                        d0: widget.storageService.getD0(),
                        rssi0: widget.storageService.getRssi0(),
                        n: widget.storageService.getPathLossN(),
                      ),
                    );

                    return DataRow(
                      cells: [
                        DataCell(Text(device.deviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: AppColors.primaryAccent))),
                        DataCell(Text(device.friendlyName, style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(
                          Text(
                            device.rawRssiHistory.isNotEmpty ? '${device.rawRssiHistory.last} dBm' : 'N/A',
                            style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                          ),
                        ),
                        DataCell(Text('${stats.sampleCount}', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text(stats.sampleCount > 0 ? '${stats.median.toStringAsFixed(1)}' : 'N/A', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text(stats.sampleCount > 0 ? '${stats.mean.toStringAsFixed(1)}' : 'N/A', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(
                          Text(
                            stats.sampleCount > 0 ? stats.stdDev.toStringAsFixed(2) : 'N/A',
                            style: TextStyle(
                              color: stats.stdDev > 5.0 ? AppColors.primaryAccent : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            stats.sampleCount > 0 ? '${estDist.toStringAsFixed(2)} m' : 'N/A',
                            style: const TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(device.lastSequenceNumber != null ? '${device.lastSequenceNumber}' : '-', style: const TextStyle(color: AppColors.textSecondary))),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool active, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? AppColors.success : AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: active ? AppColors.textPrimary : AppColors.textTertiary,
          ),
        ),
      ],
    );
  }
}
