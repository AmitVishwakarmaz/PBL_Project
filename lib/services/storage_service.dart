import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static const String keyDeviceIndex = 'device_index';
  static const String keyFriendlyName = 'friendly_name';
  static const String keyPathLossN = 'path_loss_n';
  static const String keyRssi0 = 'rssi0';
  static const String keyD0 = 'd0';
  static const String keyAnchorMap = 'anchor_map';

  final SharedPreferences _prefs;

  StorageService(this._prefs);

  static Future<StorageService> init() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final service = StorageService(prefs);
    await service._ensureDefaults();
    return service;
  }

  Future<void> _ensureDefaults() async {
    if (!_prefs.containsKey(keyDeviceIndex)) {
      // Generate a random default device index between 1 and 100 on first launch
      final int randIndex = Random().nextInt(100) + 1;
      await _prefs.setInt(keyDeviceIndex, randIndex);
    }
    if (!_prefs.containsKey(keyFriendlyName)) {
      // e.g. Phone A
      final int index = getDeviceIndex();
      await _prefs.setString(keyFriendlyName, 'Phone ${String.fromCharCode(64 + (index % 26 == 0 ? 26 : index % 26))}');
    }
    if (!_prefs.containsKey(keyPathLossN)) {
      await _prefs.setDouble(keyPathLossN, 2.5);
    }
    if (!_prefs.containsKey(keyRssi0)) {
      await _prefs.setDouble(keyRssi0, -50.0);
    }
    if (!_prefs.containsKey(keyD0)) {
      await _prefs.setDouble(keyD0, 1.0);
    }
  }

  // Getters
  int getDeviceIndex() => _prefs.getInt(keyDeviceIndex) ?? 1;
  
  String getDeviceId() {
    final int index = getDeviceIndex();
    return 'TEST-A${index.toString().padLeft(3, '0')}';
  }

  String getFriendlyName() => _prefs.getString(keyFriendlyName) ?? 'Phone A';

  double getPathLossN() => _prefs.getDouble(keyPathLossN) ?? 2.0;

  double getRssi0() => _prefs.getDouble(keyRssi0) ?? -60.0;

  double getD0() => _prefs.getDouble(keyD0) ?? 1.0;

  // Setters
  Future<void> setDeviceIndex(int index) async {
    await _prefs.setInt(keyDeviceIndex, index);
  }

  Future<void> setFriendlyName(String name) async {
    await _prefs.setString(keyFriendlyName, name);
  }

  Future<void> setPathLossN(double n) async {
    await _prefs.setDouble(keyPathLossN, n);
  }

  Future<void> setRssi0(double rssi0) async {
    await _prefs.setDouble(keyRssi0, rssi0);
  }

  Future<void> setD0(double d0) async {
    await _prefs.setDouble(keyD0, d0);
  }

  Future<void> saveAnchorMap(String jsonString) async {
    await _prefs.setString(keyAnchorMap, jsonString);
  }

  String? getAnchorMap() {
    return _prefs.getString(keyAnchorMap);
  }

  Future<void> clearAnchorMap() async {
    await _prefs.remove(keyAnchorMap);
  }

  Future<void> resetAll() async {
    await _prefs.clear();
    await _ensureDefaults();
  }
}
