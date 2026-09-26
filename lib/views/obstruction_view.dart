import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
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
  int _testDurationSeconds = 15;

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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Instructions Card
              _buildInstructionsCard(),
              const SizedBox(height: 16),

              // Setup Card
              _buildSetupCard(devices, isTesting, activeType),
              const SizedBox(height: 24),

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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.block_rounded, color: Color(0xFF00F0FF)),
                SizedBox(width: 12),
                Text(
                  'OBSTRUCTION TEST INSTRUCTIONS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'This test quantifies how different environmental barriers absorb/reflect BLE signals, which helps determine threshold safety margins for the trilateration positioning algorithm.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 8),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OBSTRUCTION TEST CONFIGURATION',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFFD946EF)),
            ),
            const SizedBox(height: 16),
            if (devices.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'No nearby transmitters detected. Turn on scanning and advertising first.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
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
                  border: OutlineInputBorder(),
                ),
                dropdownColor: const Color(0xFF171721),
                items: devices.map((d) {
                  return DropdownMenuItem<String>(
                    value: d.deviceId,
                    child: Text('${d.friendlyName} (${d.deviceId})'),
                  );
                }).toList(),
                onChanged: currentRunning ? null : (val) => setState(() => _selectedTargetDeviceId = val),
              ),
              const SizedBox(height: 16),

              // Fixed distance selection
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Fixed Test Distance: ', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(width: 8),
                  DropdownButton<double>(
                    value: _testDistance,
                    dropdownColor: const Color(0xFF171721),
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
              const SizedBox(height: 16),

              // Obstruction selection
              const Text('Select Obstruction Type:', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _obstructions.map((obs) {
                  final bool isSelected = _selectedObstruction == obs;
                  return ChoiceChip(
                    label: Text(obs),
                    selected: isSelected,
                    selectedColor: const Color(0xFFD946EF).withOpacity(0.15),
                    backgroundColor: const Color(0xFF0F0F13),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFFD946EF) : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSelected ? const Color(0xFFD946EF) : Colors.white10),
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
              const SizedBox(height: 20),

              // Action button or progress
              if (currentRunning) ...[
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: (widget.measurementRepository.activeDurationSeconds - widget.measurementRepository.testSecondsRemaining) / widget.measurementRepository.activeDurationSeconds,
                      backgroundColor: Colors.white12,
                      color: const Color(0xFFD946EF),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Measuring obstruction $_selectedObstruction...',
                          style: TextStyle(color: const Color(0xFFD946EF).withOpacity(0.8), fontSize: 13),
                        ),
                        Text(
                          '${widget.measurementRepository.testSecondsRemaining}s left',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => widget.measurementRepository.stopActiveTest(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: const BorderSide(color: Colors.redAccent, width: 1.5),
                        ),
                        child: const Text('STOP COLLECTING'),
                      ),
                    ),
                  ],
                ),
              ] else if (isTesting) ...[
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      'Another test (${widget.measurementRepository.activeTestType}) is currently active.',
                      style: const TextStyle(color: Colors.white24, fontStyle: FontStyle.italic),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD946EF),
                      foregroundColor: Colors.white,
                    ),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OBSTRUCTION TEST RUN HISTORIES',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'No obstruction test runs recorded yet.',
                    style: TextStyle(color: Colors.white24, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 24,
                  headingRowColor: MaterialStateProperty.all(const Color(0xFF0F0F13)),
                  columns: const [
                    DataColumn(label: Text('Target Device')),
                    DataColumn(label: Text('Distance')),
                    DataColumn(label: Text('Obstruction')),
                    DataColumn(label: Text('Samples')),
                    DataColumn(label: Text('Median RSSI')),
                    DataColumn(label: Text('Mean RSSI')),
                    DataColumn(label: Text('Std Dev')),
                  ],
                  rows: runs.map((run) {
                    return DataRow(
                      cells: [
                        DataCell(Text(run.targetDeviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)))),
                        DataCell(Text('${run.actualDistance.toStringAsFixed(1)} m')),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00F0FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              run.obstruction,
                              style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ),
                        DataCell(Text('${run.sampleCount}')),
                        DataCell(Text('${run.medianRssi.toStringAsFixed(1)} dBm')),
                        DataCell(Text('${run.meanRssi.toStringAsFixed(1)} dBm')),
                        DataCell(Text(run.rssiStdDev.toStringAsFixed(2))),
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
