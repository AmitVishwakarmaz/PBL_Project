import '../utils/rssi_processor.dart';
import '../utils/distance_estimator.dart';

class BleDevice {
  final String deviceId;       // e.g. "TEST-A001"
  String friendlyName;         // e.g. "Phone A"
  final List<int> rawRssiHistory = [];
  final List<DateTime> timestamps = [];
  int? txPower;
  int? lastSequenceNumber;
  DateTime lastSeen;

  static const int maxHistorySize = 100; // Rolling window capacity

  BleDevice({
    required this.deviceId,
    required this.friendlyName,
    required this.lastSeen,
    int? rssi,
    this.txPower,
    this.lastSequenceNumber,
  }) {
    if (rssi != null) {
      addRssi(rssi, txPower: txPower, sequenceNumber: lastSequenceNumber);
    }
  }

  void addRssi(int rssi, {int? txPower, int? sequenceNumber}) {
    if (rawRssiHistory.length >= maxHistorySize) {
      rawRssiHistory.removeAt(0);
      timestamps.removeAt(0);
    }
    rawRssiHistory.add(rssi);
    timestamps.add(DateTime.now());
    lastSeen = DateTime.now();
    
    if (txPower != null) {
      this.txPower = txPower;
    }
    if (sequenceNumber != null) {
      lastSequenceNumber = sequenceNumber;
    }
  }

  void clear() {
    rawRssiHistory.clear();
    timestamps.clear();
  }

  List<double> getFilteredRssiHistory(RssiProcessor processor) {
    return processor.processRssi(rawRssiHistory);
  }

  double? getLatestFilteredRssi(RssiProcessor processor) {
    final filtered = getFilteredRssiHistory(processor);
    return filtered.isNotEmpty ? filtered.last : null;
  }

  RssiStats getStats(RssiProcessor processor) {
    return processor.calculateStats(rawRssiHistory);
  }

  double getEstimatedDistance(RssiProcessor processor, DistanceEstimator estimator) {
    final double? filteredRssi = getLatestFilteredRssi(processor);
    if (filteredRssi == null) return 0.0;
    return estimator.estimateDistance(filteredRssi);
  }
}
