import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

enum DeviceRole {
  anchor,
  tracked,
}

class StorageService {
  static const String keyDeviceRole = 'device_role';
  static const String keyDeviceIndex = 'device_index';
  static const String keyFriendlyName = 'friendly_name';
  static const String keyAssignedRoom = 'assigned_room';
  static const String keyAnchorX = 'anchor_x';
  static const String keyAnchorY = 'anchor_y';
  static const String keyServerHost = 'server_host';
  static const String keyServerPort = 'server_port';
  static const String keyIsHostingServer = 'is_hosting_server';

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
      final int randIndex = Random().nextInt(50) + 1;
      await _prefs.setInt(keyDeviceIndex, randIndex);
    }
    if (!_prefs.containsKey(keyFriendlyName)) {
      final int index = getDeviceIndex();
      await _prefs.setString(keyFriendlyName, 'Anchor $index');
    }
    if (!_prefs.containsKey(keyAssignedRoom)) {
      await _prefs.setString(keyAssignedRoom, 'Room A');
    }
    if (!_prefs.containsKey(keyAnchorX)) {
      await _prefs.setDouble(keyAnchorX, 0.0);
    }
    if (!_prefs.containsKey(keyAnchorY)) {
      await _prefs.setDouble(keyAnchorY, 0.0);
    }
    if (!_prefs.containsKey(keyServerHost) || _prefs.getString(keyServerHost) == '127.0.0.1') {
      await _prefs.setString(keyServerHost, '192.168.0.100');
    }
    if (!_prefs.containsKey(keyServerPort)) {
      await _prefs.setInt(keyServerPort, 8080);
    }
    if (!_prefs.containsKey(keyPathLossN)) {
      await _prefs.setDouble(keyPathLossN, 2.4);
    }
    if (!_prefs.containsKey(keyRssi0)) {
      await _prefs.setDouble(keyRssi0, -64.0);
    }
    if (!_prefs.containsKey(keyD0)) {
      await _prefs.setDouble(keyD0, 1.0);
    }
  }

  // Getters
  DeviceRole? getDeviceRole() {
    final val = _prefs.getString(keyDeviceRole);
    if (val == 'anchor') return DeviceRole.anchor;
    if (val == 'tracked') return DeviceRole.tracked;
    return null; // Not selected yet
  }

  int getDeviceIndex() => _prefs.getInt(keyDeviceIndex) ?? 1;
  
  String getDeviceId() {
    final role = getDeviceRole();
    final int index = getDeviceIndex();
    if (role == DeviceRole.anchor) {
      return 'TEST-A${index.toString().padLeft(3, '0')}';
    } else {
      return 'TEST-C${index.toString().padLeft(3, '0')}';
    }
  }

  String getFriendlyName() {
    final role = getDeviceRole();
    final defaultName = role == DeviceRole.anchor ? 'Anchor ${getDeviceIndex()}' : 'Tracked Device ${getDeviceIndex()}';
    return _prefs.getString(keyFriendlyName) ?? defaultName;
  }

  String getAssignedRoom() => _prefs.getString(keyAssignedRoom) ?? 'Room A';

  double getAnchorX() => _prefs.getDouble(keyAnchorX) ?? 0.0;
  double getAnchorY() => _prefs.getDouble(keyAnchorY) ?? 0.0;

  String getServerHost() {
    final host = _prefs.getString(keyServerHost);
    if (host == null || host.isEmpty) {
      return '192.168.0.100';
    }
    return host;
  }
  int getServerPort() => _prefs.getInt(keyServerPort) ?? 8080;
  bool isHostingServer() => _prefs.getBool(keyIsHostingServer) ?? false;

  /// Sanitizes and extracts (host, port) from user input
  /// Handles: "192.168.1.50", "192.168.1.50:8080", "http://192.168.1.50:8080/..."
  static ({String host, int port}) parseServerAddress(String input, {int defaultPort = 8080}) {
    String cleaned = input.trim();
    if (cleaned.startsWith('http://')) {
      cleaned = cleaned.substring(7);
    } else if (cleaned.startsWith('https://')) {
      cleaned = cleaned.substring(8);
    }
    cleaned = cleaned.split('/')[0].trim();
    if (cleaned.contains(':')) {
      final parts = cleaned.split(':');
      final host = parts[0].trim();
      final port = int.tryParse(parts[1].trim()) ?? defaultPort;
      return (host: host.isEmpty ? '192.168.0.100' : host, port: port);
    }
    return (host: cleaned.isEmpty ? '192.168.0.100' : cleaned, port: defaultPort);
  }

  double getPathLossN() => _prefs.getDouble(keyPathLossN) ?? 2.4;
  double getRssi0() => _prefs.getDouble(keyRssi0) ?? -64.0;
  double getD0() => _prefs.getDouble(keyD0) ?? 1.0;

  String? getAnchorMap() => _prefs.getString(keyAnchorMap);

  // Setters
  Future<void> setDeviceRole(DeviceRole role) async {
    await _prefs.setString(keyDeviceRole, role == DeviceRole.anchor ? 'anchor' : 'tracked');
  }

  Future<void> clearDeviceRole() async {
    await _prefs.remove(keyDeviceRole);
  }

  Future<void> setDeviceIndex(int index) async {
    await _prefs.setInt(keyDeviceIndex, index);
  }

  Future<void> setFriendlyName(String name) async {
    await _prefs.setString(keyFriendlyName, name);
  }

  Future<void> setAssignedRoom(String room) async {
    await _prefs.setString(keyAssignedRoom, room);
  }

  Future<void> setAnchorCoordinates(double x, double y) async {
    await _prefs.setDouble(keyAnchorX, x);
    await _prefs.setDouble(keyAnchorY, y);
  }

  Future<void> setServerHost(String host) async {
    await _prefs.setString(keyServerHost, host);
  }

  Future<void> setServerPort(int port) async {
    await _prefs.setInt(keyServerPort, port);
  }

  Future<void> setIsHostingServer(bool hosting) async {
    await _prefs.setBool(keyIsHostingServer, hosting);
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

  Future<void> clearAnchorMap() async {
    await _prefs.remove(keyAnchorMap);
  }

  Future<void> resetAll() async {
    await _prefs.clear();
    await _ensureDefaults();
  }
}
