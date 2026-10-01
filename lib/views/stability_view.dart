import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/app_theme.dart';
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
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Setup Card
              _buildSetupCard(devices, isTesting, activeType),
              const SizedBox(height: AppSpacing.md),

              // Live Chart Card
              _buildLiveChartCard(currentBuffer, currentTimeBuffer, stats, range, isTesting, activeType),
              const SizedBox(height: AppSpacing.md),

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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STABILITY RUN CONTROL (60 SECONDS)',
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

              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('Test Distance: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                  const Spacer(),
                  Text(
                    'Fixed Duration: $_testDurationSeconds seconds',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

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
                        const Text(
                          'Streaming RSSI values continuously...',
                          style: TextStyle(color: AppColors.primaryAccent, fontSize: 12, fontWeight: FontWeight.w600),
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
                        child: const Text('STOP STABILITY RECORDING'),
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'REAL-TIME RSSI SIGNAL PLOT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceSubtle,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Text(
                    currentRunning ? 'Recording' : 'Idle',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: currentRunning ? AppColors.primaryAccent : AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            RssiChart(
              rssiSamples: currentBuffer,
              timeSamples: currentTimeBuffer,
              durationSeconds: _testDurationSeconds.toDouble(),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'LIVE STREAM STATISTICS',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.xs),
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
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'STABILITY RUN HISTORY LIST',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (runs.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    'No completed stability runs recorded yet.',
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
                    DataColumn(label: Text('Device', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Distance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Median', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Mean', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Range', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                  ],
                  rows: runs.map((run) {
                    return DataRow(
                      cells: [
                        DataCell(Text(run.targetDeviceId, style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, color: AppColors.primaryAccent))),
                        DataCell(Text('${run.actualDistance.toStringAsFixed(1)} m', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${run.sampleCount}', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${run.medianRssi.toStringAsFixed(1)} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${run.meanRssi.toStringAsFixed(1)} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text(run.rssiStdDev.toStringAsFixed(2), style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${(run.rssiStdDev * 3).toStringAsFixed(1)} dB', style: const TextStyle(color: AppColors.textSecondary))),
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
      margin: const EdgeInsets.all(3.0),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
