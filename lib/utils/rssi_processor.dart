import 'dart:math';

class RssiStats {
  final int sampleCount;
  final double mean;
  final double median;
  final double min;
  final double max;
  final double stdDev;
  final double variance;

  RssiStats({
    required this.sampleCount,
    required this.mean,
    required this.median,
    required this.min,
    required this.max,
    required this.stdDev,
    required this.variance,
  });

  factory RssiStats.empty() {
    return RssiStats(
      sampleCount: 0,
      mean: 0.0,
      median: 0.0,
      min: 0.0,
      max: 0.0,
      stdDev: 0.0,
      variance: 0.0,
    );
  }
}

class RssiProcessor {
  final int minValidRssi;
  final int maxValidRssi;
  final int medianWindowSize;
  final int movingAverageWindowSize;

  RssiProcessor({
    this.minValidRssi = -100,
    this.maxValidRssi = -20,
    this.medianWindowSize = 5,
    this.movingAverageWindowSize = 10,
  });

  /// Processes raw RSSI samples and returns the list of filtered RSSI values
  /// step-by-step: Rejection -> Median Filter -> Moving Average.
  List<double> processRssi(List<int> rawSamples) {
    // 1. Invalid-value rejection
    final List<int> validSamples = rawSamples
        .where((rssi) =>
            rssi >= minValidRssi && rssi <= maxValidRssi && rssi != 127)
        .toList();

    if (validSamples.isEmpty) return [];

    // 2. Trailing Median Filter
    final List<double> medianFiltered = [];
    for (int i = 0; i < validSamples.length; i++) {
      final int start = max(0, i - medianWindowSize + 1);
      final List<int> window = validSamples.sublist(start, i + 1);
      medianFiltered.add(_calculateMedianOfInts(window));
    }

    // 3. Moving Average of the Median-Filtered values
    final List<double> movingAverage = [];
    for (int i = 0; i < medianFiltered.length; i++) {
      final int start = max(0, i - movingAverageWindowSize + 1);
      final List<double> window = medianFiltered.sublist(start, i + 1);
      final double sum = window.fold(0.0, (prev, element) => prev + element);
      movingAverage.add(sum / window.length);
    }

    return movingAverage;
  }

  /// Calculates statistics for a list of raw RSSI samples (rejection is applied first)
  RssiStats calculateStats(List<int> rawSamples) {
    // 1. Apply rejection first to get valid samples
    final List<int> validSamples = rawSamples
        .where((rssi) =>
            rssi >= minValidRssi && rssi <= maxValidRssi && rssi != 127)
        .toList();

    if (validSamples.isEmpty) {
      return RssiStats.empty();
    }

    final int count = validSamples.length;
    final double sum = validSamples.fold(0.0, (prev, element) => prev + element);
    final double mean = sum / count;

    final double median = _calculateMedianOfInts(validSamples);

    final double minVal = validSamples.reduce(min).toDouble();
    final double maxVal = validSamples.reduce(max).toDouble();

    double sumSqDiff = 0.0;
    for (var val in validSamples) {
      sumSqDiff += pow(val - mean, 2);
    }

    // Use N-1 sample variance, fallback to population variance if count <= 1
    final double variance = count > 1 ? sumSqDiff / (count - 1) : sumSqDiff / count;
    final double stdDev = sqrt(variance);

    return RssiStats(
      sampleCount: count,
      mean: mean,
      median: median,
      min: minVal,
      max: maxVal,
      stdDev: stdDev,
      variance: variance,
    );
  }

  double _calculateMedianOfInts(List<int> list) {
    if (list.isEmpty) return 0.0;
    final List<int> sorted = List.from(list)..sort();
    final int middle = sorted.length ~/ 2;
    if (sorted.length % 2 == 1) {
      return sorted[middle].toDouble();
    } else {
      return (sorted[middle - 1] + sorted[middle]) / 2.0;
    }
  }
}
