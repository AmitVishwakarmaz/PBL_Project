import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/app_theme.dart';
import 'widgets/expandable_text.dart';

class CalibrationView extends StatefulWidget {
  final StorageService storageService;
  final MeasurementRepository measurementRepository;
  final ScrollController? scrollController;

  const CalibrationView({
    super.key,
    required this.storageService,
    required this.measurementRepository,
    this.scrollController,
  });

  @override
  State<CalibrationView> createState() => _CalibrationViewState();
}

class _CalibrationViewState extends State<CalibrationView> {
  String? _selectedDeviceId;
  bool _isCalibrating = false;

  void _showEnvironmentInfoDialog() {
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
          title: const Row(
            children: [
              Icon(Icons.info_outline_rounded, color: AppColors.primaryAccent, size: 20),
              SizedBox(width: 8),
              Text('Room Environment (n)', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'In wireless physics, "n" (Path Loss Exponent) tells the system how quickly Bluetooth signals weaken in this room:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
              ),
              SizedBox(height: 14),
              Text('🏛 Open Hall (n = 2.0)', style: TextStyle(color: AppColors.primaryAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Large open spaces, halls, or corridors with minimal furniture and no walls.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              SizedBox(height: 10),
              Text('🚪 Normal Room (n = 2.4) [Default]', style: TextStyle(color: AppColors.success, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Typical indoor spaces like classrooms, labs, and offices with standard furniture.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              SizedBox(height: 10),
              Text('🧱 Dense / Walls (n = 2.8)', style: TextStyle(color: AppColors.warning, fontSize: 13, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Rooms with concrete pillars, glass partitions, heavy machinery, or dense human crowds.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
              ),
              child: const Text('Got It'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.measurementRepository,
      builder: (context, _) {
        final List<BleDevice> devices = widget.measurementRepository.devices
            .where((d) => d.rawRssiHistory.isNotEmpty)
            .toList();

        if (_selectedDeviceId == null && devices.isNotEmpty) {
          _selectedDeviceId = devices.first.deviceId;
        }

        final double currentRssi0 = widget.storageService.getRssi0();
        final double currentN = widget.storageService.getPathLossN();

        // Get live distance to selected device
        double liveDist = 0.0;
        int liveRssi = -100;
        if (_selectedDeviceId != null) {
          liveDist = widget.measurementRepository.getDistanceToDevice(_selectedDeviceId!);
          final dev = widget.measurementRepository.devices.firstWhere(
            (d) => d.deviceId == _selectedDeviceId,
            orElse: () => devices.first,
          );
          if (dev.rawRssiHistory.isNotEmpty) {
            liveRssi = dev.rawRssiHistory.last;
          }
        }

        return Scaffold(
          backgroundColor: AppColors.surface,
          appBar: AppBar(
            backgroundColor: AppColors.surface,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Distance Calibration',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await widget.storageService.setRssi0(-64.0);
                  await widget.storageService.setPathLossN(2.4);
                  await widget.storageService.setD0(1.0);
                  widget.measurementRepository.reloadConfig();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Reset to safe defaults (-64 dBm, n=2.4)')),
                    );
                  }
                },
                child: const Text('Reset', style: TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          body: ListView(
            controller: widget.scrollController,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
            children: [
              const ExpandableText(
                text: 'Accurate indoor BLE distance requires matching your phone’s 1-meter RSSI signal. Calibration is quick and simple:',
                maxLines: 2,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                linkColor: AppColors.primaryAccent,
              ),
              const SizedBox(height: AppSpacing.md),

              // Target Device Dropdown
              if (devices.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warningSubtle,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No nearby BLE devices found. Ensure another phone is broadcasting as Anchor or Test device.',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                DropdownButtonFormField<String>(
                  value: _selectedDeviceId,
                  decoration: const InputDecoration(
                    labelText: 'Target Device to Calibrate Against',
                  ),
                  dropdownColor: AppColors.surfaceHighlight,
                  items: devices.map((d) {
                    return DropdownMenuItem<String>(
                      value: d.deviceId,
                      child: Text(
                        '${d.friendlyName} (${d.deviceId})',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedDeviceId = val),
                ),
              const SizedBox(height: AppSpacing.md),

              // Step 1: 1-Meter Calibration
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Expanded(
                          child: Text(
                            'STEP 1: 1-METER BASELINE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.8,
                              color: AppColors.primaryAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primaryAccentSubtle,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            '1m: ${currentRssi0.toStringAsFixed(1)} dBm',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primaryAccent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const ExpandableText(
                      text: 'Hold this phone exactly 1.0 meter away from the selected device, then tap the button below to sample your phone antenna:',
                      maxLines: 2,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                      linkColor: AppColors.primaryAccent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: devices.isEmpty || _isCalibrating ? null : () async {
                          if (_selectedDeviceId == null) return;
                          setState(() => _isCalibrating = true);
                          try {
                            await widget.measurementRepository.calibrateAtOneMeter(_selectedDeviceId!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Calibrated 1m RSSI to ${widget.storageService.getRssi0().toStringAsFixed(1)} dBm!'),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Calibration error: $e')),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _isCalibrating = false);
                          }
                        },
                        icon: _isCalibrating
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.gps_fixed_rounded, size: 18),
                        label: Text(_isCalibrating ? 'SAMPLING RSSI...' : 'CALIBRATE AT 1 METER'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          elevation: 0,
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Step 2: Environment Preset
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
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
                              const Flexible(
                                child: Text(
                                  'STEP 2: ENVIRONMENT',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: AppColors.primaryAccent,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.info_outline_rounded, color: AppColors.primaryAccent, size: 16),
                                tooltip: 'What is Room Environment (n)?',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                onPressed: _showEnvironmentInfoDialog,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.successSubtle,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          child: Text(
                            'n = ${currentN.toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.success),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const ExpandableText(
                      text: 'Pick your room type so distance calculation accurately accounts for radio signal fade through walls and furniture:',
                      maxLines: 2,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
                      linkColor: AppColors.primaryAccent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        _buildPresetButton('Open Hall', 2.0, currentN),
                        const SizedBox(width: AppSpacing.xs),
                        _buildPresetButton('Normal Room', 2.4, currentN),
                        const SizedBox(width: AppSpacing.xs),
                        _buildPresetButton('Dense / Walls', 2.8, currentN),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Step 3: Live Verification Meter
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceHighlight,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'LIVE DISTANCE VERIFICATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                            color: AppColors.primaryAccent,
                          ),
                        ),
                        Text(
                          'Real-Time',
                          style: TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${liveDist > 0 ? liveDist.toStringAsFixed(2) : "--"} m',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                        letterSpacing: -1.0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Live RSSI: $liveRssi dBm  •  Clamped physically: 0.2m - 15.0m',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      child: LinearProgressIndicator(
                        value: (liveDist / 10.0).clamp(0.0, 1.0),
                        backgroundColor: AppColors.surfaceSubtle,
                        color: AppColors.primaryAccent,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    const Text(
                      'Walk to 2m or 3m to observe live distance calculation stability.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPresetButton(String label, double value, double currentN) {
    final bool isSelected = (currentN - value).abs() < 0.15;

    return Expanded(
      child: OutlinedButton(
        onPressed: () async {
          await widget.measurementRepository.setPathLossEnvironment(value);
        },
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
          backgroundColor: isSelected ? AppColors.primaryAccentSubtle : Colors.transparent,
          side: BorderSide(
            color: isSelected ? AppColors.primaryAccent : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primaryAccent : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'n=$value',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primaryAccent : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
