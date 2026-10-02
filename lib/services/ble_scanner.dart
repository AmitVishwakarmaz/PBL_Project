import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'storage_service.dart';

class ScannedPacket {
  final String deviceId;
  final String friendlyName;
  final String role; // "ANCHOR", "TRACKED", "TEST"
  final String roomName;
  final int rssi;
  final int? txPower;
  final int? sequenceNumber;
  final int? target1Index;
  final int? target1Distance; // in decimeters
  final int? target2Index;
  final int? target2Distance; // in decimeters

  ScannedPacket({
    required this.deviceId,
    required this.friendlyName,
    this.role = 'ANCHOR',
    this.roomName = 'Room A',
    required this.rssi,
    this.txPower,
    this.sequenceNumber,
    this.target1Index,
    this.target1Distance,
    this.target2Index,
    this.target2Distance,
  });
}

class BleScanner extends ChangeNotifier {
  final StorageService _storageService;
  final void Function(ScannedPacket) _onPacketReceived;

  bool _isScanning = false;
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;

  bool get isScanning => _isScanning;
  BluetoothAdapterState get adapterState => _adapterState;
  bool get isBluetoothOn => _adapterState == BluetoothAdapterState.on;

  BleScanner(this._storageService, this._onPacketReceived) {
    _initAdapterState();
    
    // Listen to changes in scanning state
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });
  }

  void _initAdapterState() {
    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      _adapterState = state;
      notifyListeners();
    });
  }

  Future<void> startScanning() async {
    if (_adapterState != BluetoothAdapterState.on) {
      throw Exception("Bluetooth is disabled. Please enable Bluetooth to scan.");
    }

    _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final packet = _parseZoneCheckPacket(r);
        if (packet != null) {
          _onPacketReceived(packet);
        }
      }
    });

    try {
      // Start scanning in low latency mode (without requiring Android location)
      await FlutterBluePlus.startScan(
        androidUsesFineLocation: false,
      );
      _isScanning = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error starting BLE scan: $e');
      rethrow;
    }
  }

  Future<void> stopScanning() async {
    try {
      await FlutterBluePlus.stopScan();
      _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (e) {
      debugPrint('Error stopping BLE scan: $e');
    }
    _isScanning = false;
    notifyListeners();
  }

  /// Parses a ScanResult to check if it's a valid ZoneCheck test packet.
  /// Decodes company ID 0xFFFF and Protocol ID 0x5A43 ('ZC').
  /// Parses a ScanResult to check if it's a valid ZoneCheck test packet.
  /// Decodes company ID 0xFFFF / service UUID 'bf27730d-860a-4e09-889c-2d8b6a9e0fe7' and Protocol ID 0x5A43 ('ZC').
  ScannedPacket? _parseZoneCheckPacket(ScanResult result) {
    List<int>? bytes;

    // 1. Check manufacturerData maps (0xFFFF / 65535 or matching protocol header)
    final Map<int, List<int>> manufacturerData = result.advertisementData.manufacturerData;
    if (manufacturerData.containsKey(0xFFFF)) {
      bytes = manufacturerData[0xFFFF];
    } else if (manufacturerData.containsKey(65535)) {
      bytes = manufacturerData[65535];
    } else {
      for (final entry in manufacturerData.values) {
        if (entry.length >= 7 && entry[0] == 0x5A && entry[1] == 0x43) {
          bytes = entry;
          break;
        }
      }
    }

    // 2. Check serviceData fallback (for iOS CoreBluetooth payload parsing)
    if (bytes == null || bytes.isEmpty) {
      final Map<Guid, List<int>> serviceData = result.advertisementData.serviceData;
      final targetGuid = Guid('bf27730d-860a-4e09-889c-2d8b6a9e0fe7');
      if (serviceData.containsKey(targetGuid)) {
        bytes = serviceData[targetGuid];
      } else {
        for (final entry in serviceData.values) {
          if (entry.length >= 7 && entry[0] == 0x5A && entry[1] == 0x43) {
            bytes = entry;
            break;
          }
        }
      }
    }

    if (bytes == null || bytes.length < 7) {
      return null;
    }

    // Byte 0-1: Protocol ID (0x5A43)
    if (bytes[0] != 0x5A || bytes[1] != 0x43) {
      return null;
    }

    // Byte 2: Version (1)
    final int version = bytes[2];
    if (version != 1) {
      return null;
    }

    // Byte 3: Role ('A' = 0x41, 'C' = 0x43, 'T' = 0x54)
    final int roleByte = bytes[3];
    String roleStr = 'ANCHOR';
    String prefix = 'TEST-A';
    if (roleByte == 0x43) {
      roleStr = 'TRACKED';
      prefix = 'TEST-C';
    } else if (roleByte == 0x41) {
      roleStr = 'ANCHOR';
      prefix = 'TEST-A';
    } else if (roleByte == 0x54) {
      roleStr = 'TEST';
      prefix = 'TEST-A';
    } else {
      return null; // Unknown role
    }

    // Byte 4-5: Device index
    final int deviceIndex = (bytes[4] << 8) | bytes[5];
    final String deviceId = '$prefix${deviceIndex.toString().padLeft(3, '0')}';

    // Byte 6: Sequence number
    final int sequenceNumber = bytes[6];

    // Friendly Name & Room parsing
    String friendlyName = result.advertisementData.localName.trim();
    if (friendlyName.isEmpty) {
      friendlyName = result.device.platformName.trim();
    }
    if (friendlyName.isEmpty) {
      friendlyName = roleStr == 'TRACKED' ? 'Tracked $deviceIndex' : 'Anchor $deviceIndex';
    }

    String roomName = 'Room A';
    final roomMatch = RegExp(r'\[(.*?)\]').firstMatch(friendlyName);
    if (roomMatch != null && roomMatch.group(1) != null) {
      roomName = roomMatch.group(1)!.trim();
      friendlyName = friendlyName.replaceAll(RegExp(r'\[.*?\]'), '').trim();
    }

    // Get TX Power
    final int? txPower = result.advertisementData.txPowerLevel;

    // Parse Dynamic P2P Distances if present (Bytes 7, 8, 9, 10)
    int? target1Index;
    int? target1Distance;
    int? target2Index;
    int? target2Distance;
    if (bytes.length >= 11) {
      target1Index = bytes[7];
      target1Distance = bytes[8];
      target2Index = bytes[9];
      target2Distance = bytes[10];
    }

    return ScannedPacket(
      deviceId: deviceId,
      friendlyName: friendlyName,
      role: roleStr,
      roomName: roomName,
      rssi: result.rssi,
      txPower: txPower,
      sequenceNumber: sequenceNumber,
      target1Index: target1Index,
      target1Distance: target1Distance,
      target2Index: target2Index,
      target2Distance: target2Distance,
    );
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _adapterStateSubscription?.cancel();
    super.dispose();
  }
}
