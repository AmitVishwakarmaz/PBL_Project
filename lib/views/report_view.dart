import 'package:flutter/material.dart';

import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../services/measurement_repository.dart';
import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';

class ReportView extends StatelessWidget {
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;

  const ReportView({
    super.key,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        bleAdvertiser,
        bleScanner,
        measurementRepository,
      ]),
      builder: (context, _) {
        final List<BleDevice> devices = measurementRepository.devices;
        final List<TestSummary> calibrationRuns = measurementRepository.testSummaries
            .where((s) => s.testType == "Calibration")
            .toList();

        // 1. Evaluate BLE Capabilities
        final bool isAdvertisingSupported = bleAdvertiser.isSupported;
        final bool isScanningActive = bleScanner.isScanning || devices.isNotEmpty;
        final bool isRssiAvailable = devices.any((d) => d.rawRssiHistory.isNotEmpty);
        final bool isMultipleDevicesDetected = devices.length >= 2;

        // 2. Evaluate Measurement Quality
        final RssiProcessor processor = RssiProcessor();
        
        // Average RSSI standard deviation
        double totalStdDev = 0.0;
        int activeDeviceCount = 0;
        for (var device in devices) {
          final stats = device.getStats(processor);
          if (stats.sampleCount > 0) {
            totalStdDev += stats.stdDev;
            activeDeviceCount++;
          }
        }
        final double avgStdDev = activeDeviceCount > 0 ? (totalStdDev / activeDeviceCount) : 0.0;

        // Best and worst stable distances based on calibration runs
        double bestStableDistance = 0.0;
        double worstStableDistance = 0.0;
        double lowestStdDev = 999.0;
        double highestStdDev = -1.0;

        for (var run in calibrationRuns) {
          if (run.rssiStdDev < lowestStdDev) {
            lowestStdDev = run.rssiStdDev;
            bestStableDistance = run.actualDistance;
          }
          if (run.rssiStdDev > highestStdDev) {
            highestStdDev = run.rssiStdDev;
            worstStableDistance = run.actualDistance;
          }
        }

        // Average distance estimation error
        double totalPctError = 0.0;
        for (var run in calibrationRuns) {
          totalPctError += run.percentageError;
        }
        final double avgErrorPct = calibrationRuns.isNotEmpty ? (totalPctError / calibrationRuns.length) : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Recommendation Banner
              _buildRecommendationCard(
                isAdvertisingSupported,
                isScanningActive,
                isRssiAvailable,
                avgStdDev,
              ),
              const SizedBox(height: 16),

              // Capabilities Checkbox Card
              _buildCapabilitiesCard(
                isAdvertisingSupported,
                isScanningActive,
                isRssiAvailable,
                isMultipleDevicesDetected,
              ),
              const SizedBox(height: 16),

              // Quality metrics Card
              _buildQualityCard(
                avgStdDev,
                calibrationRuns.isNotEmpty,
                bestStableDistance,
                lowestStdDev,
                worstStableDistance,
                highestStdDev,
                avgErrorPct,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecommendationCard(
    bool canAdvertise,
    bool canScan,
    bool hasRssi,
    double avgStdDev,
  ) {
    final bool coreCapabilitiesMet = canAdvertise && canScan && hasRssi;

    Color bannerColor;
    String titleText;
    String descText;
    IconData icon;

    if (!coreCapabilitiesMet) {
      bannerColor = Colors.redAccent;
      titleText = "INSUFFICIENT DATA / METRICS FAIL";
      descText = "Core Bluetooth capabilities are not active or supported on this device. Review the Capability Report below.";
      icon = Icons.cancel_rounded;
    } else {
      bannerColor = const Color(0xFFD946EF);
      titleText = "SUITABILITY TO BE DETERMINED";
      descText = "Device supports scanning and advertising. Evaluate the standard deviation ($avgStdDev dB) to determine positioning suitability.";
      icon = Icons.help_outline_rounded;
    }

    return Card(
      elevation: 6,
      shadowColor: bannerColor.withOpacity(0.2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: bannerColor.withOpacity(0.4), width: 1.5),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [bannerColor.withOpacity(0.15), Colors.transparent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(18.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: bannerColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleText,
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: bannerColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    descText,
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapabilitiesCard(
    bool adv,
    bool scan,
    bool rssi,
    bool multi,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BLE HARDWARE & CORE CAPABILITY CHECK',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFF00F0FF)),
            ),
            const SizedBox(height: 16),
            _buildChecklistTile('BLE Peripheral Mode (Advertising)', adv, 'Needed to transmit anchor identity packets.'),
            const Divider(color: Colors.white10),
            _buildChecklistTile('BLE Central Mode (Scanning)', scan, 'Needed to listen for nearby transmitters.'),
            const Divider(color: Colors.white10),
            _buildChecklistTile('RSSI Stream Availability', rssi, 'Needed to capture signal power levels.'),
            const Divider(color: Colors.white10),
            _buildChecklistTile('Multi-Device Detection', multi, 'Requires at least 2 transmitting test nodes active.'),
          ],
        ),
      ),
    );
  }

  Widget _buildChecklistTile(String title, bool pass, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pass ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: pass ? const Color(0xFF00F0FF) : Colors.redAccent,
            size: 24,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: pass ? Colors.white : Colors.white60,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(fontSize: 12, color: Colors.white30),
                ),
              ],
            ),
          ),
          Text(
            pass ? 'PASS' : 'FAIL',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: pass ? const Color(0xFF00F0FF) : Colors.redAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityCard(
    double avgStdDev,
    bool hasCalibration,
    double bestDist,
    double bestStd,
    double worstDist,
    double worstStd,
    double avgError,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MEASUREMENT SIGNAL QUALITY SUMMARY',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Color(0xFFD946EF)),
            ),
            const SizedBox(height: 16),
            _buildQualityMetricRow(
              'Average RSSI Standard Deviation',
              avgStdDev > 0 ? '${avgStdDev.toStringAsFixed(2)} dBm' : 'No Data',
              'Lower is better. A value under 3.0 indicates a stable RF environment.',
            ),
            const Divider(color: Colors.white10),
            _buildQualityMetricRow(
              'Best Stable Calibration Distance',
              hasCalibration ? '${bestDist.toStringAsFixed(1)} m (Std Dev: ${bestStd.toStringAsFixed(2)} dBm)' : 'No Data',
              'The known test distance that returned the lowest RSSI variance.',
            ),
            const Divider(color: Colors.white10),
            _buildQualityMetricRow(
              'Worst Stable Calibration Distance',
              hasCalibration ? '${worstDist.toStringAsFixed(1)} m (Std Dev: ${worstStd.toStringAsFixed(2)} dBm)' : 'No Data',
              'The known test distance that returned the highest RSSI variance.',
            ),
            const Divider(color: Colors.white10),
            _buildQualityMetricRow(
              'Avg. Distance Estimation Error',
              hasCalibration ? '${avgError.toStringAsFixed(1)}%' : 'No Data',
              'Average accuracy gap of the path-loss log model compared to physical distance.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityMetricRow(String label, String value, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF00F0FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(fontSize: 11, color: Colors.white30),
          ),
        ],
      ),
    );
  }
}
