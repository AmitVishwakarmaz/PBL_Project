import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';
import 'storage_service.dart';

class BleAdvertiser extends ChangeNotifier {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  final StorageService _storageService;

  bool _isAdvertising = false;
  bool _isSupported = false;
  int _packetsSent = 0;
  int _sequenceNumber = 0;
  Timer? _sequenceTimer;

  bool get isAdvertising => _isAdvertising;
  bool get isSupported => _isSupported;
  int get packetsSent => _packetsSent;
  int get sequenceNumber => _sequenceNumber;

  List<MapEntry<int, int>> Function()? getTopScanDistances;

  BleAdvertiser(this._storageService) {
    _checkSupport();
    // Listen to peripheral state changes if available
    _peripheral.onPeripheralStateChanged?.listen((state) {
      _isAdvertising = state == PeripheralState.advertising;
      notifyListeners();
    });
  }

  Future<void> _checkSupport() async {
    try {
      _isSupported = await _peripheral.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking BLE peripheral support: $e');
      _isSupported = false;
      notifyListeners();
    }
  }

  /// Builds the custom manufacturer data payload:
  /// Byte 0-1: Protocol ID (0x5A43)
  /// Byte 2: Version (1)
  /// Byte 3: Role (0x54 - 'T')
  /// Byte 4-5: Device index (16-bit)
  /// Byte 6: Sequence number (8-bit)
  /// Byte 7: Target 1 Index (8-bit)
  /// Byte 8: Target 1 Distance (8-bit decimeters)
  /// Byte 9: Target 2 Index (8-bit)
  /// Byte 10: Target 2 Distance (8-bit decimeters)
  List<int> _buildManufacturerData() {
    final int index = _storageService.getDeviceIndex();
    
    int target1Idx = 0;
    int target1Dist = 0;
    int target2Idx = 0;
    int target2Dist = 0;
    
    if (getTopScanDistances != null) {
      final list = getTopScanDistances!();
      if (list.isNotEmpty) {
        target1Idx = list[0].key.clamp(0, 255);
        target1Dist = list[0].value.clamp(0, 255);
      }
      if (list.length > 1) {
        target2Idx = list[1].key.clamp(0, 255);
        target2Dist = list[1].value.clamp(0, 255);
      }
    }

    final List<int> data = [
      0x5A, 0x43, // Protocol ID: 'Z', 'C'
      0x01,       // Version 1
      0x54,       // Role 'T' (TEST)
      (index >> 8) & 0xFF,
      index & 0xFF,
      _sequenceNumber & 0xFF,
      target1Idx,
      target1Dist,
      target2Idx,
      target2Dist,
    ];
    return data;
  }

  Future<void> startAdvertising() async {
    if (!_isSupported) {
      await _checkSupport();
      if (!_isSupported) {
        throw Exception("BLE Advertising is not supported on this device.");
      }
    }

    _sequenceNumber = 0;
    _packetsSent = 0;
    
    await _advertise();
    
    // Start a timer to periodically increment sequence number and update advertisement payload
    _sequenceTimer?.cancel();
    _sequenceTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_isAdvertising) {
        _sequenceNumber = (_sequenceNumber + 1) % 256;
        _packetsSent++;
        await _advertise();
        notifyListeners();
      }
    });

    _isAdvertising = true;
    notifyListeners();
  }

  Future<void> _advertise() async {
    try {
      final List<int> manData = _buildManufacturerData();
      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
        manufacturerId: 0xFFFF, // Custom Manufacturer ID for testing
        manufacturerData: Uint8List.fromList(manData),
        localName: _storageService.getFriendlyName(),
        includeDeviceName: true,
      );
      
      // Stop advertising first if active to release native BLE slots on Android
      try {
        await _peripheral.stop();
      } catch (_) {}
      
      await _peripheral.start(advertiseData: advertiseData);
    } catch (e) {
      debugPrint('Error starting BLE advertisement: $e');
      rethrow;
    }
  }

  Future<void> stopAdvertising() async {
    _sequenceTimer?.cancel();
    _sequenceTimer = null;
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('Error stopping BLE advertisement: $e');
    }
    _isAdvertising = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sequenceTimer?.cancel();
    super.dispose();
  }
}
