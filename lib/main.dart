import 'package:flutter/material.dart';
import 'utils/app_theme.dart';
import 'services/storage_service.dart';
import 'services/ble_advertiser.dart';
import 'services/ble_scanner.dart';
import 'services/measurement_repository.dart';
import 'services/central_server_service.dart';
import 'views/role_selection_view.dart';
import 'views/tracked_map_view.dart';
import 'views/anchor_node_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Storage
  final storageService = await StorageService.init();
  
  // 2. Initialize Central Server Service
  final centralServerService = CentralServerService(storageService);

  // 3. Initialize Repos & BLE Services
  final measurementRepository = MeasurementRepository(storageService);
  measurementRepository.centralServerService = centralServerService;

  final bleAdvertiser = BleAdvertiser(storageService);
  bleAdvertiser.getTopScanDistances = () {
    return measurementRepository.getTopScanDistances();
  };
  final bleScanner = BleScanner(storageService, (packet) {
    measurementRepository.handleScannedPacket(packet);
  });



  runApp(LIVSApp(
    storageService: storageService,
    bleAdvertiser: bleAdvertiser,
    bleScanner: bleScanner,
    measurementRepository: measurementRepository,
    centralServerService: centralServerService,
  ));
}

class LIVSApp extends StatelessWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;
  final CentralServerService centralServerService;

  const LIVSApp({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
    required this.centralServerService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIVS Indoor Navigation',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      home: MainShell(
        storageService: storageService,
        bleAdvertiser: bleAdvertiser,
        bleScanner: bleScanner,
        measurementRepository: measurementRepository,
        centralServerService: centralServerService,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;
  final CentralServerService centralServerService;

  const MainShell({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
    required this.centralServerService,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  DeviceRole? _currentRole;

  @override
  void initState() {
    super.initState();
    // Start at role selection so the user can choose whether this device acts as Anchor or Client
    _currentRole = null;
  }

  void _onRoleSelected() {
    setState(() {
      _currentRole = widget.storageService.getDeviceRole();
    });
  }

  void _switchToRoleSelection() {
    setState(() {
      _currentRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentRole == null) {
      return RoleSelectionView(
        storageService: widget.storageService,
        bleAdvertiser: widget.bleAdvertiser,
        bleScanner: widget.bleScanner,
        centralServerService: widget.centralServerService,
        onRoleSelected: _onRoleSelected,
      );
    }

    if (_currentRole == DeviceRole.anchor) {
      return AnchorNodeView(
        storageService: widget.storageService,
        measurementRepository: widget.measurementRepository,
        bleAdvertiser: widget.bleAdvertiser,
        bleScanner: widget.bleScanner,
        centralServerService: widget.centralServerService,
        onSwitchRole: _switchToRoleSelection,
      );
    }

    // Default: Tracked Device Mode
    return TrackedMapView(
      storageService: widget.storageService,
      measurementRepository: widget.measurementRepository,
      bleAdvertiser: widget.bleAdvertiser,
      bleScanner: widget.bleScanner,
      centralServerService: widget.centralServerService,
      onSwitchRole: _switchToRoleSelection,
    );
  }
}
