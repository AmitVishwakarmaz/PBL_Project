import 'package:flutter/material.dart';

import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';

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
          backgroundColor: const Color(0xFF171721),
          title: const Text('Add Pairwise Entry', style: TextStyle(fontFamily: 'Outfit')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _scannerController,
                  decoration: const InputDecoration(labelText: 'Scanner ID (e.g. Phone B)'),
                ),
                TextField(
                  controller: _transmitterController,
                  decoration: const InputDecoration(labelText: 'Transmitter ID (e.g. Phone C)'),
                ),
                TextField(
                  controller: _rssiController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Latest RSSI (dBm)'),
                ),
                TextField(
                  controller: _samplesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Sample Count'),
                ),
                TextField(
                  controller: _meanController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Mean RSSI'),
                ),
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
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
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
        // We'll construct a combined list of automatic + manual entries
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
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildExplainCard(),
                const SizedBox(height: 16),
                _buildMatrixCard(combinedRows),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: const Color(0xFFD946EF),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.hub_rounded, color: Color(0xFF00F0FF)),
                SizedBox(width: 12),
                Text(
                  'PAIRWISE ANCHOR-TO-ANCHOR TESTING',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'For self-localization (coordinate calculation), we must verify that anchors can successfully scan each other pairwise. This screen builds the scanner-to-transmitter grid.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 8),
            RichText(
              text: const TextSpan(
                style: TextStyle(fontSize: 13, color: Colors.white60),
                children: [
                  TextSpan(text: 'Note: ', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD946EF))),
                  TextSpan(text: 'Since there is no shared backend database in this phase, Phone A cannot query Phone B\'s scan results directly. Click the fuchsia "+" button to manually type Phone B\'s results and see the unified matrix.'),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PAIRWISE MEASUREMENT SUMMARY',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFFD946EF)),
                ),
                if (_manualEntries.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _manualEntries.clear();
                      });
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    child: const Text('Clear Manual'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32.0),
                  child: Column(
                    children: [
                      Icon(Icons.hub_outlined, size: 48, color: Colors.white24),
                      SizedBox(height: 12),
                      Text(
                        'No pairwise data available.\nActivate scanning or tap the "+" button below to add entries.',
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
                  columnSpacing: 24,
                  headingRowColor: MaterialStateProperty.all(const Color(0xFF0F0F13)),
                  columns: const [
                    DataColumn(label: Text('Scanner (Rx)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Transmitter (Tx)', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('RSSI', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Samples', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Mean RSSI', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Std Dev', style: TextStyle(fontWeight: FontWeight.bold))),
                    DataColumn(label: Text('Source', style: TextStyle(fontWeight: FontWeight.bold))),
                  ],
                  rows: rows.map((row) {
                    final bool isManual = row['isManual'] as bool;
                    return DataRow(
                      cells: [
                        DataCell(Text(row['scanner'] as String, style: const TextStyle(fontWeight: FontWeight.bold))),
                        DataCell(Text(row['transmitter'] as String, style: const TextStyle(fontFamily: 'Courier', color: Color(0xFF00F0FF)))),
                        DataCell(Text('${row['rssi']} dBm')),
                        DataCell(Text('${row['samples']}')),
                        DataCell(Text('${(row['mean'] as double).toStringAsFixed(1)} dBm')),
                        DataCell(Text((row['stdDev'] as double).toStringAsFixed(2))),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isManual ? Colors.purple.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isManual ? 'MANUAL' : 'AUTO-SCAN',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: isManual ? Colors.purpleAccent : Colors.greenAccent,
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
