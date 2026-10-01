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

  bool _isCheckingSupport = false;

  BleAdvertiser(this._storageService) {
    // Safely check support asynchronously without throwing
    Future.microtask(() => _checkSupport());
    try {
      _peripheral.onPeripheralStateChanged?.listen((state) {
        _isAdvertising = state == PeripheralState.advertising;
        notifyListeners();
      }, onError: (e) {
        debugPrint('Peripheral state listener error: $e');
      });
    } catch (e) {
      debugPrint('Error attaching peripheral state listener: $e');
    }
  }

  Future<void> _checkSupport() async {
    if (_isCheckingSupport) return;
    _isCheckingSupport = true;
    try {
      _isSupported = await _peripheral.isSupported;
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking BLE peripheral support: $e');
      _isSupported = false;
      notifyListeners();
    } finally {
      _isCheckingSupport = false;
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
    final role = _storageService.getDeviceRole();
    final int roleByte = role == DeviceRole.anchor ? 0x41 : (role == DeviceRole.tracked ? 0x43 : 0x54);
    
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
      roleByte,   // Role 'A' (Anchor), 'C' (Central/Tracked), or 'T'
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

  bool _isAdvertisingOperationInProgress = false;

  Future<void> startAdvertising() async {
    if (_isAdvertisingOperationInProgress) return;
    _isAdvertisingOperationInProgress = true;

    try {
      if (!_isSupported) {
        await _checkSupport();
        if (!_isSupported) {
          debugPrint("BLE Advertising is not supported or Bluetooth is disabled.");
          _isAdvertising = false;
          notifyListeners();
          return;
        }
      }

      // Cleanly stop any lingering or previous advertisement first
      try {
        await _peripheral.stop();
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (_) {}

      _sequenceNumber = 0;
      _packetsSent = 0;
      
      await _advertise();
      
      // Update packet counters without repeatedly calling startAdvertisingSet on the hardware radio
      _sequenceTimer?.cancel();
      _sequenceTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
        if (_isAdvertising) {
          _sequenceNumber = (_sequenceNumber + 1) % 256;
          _packetsSent++;
          notifyListeners();
        }
      });

      _isAdvertising = true;
      notifyListeners();
    } catch (e) {
      debugPrint("startAdvertising caught error: $e");
      _isAdvertising = false;
      notifyListeners();
    } finally {
      _isAdvertisingOperationInProgress = false;
    }
  }

  Future<void> _advertise() async {
    try {
      final List<int> manData = _buildManufacturerData();
      final String advertisedName = _storageService.getDeviceRole() == DeviceRole.anchor
          ? '${_storageService.getFriendlyName()} [${_storageService.getAssignedRoom()}]'
          : _storageService.getFriendlyName();

      final AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
        manufacturerId: 0xFFFF, // Custom Manufacturer ID for testing
        manufacturerData: Uint8List.fromList(manData),
        localName: advertisedName,
        includeDeviceName: true,
      );
      
      await _peripheral.start(advertiseData: advertiseData);
      _isAdvertising = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting BLE advertisement: $e');
      if (e.toString().contains('ADVERTISE_FAILED_TOO_MANY_ADVERTISERS') || e.toString().contains('2')) {
        // Hardware advertising slots saturated: force stop and wait for Android radio cleanup
        try {
          await _peripheral.stop();
          await Future.delayed(const Duration(milliseconds: 400));
          final List<int> manData = _buildManufacturerData();
          final String advertisedName = _storageService.getDeviceRole() == DeviceRole.anchor
              ? '${_storageService.getFriendlyName()} [${_storageService.getAssignedRoom()}]'
              : _storageService.getFriendlyName();
          final AdvertiseData advertiseData = AdvertiseData(
            serviceUuid: 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7',
            manufacturerId: 0xFFFF,
            manufacturerData: Uint8List.fromList(manData),
            localName: advertisedName,
            includeDeviceName: true,
          );
          await _peripheral.start(advertiseData: advertiseData);
          _isAdvertising = true;
          notifyListeners();
          return;
        } catch (retryErr) {
          debugPrint('Retry after ADVERTISE_FAILED_TOO_MANY_ADVERTISERS failed: $retryErr');
        }
      }
      _isAdvertising = false;
      notifyListeners();
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
