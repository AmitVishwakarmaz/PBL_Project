import 'dart:math';

class DistanceEstimator {
  final double d0;     // Reference distance, usually 1.0 meter
  final double rssi0;  // Reference RSSI at reference distance (typical phone-to-phone BLE at 1m is -60 to -68 dBm)
  final double n;      // Path loss exponent (typically 2.0 to 2.8 indoors)

  DistanceEstimator({
    this.d0 = 1.0,
    this.rssi0 = -64.0, // Realistic baseline for modern smartphones at 1 meter
    this.n = 2.4,       // Standard robust default for indoor rooms
  });

  /// Estimates the distance based on filtered RSSI using the Log-Distance Path-Loss model:
  /// d = d0 * 10^((rssi0 - RSSI) / (10 * n))
  /// Strictly clamped to physically realistic indoor limits (0.2m to 15.0m) to prevent 10s of meters error blowups.
  double estimateDistance(double rssi) {
    if (rssi >= 0) return 0.2; // Invalid RSSI
    
    // Clamp RSSI to reasonable physical radio thresholds
    final double clampedRssi = rssi.clamp(-95.0, -35.0);
    final double safeN = n.clamp(1.9, 3.2);
    final double exponent = (rssi0 - clampedRssi) / (10.0 * safeN);
    final double rawDistance = d0 * pow(10.0, exponent);
    
    // Strict realistic indoor room bounds (0.2m to 15.0m)
    return rawDistance.clamp(0.2, 15.0);
  }

  /// Calculates the Path Loss Exponent 'n' given a measured RSSI at a known distance.
  /// If calibrated at 1.0m, returns 2.4 (since 1m calibrates rssi0 instead).
  static double calculatePathLossExponent({
    required double rssi0,
    required double measuredRssi,
    required double actualDistance,
    double d0 = 1.0,
  }) {
    if (actualDistance <= 0 || d0 <= 0 || (actualDistance - d0).abs() < 0.2) {
      return 2.4; // At reference distance (1m), exponent is invariant; rssi0 is the calibrated parameter
    }
    final double ratio = actualDistance / d0;
    final double logRatio = log(ratio) / ln10; // log10
    final double exponent = (rssi0 - measuredRssi) / (10.0 * logRatio);
    // Clamp the computed exponent to standard indoor bounds (1.9 to 3.2)
    return exponent.clamp(1.9, 3.2);
  }
}

