import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/app_theme.dart';
import 'orientation_view.dart'; // Import BulletPoint helper

class ObstructionView extends StatefulWidget {
  final MeasurementRepository measurementRepository;

  const ObstructionView({
    super.key,
    required this.measurementRepository,
  });

  @override
  State<ObstructionView> createState() => _ObstructionViewState();
}

class _ObstructionViewState extends State<ObstructionView> {
  String? _selectedTargetDeviceId;
  double _testDistance = 1.0;
  String _selectedObstruction = "None";
  final int _testDurationSeconds = 15;

  final List<String> _obstructions = ["None", "Person", "Door/Wall", "Pocket", "Hand"];
  final List<double> _presetDistances = [1.0, 2.0, 3.0, 5.0];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.measurementRepository,
      builder: (context, _) {
        final List<BleDevice> devices = widget.measurementRepository.devices;
        final bool isTesting = widget.measurementRepository.isTestActive;
        final String activeType = widget.measurementRepository.activeTestType;

        if (_selectedTargetDeviceId == null && devices.isNotEmpty) {
          _selectedTargetDeviceId = devices.first.deviceId;
        }

        final List<TestSummary> obstructionRuns = widget.measurementRepository.testSummaries
            .where((s) => s.testType == "Obstruction")
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions Card
              _buildInstructionsCard(),
              const SizedBox(height: AppSpacing.md),

              // Setup Card
              _buildSetupCard(devices, isTesting, activeType),
              const SizedBox(height: AppSpacing.md),

              // Runs History
              _buildRunsHistoryCard(obstructionRuns),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.block_outlined, color: AppColors.primaryAccent, size: 20),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'OBSTRUCTION TEST INSTRUCTIONS',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'This test quantifies how different environmental barriers absorb/reflect BLE signals, which helps determine threshold safety margins for the trilateration positioning algorithm.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xs),
            const BulletPoint(text: 'Select the target transmitting phone and fixed testing distance.'),
            const BulletPoint(text: 'Place the phone in the designated environment (e.g. pocket, hand, behind a door).'),
            const BulletPoint(text: 'Collect data for 10-15s and analyze the RSSI attenuation (signal loss in dBm) compared to "None" (Line-of-Sight).'),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupCard(List<BleDevice> devices, bool isTesting, String activeType) {
    final bool currentRunning = isTesting && activeType == "Obstruction";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OBSTRUCTION TEST CONFIGURATION',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
            ),
            const SizedBox(height: AppSpacing.md),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.primaryAccent, size: 20),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'No nearby transmitters detected. Turn on scanning and advertising first.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Device Selector
              DropdownButtonFormField<String>(
                value: _selectedTargetDeviceId,
                decoration: const InputDecoration(
                  labelText: 'Target Transmitting Device',
                ),
                dropdownColor: AppColors.surface,
                items: devices.map((d) {
                  return DropdownMenuItem<String>(
                    value: d.deviceId,
                    child: Text('${d.friendlyName} (${d.deviceId})'),
                  );
                }).toList(),
                onChanged: currentRunning ? null : (val) => setState(() => _selectedTargetDeviceId = val),
              ),
              const SizedBox(height: AppSpacing.md),

              // Fixed distance selection
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Fixed Test Distance: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: AppSpacing.xs),
                  DropdownButton<double>(
                    value: _testDistance,
                    dropdownColor: AppColors.surface,
                    items: _presetDistances.map((d) {
                      return DropdownMenuItem<double>(
                        value: d,
                        child: Text('${d.toStringAsFixed(1)} m'),
                      );
                    }).toList(),
                    onChanged: currentRunning ? null : (val) => setState(() => _testDistance = val!),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Obstruction selection
              const Text('Select Obstruction Type:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: _obstructions.map((obs) {
                  final bool isSelected = _selectedObstruction == obs;
                  return ChoiceChip(
                    label: Text(obs),
                    selected: isSelected,
                    selectedColor: AppColors.primaryAccentSubtle,
                    backgroundColor: AppColors.surfaceSubtle,
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primaryAccent : AppColors.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                      side: BorderSide(color: isSelected ? AppColors.primaryAccent : AppColors.border),
                    ),
                    onSelected: currentRunning
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _selectedObstruction = obs;
                              });
                            }
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // Action button or progress
              if (currentRunning) ...[
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: (widget.measurementRepository.activeDurationSeconds - widget.measurementRepository.testSecondsRemaining) / widget.measurementRepository.activeDurationSeconds,
                      backgroundColor: AppColors.surfaceSubtle,
                      color: AppColors.primaryAccent,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Measuring obstruction $_selectedObstruction...',
                          style: const TextStyle(color: AppColors.primaryAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${widget.measurementRepository.testSecondsRemaining}s left',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => widget.measurementRepository.stopActiveTest(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error, width: 1.0),
                        ),
                        child: const Text('STOP COLLECTING'),
                      ),
                    ),
                  ],
                ),
              ] else if (isTesting) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: Text(
                      'Another test (${widget.measurementRepository.activeTestType}) is currently active.',
                      style: const TextStyle(color: AppColors.textTertiary, fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_selectedTargetDeviceId == null) return;
                      widget.measurementRepository.startTest(
                        testType: "Obstruction",
                        targetDeviceId: _selectedTargetDeviceId!,
                        actualDistance: _testDistance,
                        orientation: "0°",
                        obstruction: _selectedObstruction,
                        durationSeconds: _testDurationSeconds,
                      );
                    },
                    child: const Text('START OBSTRUCTION TEST'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRunsHistoryCard(List<TestSummary> runs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OBSTRUCTION TEST RUN HISTORIES',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    'No obstruction test runs recorded yet.',
                    style: TextStyle(color: AppColors.textTertiary, fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: MaterialStateProperty.all(AppColors.surfaceSubtle),
                  columns: const [
                    DataColumn(label: Text('Target Device', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Obstruction', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Median RSSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Mean RSSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                  ],
                  rows: runs.map((run) {
                    return DataRow(
                      cells: [
                        DataCell(Text(run.targetDeviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: AppColors.primaryAccent))),
                        DataCell(Text('${run.actualDistance.toStringAsFixed(1)} m', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceSubtle,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              run.obstruction,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                        DataCell(Text('${run.sampleCount}', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${run.medianRssi.toStringAsFixed(1)} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${run.meanRssi.toStringAsFixed(1)} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text(run.rssiStdDev.toStringAsFixed(2), style: const TextStyle(color: AppColors.textSecondary))),
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
}
