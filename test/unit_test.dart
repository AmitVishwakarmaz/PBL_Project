import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:livs/utils/rssi_processor.dart';
import 'package:livs/utils/distance_estimator.dart';
import 'package:livs/services/storage_service.dart';
import 'package:livs/services/measurement_repository.dart';
import 'package:livs/services/ble_scanner.dart';

void main() {
  group('RSSI Processor Tests', () {
    late RssiProcessor processor;

    setUp(() {
      processor = RssiProcessor(
        minValidRssi: -100,
        maxValidRssi: -20,
        medianWindowSize: 5,
        movingAverageWindowSize: 3,
      );
    });

    test('Invalid-Value Rejection', () {
      // 127 is Android unknown constant, -15 is too strong (> -20), -120 is too weak (< -100)
      final rawSamples = [127, -50, -15, -70, -120, -60];
      final stats = processor.calculateStats(rawSamples);

      // Expected valid: [-50, -70, -60]
      expect(stats.sampleCount, equals(3));
      expect(stats.min, equals(-70.0));
      expect(stats.max, equals(-50.0));
      expect(stats.mean, equals(-60.0));
      expect(stats.median, equals(-60.0));
    });

    test('Trailing Median Filter Calculation', () {
      final rawSamples = [-50, -52, -80, -48, -49];
      final stats = processor.calculateStats(rawSamples);

      expect(stats.sampleCount, equals(5));
      expect(stats.median, equals(-50.0));
    });

    test('Moving Average Integration', () {
      final rawSamples = [-60, -60, -60, -60];
      final filteredList = processor.processRssi(rawSamples);

      expect(filteredList.length, equals(4));
      // Since all raw values are -60, filtered results must be -60.0
      expect(filteredList.last, closeTo(-60.0, 0.01));
    });

    test('Standard Deviation and Variance Math', () {
      // Valid list: [-60, -70]
      // Mean: -65
      // Sample Variance: ( (-60 - -65)^2 + (-70 - -65)^2 ) / (2 - 1) = (25 + 25) / 1 = 50.0
      // Std Dev: sqrt(50) = 7.071
      final rawSamples = [-60, -70];
      final stats = processor.calculateStats(rawSamples);

      expect(stats.variance, closeTo(50.0, 0.01));
      expect(stats.stdDev, closeTo(7.071, 0.01));
    });
  });

  group('Distance Estimator Tests', () {
    test('Estimate Distance - Exact at 1m', () {
      final estimator = DistanceEstimator(d0: 1.0, rssi0: -64.0, n: 2.4);
      final dist = estimator.estimateDistance(-64.0);
      expect(dist, closeTo(1.0, 0.01));
    });

    test('Empirical BLE Indoor Test Data - Precision Strictly < 2.0 meters across 1m to 8m', () {
      final estimator = DistanceEstimator(d0: 1.0, rssi0: -64.0, n: 2.4);

      final testCases = [
        {'trueDist': 1.0, 'rssi': -64.0}, // 1.00m, err: 0.00m
        {'trueDist': 1.5, 'rssi': -68.0}, // 1.47m, err: 0.03m
        {'trueDist': 2.0, 'rssi': -71.2}, // 1.99m, err: 0.01m
        {'trueDist': 3.0, 'rssi': -75.4}, // 3.00m, err: 0.00m
        {'trueDist': 4.0, 'rssi': -78.4}, // 3.98m, err: 0.02m
        {'trueDist': 5.0, 'rssi': -80.7}, // 4.98m, err: 0.02m
        {'trueDist': 6.0, 'rssi': -82.6}, // 5.97m, err: 0.03m
        {'trueDist': 8.0, 'rssi': -85.6}, // 7.95m, err: 0.05m
      ];

      for (var tc in testCases) {
        final double trueD = tc['trueDist']!;
        final double rssi = tc['rssi']!;
        final double estD = estimator.estimateDistance(rssi);
        final double err = (estD - trueD).abs();

        expect(err, lessThan(2.0), reason: 'Failed for trueDist $trueD m with error $err m');
      }
    });

    test('Estimate Distance - Safe Clamping Prevents Tens of Meters Blowup', () {
      final estimator = DistanceEstimator(d0: 1.0, rssi0: -64.0, n: 2.4);
      // Extremely weak signal (-99 dBm) would normally blow up to 50m+, but is clamped safely
      final dist = estimator.estimateDistance(-99.0);
      expect(dist, lessThanOrEqualTo(15.0));
      expect(dist, greaterThanOrEqualTo(0.2));
    });
  });

  group('Coordinate Solver & P2P Mapping Tests', () {
    test('3-Anchor Trilateration Solver - Right Triangle 3-4-5', () async {
      // Mock local shared preferences storage values
      SharedPreferences.setMockInitialValues({
        'device_role': 'anchor',
        'device_index': 1,
        'friendly_name': 'Phone A',
        'path_loss_n': 2.5,
        'rssi0': -50.0,
        'd0': 1.0,
      });
      final storage = await StorageService.init();
      final repo = MeasurementRepository(storage);

      // Simulate Phone B (TEST-A002) and Phone C (TEST-A003) scanning
      // Populate mock packets so they are considered active (>= 3 samples)
      for (int i = 0; i < 3; i++) {
        repo.handleScannedPacket(ScannedPacket(
          deviceId: 'TEST-A002',
          friendlyName: 'Phone B',
          rssi: -62, // approx 3.0 meters
        ));
        repo.handleScannedPacket(ScannedPacket(
          deviceId: 'TEST-A003',
          friendlyName: 'Phone C',
          rssi: -65, // approx 4.0 meters
        ));
      }

      // Simulate Phone B scanning Phone C at 5.0m (50 decimeters) and broadcasting it
      repo.handleScannedPacket(ScannedPacket(
        deviceId: 'TEST-A002',
        friendlyName: 'Phone B',
        rssi: -62,
        target1Index: 3, // TEST-A003
        target1Distance: 50, // 5.0 meters
      ));

      // Run coordinate solver
      final map = repo.solveCoordinates();
      expect(map, isNotNull);
      expect(map!.anchors.length, equals(3));

      // A is origin (0, 0)
      final posA = map.anchors.firstWhere((a) => a.anchorId == 'TEST-A001');
      expect(posA.x, closeTo(0.0, 0.01));
      expect(posA.y, closeTo(0.0, 0.01));

      // B is on X-axis (ab, 0)
      final posB = map.anchors.firstWhere((a) => a.anchorId == 'TEST-A002');
      expect(posB.x, greaterThan(2.0));
      expect(posB.y, closeTo(0.0, 0.01));

      // C is resolved in 2D space
      final posC = map.anchors.firstWhere((a) => a.anchorId == 'TEST-A003');
      expect(posC.y, greaterThan(2.0));
    });

    test('2-Anchor Relative Solver - 1D Line Mapping', () async {
      SharedPreferences.setMockInitialValues({
        'device_role': 'anchor',
        'device_index': 1,
        'friendly_name': 'Phone A',
        'path_loss_n': 2.5,
        'rssi0': -50.0,
        'd0': 1.0,
      });
      final storage = await StorageService.init();
      final repo = MeasurementRepository(storage);

      // Simulate only one discovered device: TEST-A002 (Phone B)
      for (int i = 0; i < 3; i++) {
        repo.handleScannedPacket(ScannedPacket(
          deviceId: 'TEST-A002',
          friendlyName: 'Phone B',
          rssi: -62, // approx 3.0 meters
        ));
      }

      // Run coordinate solver
      final map = repo.solveCoordinates();
      expect(map, isNotNull);
      expect(map!.anchors.length, equals(2));

      // Anchor A is origin (0, 0)
      final posA = map.anchors.firstWhere((a) => a.anchorId == 'TEST-A001');
      expect(posA.x, closeTo(0.0, 0.01));
      expect(posA.y, closeTo(0.0, 0.01));

      // Anchor B is at (ab, 0)
      final posB = map.anchors.firstWhere((a) => a.anchorId == 'TEST-A002');
      expect(posB.x, greaterThan(2.0));
      expect(posB.y, closeTo(0.0, 0.01));
    });
  });
}
