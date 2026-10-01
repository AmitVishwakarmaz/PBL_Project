
class AnchorCoordinate {
  final String anchorId; // e.g. "TEST-A001"
  final double x;        // in meters
  final double y;        // in meters
  final String roomName; // e.g. "Room A"

  AnchorCoordinate({
    required this.anchorId,
    required this.x,
    required this.y,
    this.roomName = 'Room A',
  });

  Map<String, dynamic> toJson() {
    return {
      'anchorId': anchorId,
      'x': x,
      'y': y,
      'roomName': roomName,
    };
  }

  factory AnchorCoordinate.fromJson(Map<String, dynamic> json) {
    return AnchorCoordinate(
      anchorId: json['anchorId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      roomName: json['roomName'] as String? ?? 'Room A',
    );
  }
}

class TrackedLocation {
  final String deviceId;
  final double x;
  final double y;
  final String roomName;
  final double confidence; // 0 to 100%
  final String nearestAnchorId;
  final double nearestDistance;
  final DateTime timestamp;
  final String source; // "BLE_LOCAL" or "CENTRAL_SERVER"

  TrackedLocation({
    required this.deviceId,
    required this.x,
    required this.y,
    required this.roomName,
    required this.confidence,
    required this.nearestAnchorId,
    required this.nearestDistance,
    required this.timestamp,
    this.source = 'BLE_LOCAL',
  });

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'x': x,
      'y': y,
      'roomName': roomName,
      'confidence': confidence,
      'nearestAnchorId': nearestAnchorId,
      'nearestDistance': nearestDistance,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
    };
  }

  factory TrackedLocation.fromJson(Map<String, dynamic> json) {
    return TrackedLocation(
      deviceId: json['deviceId'] as String? ?? 'Unknown',
      x: (json['x'] as num?)?.toDouble() ?? 0.0,
      y: (json['y'] as num?)?.toDouble() ?? 0.0,
      roomName: json['roomName'] as String? ?? 'Room A',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 50.0,
      nearestAnchorId: json['nearestAnchorId'] as String? ?? 'Anchor',
      nearestDistance: (json['nearestDistance'] as num?)?.toDouble() ?? 1.0,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      source: json['source'] as String? ?? 'CENTRAL_SERVER',
    );
  }
}

class AnchorMap {
  final String sessionId;
  final DateTime timestamp;
  final List<AnchorCoordinate> anchors;
  final Map<String, double> measuredPairwiseDistances; // keys: "AB", "AC", "BC"
  final double overallCalibrationError;
  final double confidence;
  final String primaryRoom;

  AnchorMap({
    required this.sessionId,
    required this.timestamp,
    required this.anchors,
    required this.measuredPairwiseDistances,
    required this.overallCalibrationError,
    required this.confidence,
    this.primaryRoom = 'Room A',
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'timestamp': timestamp.toIso8601String(),
      'anchors': anchors.map((a) => a.toJson()).toList(),
      'measuredPairwiseDistances': measuredPairwiseDistances,
      'overallCalibrationError': overallCalibrationError,
      'confidence': confidence,
      'primaryRoom': primaryRoom,
    };
  }

  factory AnchorMap.fromJson(Map<String, dynamic> json) {
    final List<dynamic> anchorsJson = json['anchors'] as List<dynamic>? ?? [];
    final Map<String, dynamic> distancesJson = json['measuredPairwiseDistances'] as Map<String, dynamic>? ?? {};

    return AnchorMap(
      sessionId: json['sessionId'] as String? ?? 'SESS-0',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      anchors: anchorsJson.map((a) => AnchorCoordinate.fromJson(a as Map<String, dynamic>)).toList(),
      measuredPairwiseDistances: distancesJson.map((key, value) => MapEntry(key, (value as num).toDouble())),
      overallCalibrationError: (json['overallCalibrationError'] as num?)?.toDouble() ?? 0.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 75.0,
      primaryRoom: json['primaryRoom'] as String? ?? 'Room A',
    );
  }
}
