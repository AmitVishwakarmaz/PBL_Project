import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/app_theme.dart';

class ManualPairwiseEntry {
  final String scannerId;
  final String transmitterId;
  final int rssi;
  final int samples;
  final double mean;
  final double stdDev;

  ManualPairwiseEntry({
    required this.scannerId,
    required this.transmitterId,
    required this.rssi,
    required this.samples,
    required this.mean,
    required this.stdDev,
  });
}

class PairwiseView extends StatefulWidget {
  final MeasurementRepository measurementRepository;

  const PairwiseView({
    super.key,
    required this.measurementRepository,
  });

  @override
  State<PairwiseView> createState() => _PairwiseViewState();
}

class _PairwiseViewState extends State<PairwiseView> {
  final List<ManualPairwiseEntry> _manualEntries = [];

  final _scannerController = TextEditingController();
  final _transmitterController = TextEditingController();
  final _rssiController = TextEditingController();
  final _samplesController = TextEditingController();
  final _meanController = TextEditingController();
  final _stdDevController = TextEditingController();

  void _showAddEntryDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.lg)),
          title: const Text('Add Pairwise Entry', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _scannerController,
                  decoration: const InputDecoration(labelText: 'Scanner ID (e.g. Phone B)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _transmitterController,
                  decoration: const InputDecoration(labelText: 'Transmitter ID (e.g. Phone C)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _rssiController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Latest RSSI (dBm)'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _samplesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sample Count'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _meanController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mean RSSI'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _stdDevController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Standard Deviation'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () {
                final int? rssi = int.tryParse(_rssiController.text);
                final int? samples = int.tryParse(_samplesController.text);
                final double? mean = double.tryParse(_meanController.text);
                final double? stdDev = double.tryParse(_stdDevController.text);

                if (_scannerController.text.isNotEmpty &&
                    _transmitterController.text.isNotEmpty &&
                    rssi != null &&
                    samples != null &&
                    mean != null &&
                    stdDev != null) {
                  setState(() {
                    _manualEntries.add(
                      ManualPairwiseEntry(
                        scannerId: _scannerController.text,
                        transmitterId: _transmitterController.text,
                        rssi: rssi,
                        samples: samples,
                        mean: mean,
                        stdDev: stdDev,
                      ),
                    );
                  });
                  
                  // Clear controllers
                  _scannerController.clear();
                  _transmitterController.clear();
                  _rssiController.clear();
                  _samplesController.clear();
                  _meanController.clear();
                  _stdDevController.clear();

                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please fill all fields with valid numbers.')),
                  );
                }
              },
              child: const Text('Add'),
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
        final List<BleDevice> scannedDevices = widget.measurementRepository.devices;
        final RssiProcessor processor = RssiProcessor();

        // 1. Gather automatic entries (where self is the scanner)
        final List<Map<String, dynamic>> combinedRows = [];

        // Add auto rows
        for (var device in scannedDevices) {
          final stats = device.getStats(processor);
          if (stats.sampleCount > 0) {
            combinedRows.add({
              'scanner': 'Self (A)',
              'transmitter': '${device.friendlyName} (${device.deviceId})',
              'rssi': device.rawRssiHistory.isNotEmpty ? device.rawRssiHistory.last : 0,
              'samples': stats.sampleCount,
              'mean': stats.mean,
              'stdDev': stats.stdDev,
              'isManual': false,
            });
          }
        }

        // Add manual rows
        for (var entry in _manualEntries) {
          combinedRows.add({
            'scanner': entry.scannerId,
            'transmitter': entry.transmitterId,
            'rssi': entry.rssi,
            'samples': entry.samples,
            'mean': entry.mean,
            'stdDev': entry.stdDev,
            'isManual': true,
          });
        }

        return Scaffold(
          backgroundColor: AppColors.primaryBg,
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildExplainCard(),
                const SizedBox(height: AppSpacing.md),
                _buildMatrixCard(combinedRows),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primaryAccent,
            onPressed: _showAddEntryDialog,
            tooltip: 'Add Entry from other phone',
            child: const Icon(Icons.add_rounded, color: Colors.white),
          ),
        );
      },
    );
  }

  Widget _buildExplainCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_outlined, color: AppColors.primaryAccent, size: 20),
                SizedBox(width: AppSpacing.sm),
                Text(
                  'PAIRWISE ANCHOR-TO-ANCHOR TESTING',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'For self-localization (coordinate calculation), we must verify that anchors can successfully scan each other pairwise. This screen builds the scanner-to-transmitter grid.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
            const SizedBox(height: AppSpacing.xs),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
                children: [
                  TextSpan(text: 'Note: ', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryAccent)),
                  TextSpan(text: 'Since there is no shared backend database in this phase, Phone A cannot query Phone B\'s scan results directly. Click the "+" button to manually type Phone B\'s results and see the unified matrix.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatrixCard(List<Map<String, dynamic>> rows) {
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
                  'PAIRWISE MEASUREMENT SUMMARY',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: AppColors.primaryAccent),
                ),
                if (_manualEntries.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _manualEntries.clear();
                      });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Text('Clear Manual', style: TextStyle(fontSize: 12, color: AppColors.error)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (rows.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Column(
                    children: [
                      Icon(Icons.hub_outlined, size: 40, color: AppColors.textTertiary.withOpacity(0.6)),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'No pairwise data available.\nActivate scanning or tap the "+" button below to add entries.',
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
                    DataColumn(label: Text('Scanner (Rx)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Transmitter (Tx)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('RSSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Mean RSSI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                    DataColumn(label: Text('Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppColors.textSecondary))),
                  ],
                  rows: rows.map((row) {
                    final bool isManual = row['isManual'] as bool;
                    return DataRow(
                      cells: [
                        DataCell(Text(row['scanner'] as String, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary))),
                        DataCell(Text(row['transmitter'] as String, style: const TextStyle(fontFamily: 'Courier', color: AppColors.primaryAccent, fontWeight: FontWeight.bold))),
                        DataCell(Text('${row['rssi']} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${row['samples']}', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text('${(row['mean'] as double).toStringAsFixed(1)} dBm', style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(Text((row['stdDev'] as double).toStringAsFixed(2), style: const TextStyle(color: AppColors.textPrimary))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isManual ? AppColors.surfaceSubtle : AppColors.successSubtle,
                              borderRadius: BorderRadius.circular(AppRadii.sm),
                              border: Border.all(color: isManual ? AppColors.border : AppColors.success.withOpacity(0.3)),
                            ),
                            child: Text(
                              isManual ? 'MANUAL' : 'AUTO-SCAN',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isManual ? AppColors.textSecondary : AppColors.success,
                              ),
                            ),
                          ),
                        ),
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
