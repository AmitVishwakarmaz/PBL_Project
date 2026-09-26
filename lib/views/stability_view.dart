import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import 'widgets/custom_chart.dart';

class StabilityView extends StatefulWidget {
  final MeasurementRepository measurementRepository;

  const StabilityView({
    super.key,
    required this.measurementRepository,
  });

  @override
  State<StabilityView> createState() => _StabilityViewState();
}

class _StabilityViewState extends State<StabilityView> {
  String? _selectedTargetDeviceId;
  double _testDistance = 1.0;
  final int _testDurationSeconds = 60;

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

        // Active stability data buffers
        final List<int> currentBuffer = widget.measurementRepository.activeStabilityRssiBuffer;
        final List<double> currentTimeBuffer = widget.measurementRepository.activeStabilityTimeBuffer;

        // Statistics on current buffer or latest completed run
        final RssiProcessor processor = RssiProcessor();
        final stats = processor.calculateStats(currentBuffer);
        final double range = stats.sampleCount > 0 ? (stats.max - stats.min) : 0.0;

        final List<TestSummary> stabilityRuns = widget.measurementRepository.testSummaries
            .where((s) => s.testType == "Stability")
            .toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Setup Card
              _buildSetupCard(devices, isTesting, activeType),
              const SizedBox(height: 16),

              // Live Chart Card
              _buildLiveChartCard(currentBuffer, currentTimeBuffer, stats, range, isTesting, activeType),
              const SizedBox(height: 24),

              // Runs History
              _buildRunsHistoryCard(stabilityRuns),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSetupCard(List<BleDevice> devices, bool isTesting, String activeType) {
    final bool currentRunning = isTesting && activeType == "Stability";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STABILITY RUN CONTROL (60 SECONDS)',
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

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Test Distance: ', style: TextStyle(fontSize: 13, color: Colors.white70)),
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
                  const Spacer(),
                  Text(
                    'Fixed Duration: $_testDurationSeconds seconds',
                    style: const TextStyle(fontSize: 13, color: Colors.white54, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 20),

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
                        const Text(
                          'Streaming RSSI values continuously...',
                          style: TextStyle(color: Color(0xFF00F0FF), fontSize: 13),
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
                        child: const Text('STOP STABILITY RECORDING'),
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
                        testType: "Stability",
                        targetDeviceId: _selectedTargetDeviceId!,
                        actualDistance: _testDistance,
                        orientation: "0°",
                        obstruction: "None",
                        durationSeconds: _testDurationSeconds,
                      );
                    },
                    child: const Text('START 60s STABILITY RECORDING'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLiveChartCard(
    List<int> currentBuffer,
    List<double> currentTimeBuffer,
    RssiStats stats,
    double range,
    bool isTesting,
    String activeType,
  ) {
    final bool currentRunning = isTesting && activeType == "Stability";

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
                  'REAL-TIME RSSI SIGNAL PLOT',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                ),
                Text(
                  currentRunning ? 'Recording' : 'Idle',
                  style: const TextStyle(fontSize: 12, color: Colors.white30),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RssiChart(
              rssiSamples: currentBuffer,
              timeSamples: currentTimeBuffer,
              durationSeconds: _testDurationSeconds.toDouble(),
            ),
            const SizedBox(height: 16),
            const Text(
              'LIVE STREAM STATISTICS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildChartMetricTile('Samples', '${stats.sampleCount}')),
                Expanded(child: _buildChartMetricTile('Median', stats.sampleCount > 0 ? '${stats.median.toStringAsFixed(1)} dBm' : '-')),
                Expanded(child: _buildChartMetricTile('Mean', stats.sampleCount > 0 ? '${stats.mean.toStringAsFixed(1)} dBm' : '-')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _buildChartMetricTile('Std Dev', stats.sampleCount > 0 ? stats.stdDev.toStringAsFixed(2) : '-')),
                Expanded(child: _buildChartMetricTile('Min/Max', stats.sampleCount > 0 ? '${stats.min.toInt()} / ${stats.max.toInt()} dBm' : '-')),
                Expanded(child: _buildChartMetricTile('Range', stats.sampleCount > 0 ? '${range.toInt()} dB' : '-')),
              ],
            ),
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
              'STABILITY RUN HISTORY LIST',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white54),
            ),
            const SizedBox(height: 12),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24.0),
                  child: Text(
                    'No completed stability runs recorded yet.',
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
                    DataColumn(label: Text('Device')),
                    DataColumn(label: Text('Distance')),
                    DataColumn(label: Text('Samples')),
                    DataColumn(label: Text('Median')),
                    DataColumn(label: Text('Mean')),
                    DataColumn(label: Text('Std Dev')),
                    DataColumn(label: Text('Range')),
                  ],
                  rows: runs.map((run) {
                    return DataRow(
                      cells: [
                        DataCell(Text(run.targetDeviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)))),
                        DataCell(Text('${run.actualDistance.toStringAsFixed(1)} m')),
                        DataCell(Text('${run.sampleCount}')),
                        DataCell(Text('${run.medianRssi.toStringAsFixed(1)} dBm')),
                        DataCell(Text('${run.meanRssi.toStringAsFixed(1)} dBm')),
                        DataCell(Text(run.rssiStdDev.toStringAsFixed(2))),
                        DataCell(Text('${(run.rssiStdDev * 3).toStringAsFixed(1)} dB')), // Approx range indicator
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

  Widget _buildChartMetricTile(String label, String value) {
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
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: const Color(0xFFEFEFEF),
            ),
          ),
        ],
      ),
    );
  }
}
