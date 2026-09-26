import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';

class OrientationView extends StatefulWidget {
  final MeasurementRepository measurementRepository;

  const OrientationView({
    super.key,
    required this.measurementRepository,
  });

  @override
  State<OrientationView> createState() => _OrientationViewState();
}

class _OrientationViewState extends State<OrientationView> {
  String? _selectedTargetDeviceId;
  double _testDistance = 1.0;
  String _selectedOrientation = "0°";
  int _testDurationSeconds = 15;

  final List<String> _orientations = ["0°", "90°", "180°", "270°"];
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

        final List<TestSummary> orientationRuns = widget.measurementRepository.testSummaries
            .where((s) => s.testType == "Orientation")
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
              _buildRunsHistoryCard(orientationRuns),
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
                Icon(Icons.explore_rounded, color: Color(0xFF00F0FF)),
                SizedBox(width: 12),
                Text(
                  'ORIENTATION TEST INSTRUCTIONS',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'The purpose of this test is to analyze the directional dependency of BLE signals due to phone antennas and human body shading.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const BulletPoint(text: 'Keep the transmitter and scanner phones at a fixed physical distance.'),
            const BulletPoint(text: 'Rotate the receiving phone to 0°, 90°, 180°, and 270°.'),
            const BulletPoint(text: 'Run the test for 10-15s for each orientation and compare the median RSSI values.'),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupCard(List<BleDevice> devices, bool isTesting, String activeType) {
    final bool currentRunning = isTesting && activeType == "Orientation";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ORIENTATION TEST CONFIGURATION',
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

              // Orientation selection
              const Text('Select Phone Orientation:', style: TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: _orientations.map((orientation) {
                  final bool isSelected = _selectedOrientation == orientation;
                  return ChoiceChip(
                    label: Text(orientation),
                    selected: isSelected,
                    selectedColor: const Color(0xFF00F0FF).withOpacity(0.15),
                    backgroundColor: const Color(0xFF0F0F13),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFF00F0FF) : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSelected ? const Color(0xFF00F0FF) : Colors.white10),
                    ),
                    onSelected: currentRunning
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _selectedOrientation = orientation;
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
                      color: const Color(0xFF00F0FF),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Measuring orientation $_selectedOrientation...',
                          style: TextStyle(color: const Color(0xFF00F0FF).withOpacity(0.8), fontSize: 13),
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
                        testType: "Orientation",
                        targetDeviceId: _selectedTargetDeviceId!,
                        actualDistance: _testDistance,
                        orientation: _selectedOrientation,
                        obstruction: "None",
                        durationSeconds: _testDurationSeconds,
                      );
                    },
                    child: const Text('START ORIENTATION TEST'),
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
              'ORIENTATION TEST RUN HISTORIES',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'No orientation test runs recorded yet.',
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
                    DataColumn(label: Text('Orientation')),
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
                              color: const Color(0xFFD946EF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              run.orientation,
                              style: const TextStyle(color: Color(0xFFD946EF), fontWeight: FontWeight.bold, fontSize: 11),
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

class BulletPoint extends StatelessWidget {
  final String text;
  const BulletPoint({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6.0, right: 8.0, left: 4.0),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF00F0FF)),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, color: Colors.white60),
            ),
          ),
        ],
      ),
    );
  }
}
