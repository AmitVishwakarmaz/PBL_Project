import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../services/storage_service.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/distance_estimator.dart';

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

  Future<void> _checkPermissions() async {
    final Map<Permission, PermissionStatus> statuses = {};
    for (var permission in [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ]) {
      statuses[permission] = await permission.status;
    }

    final allGranted = statuses.values.every((status) => status.isGranted);

    setState(() {
      _permissionStatuses = statuses;
      _permissionsGranted = allGranted;
    });
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

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
            backgroundColor: Colors.redAccent,
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
          backgroundColor: const Color(0xFF171721),
          title: const Text('Edit Device Identity', style: TextStyle(fontFamily: 'Outfit')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: friendlyController,
                decoration: const InputDecoration(
                  labelText: 'Friendly Name',
                  hintText: 'e.g. Phone A',
                  labelStyle: TextStyle(color: Color(0xFF00F0FF)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F0FF))),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: indexController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Device Index (e.g. 1 for TEST-A001)',
                  hintText: 'e.g. 1',
                  labelStyle: TextStyle(color: Color(0xFF00F0FF)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00F0FF))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SYSTEM STATUS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFFD946EF)),
                ),
                _buildStatusIndicator(isBtOn, isBtOn ? 'Bluetooth ON' : 'Bluetooth OFF'),
              ],
            ),
            const SizedBox(height: 12),
            if (!_permissionsGranted) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'BLE Permissions are missing! Scanning and advertising will fail.',
                        style: TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                    TextButton(
                      onPressed: _requestPermissions,
                      child: const Text('GRANT'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Show individual permissions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _permissionStatuses.entries.map((entry) {
                final String name = entry.key.toString().replaceAll('Permission.', '').toUpperCase();
                final bool isGranted = entry.value.isGranted;
                return Chip(
                  avatar: Icon(
                    isGranted ? Icons.check_circle : Icons.cancel,
                    size: 16,
                    color: isGranted ? const Color(0xFF00F0FF) : Colors.white24,
                  ),
                  label: Text(name, style: const TextStyle(fontSize: 10)),
                  backgroundColor: const Color(0xFF0F0F13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: isGranted ? const Color(0xFF00F0FF).withOpacity(0.2) : Colors.white10),
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
        padding: const EdgeInsets.all(16.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LOCAL IDENTITY',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        friendlyName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00F0FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.3)),
                        ),
                        child: Text(
                          deviceId,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Courier',
                            color: Color(0xFF00F0FF),
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
              icon: const Icon(Icons.edit_rounded, size: 16),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ADVERTISER',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
                ),
                _buildStatusIndicator(isAdv, isAdv ? 'ACTIVE' : 'IDLE'),
              ],
            ),
            const SizedBox(height: 16),
            Text('Packets sent: $packets', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 4),
            Text('Sequence number: $seq', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: isAdv
                  ? OutlinedButton(
                      onPressed: () => widget.bleAdvertiser.stopAdvertising(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SCANNER',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
                ),
                _buildStatusIndicator(isScan, isScan ? 'SCANNING' : 'IDLE'),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Devices detected: ${widget.measurementRepository.devices.length}',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 24), // Spacer to align buttons
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: isScan
                  ? OutlinedButton(
                      onPressed: () => widget.bleScanner.stopScanning(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent, width: 1.5),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LIVE DETECTED TEST DEVICES',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                ),
                Text(
                  '${scannedDevices.length} Online',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (scannedDevices.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Column(
                    children: [
                      Icon(Icons.radar_rounded, size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text(
                        'No test packets detected yet.\nEnsure other devices are actively advertising.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: MaterialStateProperty.all(const Color(0xFF0F0F13)),
                  columns: const [
                    DataColumn(label: Text('Device ID', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Friendly Name', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Raw RSSI', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Median', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Average', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Est Dist', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Seq Num', style: TextStyle(fontWeight: FontWeight.bold))),
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
                        DataCell(Text(device.deviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)))),
                        DataCell(Text(device.friendlyName)),
                        DataCell(
                          Text(
                            device.rawRssiHistory.isNotEmpty ? '${device.rawRssiHistory.last} dBm' : 'N/A',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        DataCell(Text('${stats.sampleCount}')),
                        DataCell(Text(stats.sampleCount > 0 ? '${stats.median.toStringAsFixed(1)}' : 'N/A')),
                        DataCell(Text(stats.sampleCount > 0 ? '${stats.mean.toStringAsFixed(1)}' : 'N/A')),
                        DataCell(
                          Text(
                            stats.sampleCount > 0 ? stats.stdDev.toStringAsFixed(2) : 'N/A',
                            style: TextStyle(
                              color: stats.stdDev > 5.0 ? Colors.orangeAccent : const Color(0xFF00F0FF),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            stats.sampleCount > 0 ? '${estDist.toStringAsFixed(2)} m' : 'N/A',
                            style: const TextStyle(color: Color(0xFFD946EF), fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(device.lastSequenceNumber != null ? '${device.lastSequenceNumber}' : '-')),
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
            color: active ? const Color(0xFF00F0FF) : Colors.white24,
            boxShadow: active
                ? [
                    const BoxShadow(
                      color: Color(0xFF00F0FF),
                      blurRadius: 6,
                      spreadRadius: 1,
                    )
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : Colors.white30,
          ),
        ),
      ],
    );
  }
}
