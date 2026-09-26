import 'package:flutter/material.dart';

import '../services/storage_service.dart';
import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/distance_estimator.dart';

class CalibrationView extends StatefulWidget {
  final StorageService storageService;
  final MeasurementRepository measurementRepository;

  const CalibrationView({
    super.key,
    required this.storageService,
    required this.measurementRepository,
  });

  @override
  State<CalibrationView> createState() => _CalibrationViewState();
}

class _CalibrationViewState extends State<CalibrationView> {
  final _d0Controller = TextEditingController();
  final _rssi0Controller = TextEditingController();
  final _nController = TextEditingController();

  String? _selectedTargetDeviceId;
  double _selectedDistance = 1.0;
  int _testDurationSeconds = 15;

  final List<double> _presetDistances = [1.0, 2.0, 3.0, 5.0, 7.0, 10.0];

  @override
  void initState() {
    super.initState();
    _loadConfigValues();
  }

  void _loadConfigValues() {
    _d0Controller.text = widget.storageService.getD0().toString();
    _rssi0Controller.text = widget.storageService.getRssi0().toString();
    _nController.text = widget.storageService.getPathLossN().toString();
  }

  Future<void> _saveConfigValues() async {
    final double? d0 = double.tryParse(_d0Controller.text);
    final double? rssi0 = double.tryParse(_rssi0Controller.text);
    final double? n = double.tryParse(_nController.text);

    if (d0 != null && rssi0 != null && n != null) {
      await widget.storageService.setD0(d0);
      await widget.storageService.setRssi0(rssi0);
      await widget.storageService.setPathLossN(n);
      
      widget.measurementRepository.reloadConfig();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Path-loss parameters updated successfully.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid numeric parameters.')),
      );
    }
  }

  void _startCalibrationTest() {
    if (_selectedTargetDeviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a target device to calibrate.')),
      );
      return;
    }

    widget.measurementRepository.startTest(
      testType: "Calibration",
      targetDeviceId: _selectedTargetDeviceId!,
      actualDistance: _selectedDistance,
      orientation: "0°", // Standard default
      obstruction: "None",
      durationSeconds: _testDurationSeconds,
    );
  }

  void _applyCalibratedExponent(double calculatedN) async {
    if (calculatedN > 0 && calculatedN < 10) {
      setState(() {
        _nController.text = calculatedN.toStringAsFixed(2);
      });
      await widget.storageService.setPathLossN(calculatedN);
      widget.measurementRepository.reloadConfig();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved calculated Exponent n = ${calculatedN.toStringAsFixed(2)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.measurementRepository,
      builder: (context, _) {
        final List<BleDevice> devices = widget.measurementRepository.devices;
        final bool isTesting = widget.measurementRepository.isTestActive;
        final String activeType = widget.measurementRepository.activeTestType;
        
        // Auto-select target device if none is selected and devices exist
        if (_selectedTargetDeviceId == null && devices.isNotEmpty) {
          _selectedTargetDeviceId = devices.first.deviceId;
        }

        // Filter for calibration test summaries
        final List<TestSummary> calibrationRuns = widget.measurementRepository.testSummaries
            .where((s) => s.testType == "Calibration")
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Configurable Parameters Card
              _buildParametersCard(),
              const SizedBox(height: 16),

              // 2. Calibration Execution Settings Card
              _buildExecutionCard(devices, isTesting, activeType),
              const SizedBox(height: 24),

              // 3. Calibration Test Results & History Card
              _buildResultsHistoryCard(calibrationRuns),
            ],
          ),
        );
      },
    );
  }

  Widget _buildParametersCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PATH-LOSS CONFIGURATION (EXPERIMENTAL DISTANCE)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _d0Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Reference Dist d0 (m)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _rssi0Controller,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Reference RSSI0 (dBm)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Exponent n',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveConfigValues,
                icon: const Icon(Icons.save_rounded),
                label: const Text('SAVE PARAMETERS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutionCard(List<BleDevice> devices, bool isTesting, String activeType) {
    final bool currentCalibrationRunning = isTesting && activeType == "Calibration";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'KNOWN DISTANCE TEST ENGINE',
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
                        'No nearby transmitters detected yet. Turn on Scanning and advertise from another device first.',
                        style: TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Device Selector dropdown
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
                onChanged: currentCalibrationRunning
                    ? null
                    : (val) {
                        setState(() {
                          _selectedTargetDeviceId = val;
                        });
                      },
              ),
              const SizedBox(height: 16),
              
              // Known distance selection
              const Text(
                'Select Actual Testing Distance (meters):',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _presetDistances.map((dist) {
                  final bool isSelected = _selectedDistance == dist;
                  return ChoiceChip(
                    label: Text('${dist.toStringAsFixed(1)} m'),
                    selected: isSelected,
                    selectedColor: const Color(0xFFD946EF).withOpacity(0.2),
                    backgroundColor: const Color(0xFF0F0F13),
                    labelStyle: TextStyle(
                      color: isSelected ? const Color(0xFFD946EF) : Colors.white60,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: isSelected ? const Color(0xFFD946EF) : Colors.white10),
                    ),
                    onSelected: currentCalibrationRunning
                        ? null
                        : (selected) {
                            if (selected) {
                              setState(() {
                                _selectedDistance = dist;
                              });
                            }
                          },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Duration selector
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Test Collection Duration:', style: TextStyle(fontSize: 13, color: Colors.white70)),
                  DropdownButton<int>(
                    value: _testDurationSeconds,
                    dropdownColor: const Color(0xFF171721),
                    items: [10, 15, 20, 30].map((sec) {
                      return DropdownMenuItem<int>(
                        value: sec,
                        child: Text('$sec seconds'),
                      );
                    }).toList(),
                    onChanged: currentCalibrationRunning
                        ? null
                        : (val) {
                            if (val != null) {
                              setState(() {
                                _testDurationSeconds = val;
                              });
                            }
                          },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Execution Button or Countdown
              if (currentCalibrationRunning) ...[
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
                          'Collecting BLE RSSI samples...',
                          style: TextStyle(color: const Color(0xFFD946EF).withOpacity(0.8), fontSize: 13),
                        ),
                        Text(
                          '${widget.measurementRepository.testSecondsRemaining}s remaining',
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
                        child: const Text('STOP COLLECTING EARLY'),
                      ),
                    ),
                  ],
                ),
              ] else if (isTesting) ...[
                // Another type of test is active
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
                    onPressed: _startCalibrationTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD946EF),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('START CALIBRATION TEST'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHistoryCard(List<TestSummary> runs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'CALIBRATION TEST RUN HISTORIES',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'No calibration test runs recorded in this session.',
                    style: TextStyle(color: Colors.white24, fontStyle: FontStyle.italic),
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: runs.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final run = runs[runs.length - 1 - index]; // Show latest run first

                  // Calculate matching Path Loss Exponent 'n' based on median RSSI
                  final double calculatedN = DistanceEstimator.calculatePathLossExponent(
                    rssi0: widget.storageService.getRssi0(),
                    measuredRssi: run.medianRssi,
                    actualDistance: run.actualDistance,
                    d0: widget.storageService.getD0(),
                  );

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Run @ ${run.actualDistance.toStringAsFixed(1)}m on ${run.targetDeviceId}',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)),
                          ),
                          Text(
                            '${run.sampleCount} Samples',
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile('Median RSSI', '${run.medianRssi.toStringAsFixed(1)} dBm'),
                          ),
                          Expanded(
                            child: _buildMetricTile('Mean RSSI', '${run.meanRssi.toStringAsFixed(1)} dBm'),
                          ),
                          Expanded(
                            child: _buildMetricTile('Std Dev', run.rssiStdDev.toStringAsFixed(2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile('Est. Distance', '${run.estimatedDistance.toStringAsFixed(2)} m'),
                          ),
                          Expanded(
                            child: _buildMetricTile('Abs Error', '${run.absoluteError.toStringAsFixed(2)} m'),
                          ),
                          Expanded(
                            child: _buildMetricTile(
                              'Pct Error',
                              '${run.percentageError.toStringAsFixed(1)}%',
                              color: run.percentageError > 50.0 ? Colors.orangeAccent : const Color(0xFFD946EF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Computed path loss n: ${calculatedN.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70, fontStyle: FontStyle.italic),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => _applyCalibratedExponent(calculatedN),
                            icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                            label: const Text('APPLY EXPONENT'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, {Color? color}) {
    return Container(
      margin: const EdgeInsets.all(4.0),
      padding: const EdgeInsets.all(8.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F13),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.white30)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color ?? const Color(0xFFEEEEEE),
            ),
          ),
        ],
      ),
    );
  }
}
