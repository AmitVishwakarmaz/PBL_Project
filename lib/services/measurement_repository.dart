import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';

import '../models/ble_device.dart';
import '../utils/rssi_processor.dart';
import '../utils/distance_estimator.dart';
import '../services/ble_scanner.dart';
import 'storage_service.dart';
import 'central_server_service.dart';
import 'dart:convert';
import '../models/anchor_network.dart';

class CSVRecord {
  final DateTime timestamp;
  final String scannerId;
  final String transmitterId;
  final int rssi;
  final int? txPower;
  final int? sequenceNumber;
  final double estimatedDistance;
  
  // Calibration / Test Metadata
  final double? actualDistance;
  final String phoneModel;
  final String orientation;
  final String obstruction;
  final int? testDurationSeconds;

  CSVRecord({
    required this.timestamp,
    required this.scannerId,
    required this.transmitterId,
    required this.rssi,
    this.txPower,
    this.sequenceNumber,
    required this.estimatedDistance,
    this.actualDistance,
    required this.phoneModel,
    required this.orientation,
    required this.obstruction,
    this.testDurationSeconds,
  });

  List<dynamic> toCsvRow() {
    return [
      timestamp.toIso8601String(),
      scannerId,
      transmitterId,
      rssi,
      txPower ?? '',
      sequenceNumber ?? '',
      estimatedDistance.toStringAsFixed(2),
      actualDistance ?? '',
      phoneModel,
      orientation,
      obstruction,
      testDurationSeconds ?? '',
    ];
  }
}

class TestSummary {
  final String testType; // "Calibration", "Orientation", "Obstruction", "Stability"
  final String targetDeviceId;
  final double actualDistance;
  final String orientation;
  final String obstruction;
  final int durationSeconds;
  
  final int sampleCount;
  final double meanRssi;
  final double medianRssi;
  final double rssiStdDev;
  final double estimatedDistance;
  final double absoluteError;
  final double percentageError;
  final DateTime timestamp;

  TestSummary({
    required this.testType,
    required this.targetDeviceId,
    required this.actualDistance,
    required this.orientation,
    required this.obstruction,
    required this.durationSeconds,
    required this.sampleCount,
    required this.meanRssi,
    required this.medianRssi,
    required this.rssiStdDev,
    required this.estimatedDistance,
    required this.absoluteError,
    required this.percentageError,
    required this.timestamp,
  });
}

class MeasurementRepository extends ChangeNotifier {
  final StorageService _storageService;
  late RssiProcessor _rssiProcessor;
  late DistanceEstimator _distanceEstimator;

  final Map<String, BleDevice> _devices = {};
  final List<CSVRecord> _allRecords = [];
  final List<TestSummary> _testSummaries = [];

  // Active Test Mode State
  bool _isTestActive = false;
  String _activeTestType = "None"; // "Calibration", "Orientation", "Obstruction", "Stability"
  double _activeActualDistance = 1.0;
  String _activeOrientation = "0°";
  String _activeObstruction = "None";
  String _activeTargetDeviceId = "";
  int _activeDurationSeconds = 15;
  int _testSecondsRemaining = 0;
  Timer? _testTimer;
  Timer? _countdownTimer;

  // Active stability test real-time buffer
  final List<int> _activeStabilityRssiBuffer = [];
  final List<double> _activeStabilityTimeBuffer = []; // elapsed time in seconds

  // Remote Scanned P2P measurements: maps "TEST-A00X_TEST-A00Y" to distance in meters
  final Map<String, double> _remoteDistances = {};
  
  // Central Server & Tracking State
  CentralServerService? centralServerService;
  TrackedLocation? _localTrackedLocation;

  TrackedLocation? get trackedLocation {
    final synced = centralServerService?.latestSyncedLocation;
    if (synced != null && DateTime.now().difference(synced.timestamp).inSeconds < 5) {
      return synced;
    }
    return _localTrackedLocation ?? calculateDeviceLocation();
  }

  // Anchor map state
  AnchorMap? _lockedAnchorMap;
  AnchorMap? _currentCalibrationMap;
  
  AnchorMap? get lockedAnchorMap => _lockedAnchorMap;
  AnchorMap? get currentCalibrationMap => _currentCalibrationMap;

  List<BleDevice> get devices => _devices.values.toList();
  List<CSVRecord> get allRecords => _allRecords;
  List<TestSummary> get testSummaries => _testSummaries;

  bool get isTestActive => _isTestActive;
  String get activeTestType => _activeTestType;
  double get activeActualDistance => _activeActualDistance;
  String get activeOrientation => _activeOrientation;
  String get activeObstruction => _activeObstruction;
  String get activeTargetDeviceId => _activeTargetDeviceId;
  int get activeDurationSeconds => _activeDurationSeconds;
  int get testSecondsRemaining => _testSecondsRemaining;

  List<int> get activeStabilityRssiBuffer => _activeStabilityRssiBuffer;
  List<double> get activeStabilityTimeBuffer => _activeStabilityTimeBuffer;

  MeasurementRepository(this._storageService) {
    _updateConfigurables();
    _loadPersistedAnchorMap();
  }

  void _loadPersistedAnchorMap() {
    try {
      final jsonString = _storageService.getAnchorMap();
      if (jsonString != null) {
        final Map<String, dynamic> decoded = json.decode(jsonString);
        _lockedAnchorMap = AnchorMap.fromJson(decoded);
      }
    } catch (e) {
      debugPrint("Error loading persisted anchor map: $e");
    }
  }

  void _updateConfigurables() {
    _rssiProcessor = RssiProcessor();
    _distanceEstimator = DistanceEstimator(
      d0: _storageService.getD0(),
      rssi0: _storageService.getRssi0(),
      n: _storageService.getPathLossN(),
    );
  }

  /// Triggered whenever settings change
  void reloadConfig() {
    _updateConfigurables();
    notifyListeners();
  }

  void handleScannedPacket(ScannedPacket packet) {
    final String localId = _storageService.getDeviceId();
    
    // Do not log ourselves if somehow scanned
    if (packet.deviceId == localId) {
      return;
    }

    // 1. Update or create BLE Device
    if (_devices.containsKey(packet.deviceId)) {
      final dev = _devices[packet.deviceId]!;
      dev.addRssi(
        packet.rssi,
        txPower: packet.txPower,
        sequenceNumber: packet.sequenceNumber,
      );
      dev.friendlyName = packet.friendlyName;
      dev.role = packet.role;
      dev.roomName = packet.roomName;
    } else {
      _devices[packet.deviceId] = BleDevice(
        deviceId: packet.deviceId,
        friendlyName: packet.friendlyName,
        role: packet.role,
        roomName: packet.roomName,
        lastSeen: DateTime.now(),
        rssi: packet.rssi,
        txPower: packet.txPower,
        lastSequenceNumber: packet.sequenceNumber,
      );
    }

    // Extract dynamic P2P distances (Bytes 7-10)
    if (packet.target1Index != null && packet.target1Index! > 0 && packet.target1Distance != null && packet.target1Distance! > 0) {
      final String tId = 'TEST-A${packet.target1Index!.toString().padLeft(3, '0')}';
      _remoteDistances['${packet.deviceId}_$tId'] = packet.target1Distance! / 10.0;
    }
    if (packet.target2Index != null && packet.target2Index! > 0 && packet.target2Distance != null && packet.target2Distance! > 0) {
      final String tId = 'TEST-A${packet.target2Index!.toString().padLeft(3, '0')}';
      _remoteDistances['${packet.deviceId}_$tId'] = packet.target2Distance! / 10.0;
    }

    // Calculate current estimated distance
    final device = _devices[packet.deviceId]!;
    final double estimatedDistance = device.getEstimatedDistance(_rssiProcessor, _distanceEstimator);

    // 2. Build CSV Record
    final record = CSVRecord(
      timestamp: DateTime.now(),
      scannerId: localId,
      transmitterId: packet.deviceId,
      rssi: packet.rssi,
      txPower: packet.txPower,
      sequenceNumber: packet.sequenceNumber,
      estimatedDistance: estimatedDistance,
      actualDistance: _isTestActive && packet.deviceId == _activeTargetDeviceId ? _activeActualDistance : null,
      phoneModel: _storageService.getFriendlyName(), // Scanner phone friendly identifier
      orientation: _isTestActive && packet.deviceId == _activeTargetDeviceId ? _activeOrientation : 'Default',
      obstruction: _isTestActive && packet.deviceId == _activeTargetDeviceId ? _activeObstruction : 'None',
      testDurationSeconds: _isTestActive && packet.deviceId == _activeTargetDeviceId ? _activeDurationSeconds : null,
    );

    _allRecords.add(record);

    // 3. Handle Role-Specific Processing:
    final currentRole = _storageService.getDeviceRole();
    if (currentRole == DeviceRole.tracked) {
      // We are the tracked device: recalculate our indoor position and room
      _localTrackedLocation = calculateDeviceLocation();
    } else if (currentRole == DeviceRole.anchor) {
      // We are an anchor node: if this packet is from a tracked device, report sighting to central server
      if (packet.role == 'TRACKED' || packet.deviceId.startsWith('TEST-C')) {
        _reportAnchorSighting(packet.deviceId, packet.rssi, estimatedDistance);
      }
    }

    // 4. If a test mode is active and this is the target device, record details
    if (_isTestActive && packet.deviceId == _activeTargetDeviceId) {
      if (_activeTestType == "Stability") {
        _activeStabilityRssiBuffer.add(packet.rssi);
        if (_activeStabilityTimeBuffer.isEmpty) {
          _activeStabilityTimeBuffer.add(0.0);
        } else {
          final double elapsed = DateTime.now().difference(record.timestamp).inMilliseconds.abs() / 1000.0;
          _activeStabilityTimeBuffer.add(_activeDurationSeconds - _testSecondsRemaining + elapsed);
        }
      }
    }

    notifyListeners();
  }

  void startTest({
    required String testType,
    required String targetDeviceId,
    required double actualDistance,
    required String orientation,
    required String obstruction,
    required int durationSeconds,
  }) {
    if (_isTestActive) return;

    _isTestActive = true;
    _activeTestType = testType;
    _activeTargetDeviceId = targetDeviceId;
    _activeActualDistance = actualDistance;
    _activeOrientation = orientation;
    _activeObstruction = obstruction;
    _activeDurationSeconds = durationSeconds;
    _testSecondsRemaining = durationSeconds;

    _activeStabilityRssiBuffer.clear();
    _activeStabilityTimeBuffer.clear();

    notifyListeners();

    // Countdown Timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_testSecondsRemaining > 0) {
        _testSecondsRemaining--;
        notifyListeners();
      } else {
        _countdownTimer?.cancel();
      }
    });

    // Test completion Timer
    _testTimer = Timer(Duration(seconds: durationSeconds), () {
      _completeTest();
    });
  }

  void _completeTest() {
    _isTestActive = false;
    _countdownTimer?.cancel();
    _testTimer?.cancel();

    if (_activeTestType == "AnchorCalibration") {
      _currentCalibrationMap = solveCoordinates();
      notifyListeners();
      return;
    }

    // Retrieve collected samples for the target device from raw records within the test window
    final DateTime startTime = DateTime.now().subtract(Duration(seconds: _activeDurationSeconds));
    
    final List<CSVRecord> testSamples = _allRecords
        .where((r) =>
            r.transmitterId == _activeTargetDeviceId &&
            r.timestamp.isAfter(startTime))
        .toList();

    final List<int> rssiList = testSamples.map((s) => s.rssi).toList();
    final RssiStats stats = _rssiProcessor.calculateStats(rssiList);

    // Calculate distance estimate based on mean or median RSSI
    // The prompt requires showing error metrics.
    double estDistance = 0.0;
    if (stats.sampleCount > 0) {
      // Use filtered median for calculation
      estDistance = _distanceEstimator.estimateDistance(stats.median);
    }
    
    final double absError = (estDistance - _activeActualDistance).abs();
    final double pctError = _activeActualDistance > 0 ? (absError / _activeActualDistance) * 100 : 0.0;

    final summary = TestSummary(
      testType: _activeTestType,
      targetDeviceId: _activeTargetDeviceId,
      actualDistance: _activeActualDistance,
      orientation: _activeOrientation,
      obstruction: _activeObstruction,
      durationSeconds: _activeDurationSeconds,
      sampleCount: stats.sampleCount,
      meanRssi: stats.mean,
      medianRssi: stats.median,
      rssiStdDev: stats.stdDev,
      estimatedDistance: estDistance,
      absoluteError: absError,
      percentageError: pctError,
      timestamp: DateTime.now(),
    );

    _testSummaries.add(summary);
    notifyListeners();
  }

  void stopActiveTest() {
    _completeTest();
  }

  void clearMeasurements() {
    _devices.forEach((key, device) {
      device.clear();
    });
    _allRecords.clear();
    _testSummaries.clear();
    _activeStabilityRssiBuffer.clear();
    _activeStabilityTimeBuffer.clear();
    notifyListeners();
  }

  Future<void> exportTestData() async {
    if (_allRecords.isEmpty) {
      throw Exception("No measurement data available to export.");
    }

    final List<List<dynamic>> csvData = [
      // CSV Headers
      [
        'timestamp',
        'scanner_id',
        'transmitter_id',
        'rssi',
        'tx_power',
        'sequence_number',
        'estimated_distance',
        'actual_distance_metadata',
        'phone_model_metadata',
        'orientation_metadata',
        'obstruction_metadata',
        'test_duration_metadata'
      ],
      // Row entries
      ..._allRecords.map((r) => r.toCsvRow()),
    ];

    final String csvString = const ListToCsvConverter().convert(csvData);

    try {
      final Directory directory = await getTemporaryDirectory();
      final String path = "${directory.path}/LIVS_BLE_Test_Data_${DateTime.now().millisecondsSinceEpoch}.csv";
      final File file = File(path);
      await file.writeAsString(csvString);

      // Share CSV File
      await Share.shareXFiles([XFile(file.path)], text: 'LIVS BLE Test Data Export');
    } catch (e) {
      debugPrint("Error exporting data: $e");
      rethrow;
    }
  }

  // --- Dynamic 3-Anchor Localization Solver & P2P Helpers ---

  double getDistanceToDevice(String targetId) {
    final device = _devices[targetId];
    if (device == null || device.rawRssiHistory.isEmpty) return 0.0;
    return device.getEstimatedDistance(_rssiProcessor, _distanceEstimator);
  }

  double getPairwiseDistance(String id1, String id2) {
    if (id1 == id2) return 0.0;
    final String selfId = _storageService.getDeviceId();
    if (selfId == id1) {
      final d = getDistanceToDevice(id2);
      if (d > 0) return d;
    } else if (selfId == id2) {
      final d = getDistanceToDevice(id1);
      if (d > 0) return d;
    }
    final key1 = '${id1}_$id2';
    if (_remoteDistances.containsKey(key1) && _remoteDistances[key1]! > 0) {
      return _remoteDistances[key1]!;
    }
    final key2 = '${id2}_$id1';
    if (_remoteDistances.containsKey(key2) && _remoteDistances[key2]! > 0) {
      return _remoteDistances[key2]!;
    }
    return 0.0;
  }

  List<MapEntry<int, int>> getTopScanDistances() {
    final activeDevices = _devices.values
        .where((d) => d.rawRssiHistory.isNotEmpty)
        .toList();
    activeDevices.sort((a, b) {
      final countA = a.getStats(_rssiProcessor).sampleCount;
      final countB = b.getStats(_rssiProcessor).sampleCount;
      return countB.compareTo(countA);
    });
    final List<MapEntry<int, int>> results = [];
    for (int i = 0; i < min(2, activeDevices.length); i++) {
      final dev = activeDevices[i];
      final distMeters = dev.getEstimatedDistance(_rssiProcessor, _distanceEstimator);
      if (distMeters > 0) {
        final indexMatch = RegExp(r'\d+').firstMatch(dev.deviceId);
        if (indexMatch != null) {
          final int idx = int.tryParse(indexMatch.group(0) ?? '') ?? 0;
          final int distDecimeters = (distMeters * 10).round().clamp(0, 255);
          if (idx > 0) {
            results.add(MapEntry(idx, distDecimeters));
          }
        }
      }
    }
    return results;
  }

  AnchorMap? solveCoordinates() {
    final String selfId = _storageService.getDeviceId();
    final List<String> activeIds = [selfId];
    final Map<String, double> scores = {selfId: 9999.0};

    for (final dev in _devices.values) {
      final stats = dev.getStats(_rssiProcessor);
      if (stats.sampleCount >= 3) { // Require at least 3 samples to be considered active
        final double stdDev = stats.stdDev;
        final double score = stats.sampleCount * max(0.1, 10.0 - stdDev).toDouble();
        scores[dev.deviceId] = score;
        activeIds.add(dev.deviceId);
      }
    }

    if (activeIds.length < 2) return null;

    activeIds.sort((a, b) => (scores[b] ?? 0.0).compareTo(scores[a] ?? 0.0));
    final String anchorIdA = activeIds[0];
    final String anchorIdB = activeIds[1];

    final double ab = getPairwiseDistance(anchorIdA, anchorIdB);
    if (ab <= 0.1) return null;

    if (activeIds.length == 2) {
      final List<AnchorCoordinate> solvedAnchors = [
        AnchorCoordinate(anchorId: anchorIdA, x: 0.0, y: 0.0),
        AnchorCoordinate(anchorId: anchorIdB, x: ab, y: 0.0),
      ];

      int minSamples = 999;
      double maxStdDev = 0.0;
      final dev = _devices[anchorIdB];
      if (dev != null) {
        final stats = dev.getStats(_rssiProcessor);
        minSamples = stats.sampleCount;
        maxStdDev = stats.stdDev;
      }
      if (minSamples == 999) minSamples = 30;

      final double fSamples = min(1.0, minSamples / 50.0);
      final double fRssi = max(0.0, 1.0 - maxStdDev / 8.0);
      final double confidence = fSamples * fRssi * 100.0;

      return AnchorMap(
        sessionId: 'SESS-${DateTime.now().millisecondsSinceEpoch}',
        timestamp: DateTime.now(),
        anchors: solvedAnchors,
        measuredPairwiseDistances: {
          'AB': ab,
        },
        overallCalibrationError: 0.0,
        confidence: confidence,
      );
    }

    final String anchorIdC = activeIds[2];
    final double ac = getPairwiseDistance(anchorIdA, anchorIdC);
    final double bc = getPairwiseDistance(anchorIdB, anchorIdC);

    if (ac <= 0.1 || bc <= 0.1) return null;

    final double ax = 0.0;
    final double ay = 0.0;
    final double bx = ab;
    final double by = 0.0;
    final double cx = (ac * ac + ab * ab - bc * bc) / (2.0 * ab);
    final double cy = sqrt(max(0.0, ac * ac - cx * cx));

    final List<AnchorCoordinate> solvedAnchors = [
      AnchorCoordinate(anchorId: anchorIdA, x: ax, y: ay),
      AnchorCoordinate(anchorId: anchorIdB, x: bx, y: by),
      AnchorCoordinate(anchorId: anchorIdC, x: cx, y: cy),
    ];

    for (int i = 3; i < activeIds.length; i++) {
      final String id = activeIds[i];
      final double rA = getPairwiseDistance(id, anchorIdA);
      final double rB = getPairwiseDistance(id, anchorIdB);
      final double rC = getPairwiseDistance(id, anchorIdC);

      if (rA > 0 && rB > 0) {
        final double x = (rA * rA + ab * ab - rB * rB) / (2.0 * ab);
        double y = 0.0;
        if (cy > 0.01) {
          y = (rA * rA + ac * ac - rC * rC - 2.0 * x * cx) / (2.0 * cy);
        } else {
          y = sqrt(max(0.0, rA * rA - x * x));
        }
        solvedAnchors.add(AnchorCoordinate(anchorId: id, x: x, y: y));
      }
    }

    double errBC = 0.0;
    final double calcBC = sqrt((cx - ab) * (cx - ab) + cy * cy);
    errBC = (calcBC - bc).abs();
    final double overallError = errBC / 3.0; // AB and AC reconstruction errors are 0 by design

    int minSamples = 999;
    double maxStdDev = 0.0;

    for (final id in [anchorIdA, anchorIdB, anchorIdC]) {
      if (id == selfId) continue;
      final dev = _devices[id];
      if (dev != null) {
        final stats = dev.getStats(_rssiProcessor);
        if (stats.sampleCount < minSamples) minSamples = stats.sampleCount;
        if (stats.stdDev > maxStdDev) maxStdDev = stats.stdDev;
      }
    }
    if (minSamples == 999) minSamples = 30;

    final double fSamples = min(1.0, minSamples / 50.0);
    final double fRssi = max(0.0, 1.0 - maxStdDev / 8.0);
    final double fGeom = max(0.0, 1.0 - overallError / 2.0);
    final double confidence = fSamples * fRssi * fGeom * 100.0;

    return AnchorMap(
      sessionId: 'SESS-${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      anchors: solvedAnchors,
      measuredPairwiseDistances: {
        'AB': ab,
        'AC': ac,
        'BC': bc,
      },
      overallCalibrationError: overallError,
      confidence: confidence,
    );
  }

  Future<void> acceptAndLockAnchorMap(AnchorMap map) async {
    _lockedAnchorMap = map;
    _currentCalibrationMap = null;
    final jsonString = json.encode(map.toJson());
    await _storageService.saveAnchorMap(jsonString);
    notifyListeners();
  }

  Future<void> recalibrateAnchorMap() async {
    _lockedAnchorMap = null;
    _currentCalibrationMap = null;
    await _storageService.clearAnchorMap();
    notifyListeners();
  }

  void _reportAnchorSighting(String targetDeviceId, int rssi, double distance) {
    if (centralServerService == null) return;
    final report = AnchorReport(
      anchorId: _storageService.getDeviceId(),
      roomName: _storageService.getAssignedRoom(),
      anchorX: _storageService.getAnchorX(),
      anchorY: _storageService.getAnchorY(),
      targetDeviceId: targetDeviceId,
      rssi: rssi,
      distance: distance,
      timestamp: DateTime.now(),
    );

    if (centralServerService!.isServerRunning) {
      centralServerService!.addDirectReport(report);
    } else {
      final host = _storageService.getServerHost();
      final port = _storageService.getServerPort();
      if (host.isNotEmpty) {
        centralServerService!.sendAnchorReportToServer(
          serverHost: host,
          serverPort: port,
          report: report,
        );
      }
    }
  }

  TrackedLocation? calculateDeviceLocation() {
    final String localId = _storageService.getDeviceId();
    final List<BleDevice> anchorDevices = _devices.values
        .where((d) => d.role == 'ANCHOR' || d.deviceId.startsWith('TEST-A'))
        .where((d) => d.rawRssiHistory.isNotEmpty)
        .toList();

    if (anchorDevices.isEmpty) return null;

    // Room resolution: room of nearest/majority anchors
    final Map<String, int> roomCounts = {};
    for (var a in anchorDevices) {
      roomCounts[a.roomName] = (roomCounts[a.roomName] ?? 0) + 1;
    }
    String resolvedRoom = _storageService.getAssignedRoom();
    int maxCount = 0;
    roomCounts.forEach((r, c) {
      if (c > maxCount) {
        maxCount = c;
        resolvedRoom = r;
      }
    });

    final Map<String, AnchorCoordinate> anchorCoords = {};
    if (_lockedAnchorMap != null) {
      for (var a in _lockedAnchorMap!.anchors) {
        anchorCoords[a.anchorId] = a;
      }
    }

    final defaultPositions = [
      const Offset(0.0, 0.0),
      const Offset(6.0, 0.0),
      const Offset(3.0, 5.0),
      const Offset(0.0, 5.0),
      const Offset(6.0, 5.0),
    ];

    double weightedX = 0.0;
    double weightedY = 0.0;
    double totalWeight = 0.0;
    String nearestAnchor = anchorDevices.first.deviceId;
    double nearestDist = 999.0;

    for (int i = 0; i < anchorDevices.length; i++) {
      final dev = anchorDevices[i];
      final dist = dev.getEstimatedDistance(_rssiProcessor, _distanceEstimator);
      if (dist <= 0) continue;

      if (dist < nearestDist) {
        nearestDist = dist;
        nearestAnchor = dev.deviceId;
      }

      double ax = 0.0;
      double ay = 0.0;
      if (anchorCoords.containsKey(dev.deviceId)) {
        ax = anchorCoords[dev.deviceId]!.x;
        ay = anchorCoords[dev.deviceId]!.y;
      } else {
        final fallback = defaultPositions[i % defaultPositions.length];
        ax = fallback.dx;
        ay = fallback.dy;
      }

      final double weight = 1.0 / max(0.2, dist * dist);
      weightedX += ax * weight;
      weightedY += ay * weight;
      totalWeight += weight;
    }

    if (totalWeight <= 0) return null;

    final double solvedX = weightedX / totalWeight;
    final double solvedY = weightedY / totalWeight;
    final double confidence = min(98.0, 45.0 + anchorDevices.length * 18.0);

    return TrackedLocation(
      deviceId: localId,
      x: solvedX,
      y: solvedY,
      roomName: resolvedRoom,
      confidence: confidence,
      nearestAnchorId: nearestAnchor,
      nearestDistance: nearestDist < 900 ? nearestDist : 1.0,
      timestamp: DateTime.now(),
      source: 'BLE_LOCAL',
    );
  }

  Future<void> calibrateAtOneMeter(String targetDeviceId) async {
    final dev = _devices[targetDeviceId];
    if (dev == null || dev.rawRssiHistory.isEmpty) {
      throw Exception("No signal received from $targetDeviceId. Make sure device is nearby.");
    }

    final stats = dev.getStats(_rssiProcessor);
    final double calibratedRssi0 = stats.median.clamp(-85.0, -45.0);
    await _storageService.setRssi0(calibratedRssi0);
    await _storageService.setD0(1.0);
    reloadConfig();
  }

  Future<void> setPathLossEnvironment(double n) async {
    final double safeN = n.clamp(1.9, 3.2);
    await _storageService.setPathLossN(safeN);
    reloadConfig();
  }

  @override
  void dispose() {
    _testTimer?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}
