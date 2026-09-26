import 'dart:math';

class DistanceEstimator {
  final double d0;     // Reference distance, usually 1.0 meter
  final double rssi0;  // Reference RSSI at reference distance (e.g. -50 to -70)
  final double n;      // Path loss exponent (typically 2.0 in free space, 3.0-4.0 in buildings)

  DistanceEstimator({
    this.d0 = 1.0,
    this.rssi0 = -50.0, // More typical default for phone-to-phone BLE at 1m
    this.n = 2.5,       // More realistic default for indoor conditions
  });

  /// Estimates the distance based on raw or filtered RSSI using the Log-Distance Path-Loss model:
  /// d = d0 * 10^((rssi0 - RSSI) / (10 * n))
  double estimateDistance(double rssi) {
    if (rssi >= 0) return 0.1; // Invalid RSSI
    // Clamp RSSI to prevent extreme exponents
    final double clampedRssi = rssi.clamp(-100.0, -30.0);
    final double exponent = (rssi0 - clampedRssi) / (10.0 * n);
    final double rawDistance = d0 * pow(10.0, exponent);
    // Clamp distance output between 0.1m and 30m
    return rawDistance.clamp(0.1, 30.0);
  }

  /// Calculates the Path Loss Exponent 'n' given a measured RSSI at a known distance.
  /// n = (rssi0 - RSSI) / (10 * log10(d / d0))
  static double calculatePathLossExponent({
    required double rssi0,
    required double measuredRssi,
    required double actualDistance,
    double d0 = 1.0,
  }) {
    if (actualDistance <= 0 || d0 <= 0 || actualDistance == d0) {
      return 2.5; // Fallback or invalid input
    }
    final double ratio = actualDistance / d0;
    final double logRatio = log(ratio) / ln10; // log10
    final double exponent = (rssi0 - measuredRssi) / (10.0 * logRatio);
    // Clamp the computed exponent to standard physical propagation bounds (1.2 to 6.0)
    return exponent.clamp(1.2, 6.0);
  }
}
