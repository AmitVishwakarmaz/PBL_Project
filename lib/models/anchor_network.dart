class AnchorCoordinate {
  final String anchorId; // e.g. "TEST-A001"
  final double x;        // in meters
  final double y;        // in meters

  AnchorCoordinate({
    required this.anchorId,
    required this.x,
    required this.y,
  });

  Map<String, dynamic> toJson() {
    return {
      'anchorId': anchorId,
      'x': x,
      'y': y,
    };
  }

  factory AnchorCoordinate.fromJson(Map<String, dynamic> json) {
    return AnchorCoordinate(
      anchorId: json['anchorId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
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

  AnchorMap({
    required this.sessionId,
    required this.timestamp,
    required this.anchors,
    required this.measuredPairwiseDistances,
    required this.overallCalibrationError,
    required this.confidence,
  });

  Map<String, dynamic> toJson() {
    return {
      'sessionId': sessionId,
      'timestamp': timestamp.toIso8601String(),
      'anchors': anchors.map((a) => a.toJson()).toList(),
      'measuredPairwiseDistances': measuredPairwiseDistances,
      'overallCalibrationError': overallCalibrationError,
      'confidence': confidence,
    };
  }

  factory AnchorMap.fromJson(Map<String, dynamic> json) {
    final List<dynamic> anchorsJson = json['anchors'] as List<dynamic>;
    final Map<String, dynamic> distancesJson = json['measuredPairwiseDistances'] as Map<String, dynamic>;

    return AnchorMap(
      sessionId: json['sessionId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      anchors: anchorsJson.map((a) => AnchorCoordinate.fromJson(a as Map<String, dynamic>)).toList(),
      measuredPairwiseDistances: distancesJson.map((key, value) => MapEntry(key, (value as num).toDouble())),
      overallCalibrationError: (json['overallCalibrationError'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
    );
  }
}
