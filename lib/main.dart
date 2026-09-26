import 'package:flutter/material.dart';
import 'services/storage_service.dart';
import 'services/ble_advertiser.dart';
import 'services/ble_scanner.dart';
import 'services/measurement_repository.dart';
import 'views/dashboard_view.dart';
import 'views/calibration_view.dart';
import 'views/orientation_view.dart';
import 'views/obstruction_view.dart';
import 'views/stability_view.dart';
import 'views/pairwise_view.dart';
import 'views/report_view.dart';
import 'views/anchor_map_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. Initialize Storage
  final storageService = await StorageService.init();
  
  // 2. Initialize Repos & Services
  final measurementRepository = MeasurementRepository(storageService);
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
  ));
}

class LIVSApp extends StatelessWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;

  const LIVSApp({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LIVS BLE Test App',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F13),
        cardColor: const Color(0xFF171721),
        primaryColor: const Color(0xFF00F0FF), // Cyber Cyan
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00F0FF),
          secondary: Color(0xFFD946EF), // Neon Fuchsia
          surface: Color(0xFF171721),
          background: Color(0xFF0F0F13),
          error: Color(0xFFEF4444),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Colors.white),
          titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w600, color: Colors.white),
          bodyLarge: TextStyle(fontFamily: 'Inter', color: Color(0xFFE2E8F0)),
          bodyMedium: TextStyle(fontFamily: 'Inter', color: Color(0xFF94A3B8)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0F13),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontFamily: 'Outfit',
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00F0FF),
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00F0FF),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            elevation: 4,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF00F0FF),
            side: const BorderSide(color: Color(0xFF00F0FF), width: 1.5),
            textStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFD946EF),
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        dividerColor: const Color(0xFF2E2E3A),
      ),
      home: MainShell(
        storageService: storageService,
        bleAdvertiser: bleAdvertiser,
        bleScanner: bleScanner,
        measurementRepository: measurementRepository,
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final MeasurementRepository measurementRepository;

  const MainShell({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.measurementRepository,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> views = [
      DashboardView(
        storageService: widget.storageService,
        bleAdvertiser: widget.bleAdvertiser,
        bleScanner: widget.bleScanner,
        measurementRepository: widget.measurementRepository,
      ),
      CalibrationView(
        storageService: widget.storageService,
        measurementRepository: widget.measurementRepository,
      ),
      OrientationView(
        measurementRepository: widget.measurementRepository,
      ),
      ObstructionView(
        measurementRepository: widget.measurementRepository,
      ),
      StabilityView(
        measurementRepository: widget.measurementRepository,
      ),
      PairwiseView(
        measurementRepository: widget.measurementRepository,
      ),
      ReportView(
        bleAdvertiser: widget.bleAdvertiser,
        bleScanner: widget.bleScanner,
        measurementRepository: widget.measurementRepository,
      ),
      AnchorMapView(
        storageService: widget.storageService,
        bleAdvertiser: widget.bleAdvertiser,
        bleScanner: widget.bleScanner,
        measurementRepository: widget.measurementRepository,
      ),
    ];

    final List<String> titles = [
      'LIVS Dashboard',
      'Known Distance Calibration',
      'Orientation Impact Test',
      'Obstruction Impact Test',
      'Stability Analysis (60s)',
      'Pairwise Device Matrix',
      'Capability Report',
      'Anchor Map Localization',
    ];

    final List<IconData> icons = [
      Icons.dashboard_rounded,
      Icons.settings_input_antenna_rounded,
      Icons.explore_rounded,
      Icons.block_rounded,
      Icons.insights_rounded,
      Icons.hub_rounded,
      Icons.assignment_turned_in_rounded,
      Icons.map_rounded,
    ];

    final bool isWideScreen = MediaQuery.of(context).size.width > 900;

    int getBottomBarIndex(int currIdx) {
      if (currIdx == 0) return 0;
      if (currIdx == 1) return 1;
      if (currIdx == 7) return 2;
      return 3;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_currentIndex]),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF00F0FF)),
            tooltip: 'Clear & Reset All Measurements',
            onPressed: () {
              widget.measurementRepository.clearMeasurements();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('All measurements cleared.')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Color(0xFFD946EF)),
            tooltip: 'Export CSV Test Data',
            onPressed: () async {
              try {
                await widget.measurementRepository.exportTestData();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Export failed: ${e.toString()}')),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isWideScreen
          ? null
          : Drawer(
              backgroundColor: const Color(0xFF0F0F13),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF00F0FF), Color(0xFFD946EF)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        const Text(
                          'LIVS',
                          style: TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.black,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Location Integration Verification System',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.black.withOpacity(0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (int i = 0; i < views.length; i++)
                    ListTile(
                      leading: Icon(
                        icons[i],
                        color: _currentIndex == i ? const Color(0xFF00F0FF) : Colors.white60,
                      ),
                      title: Text(
                        titles[i],
                        style: TextStyle(
                          fontFamily: 'Inter',
                          color: _currentIndex == i ? const Color(0xFF00F0FF) : Colors.white.withOpacity(0.9),
                          fontWeight: _currentIndex == i ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: _currentIndex == i,
                      selectedTileColor: const Color(0xFF171721),
                      onTap: () {
                        setState(() {
                          _currentIndex = i;
                        });
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
      body: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              backgroundColor: const Color(0xFF0F0F13),
              selectedIndex: _currentIndex,
              onDestinationSelected: (int index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              labelType: NavigationRailLabelType.all,
              selectedLabelTextStyle: const TextStyle(
                color: Color(0xFF00F0FF),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              unselectedLabelTextStyle: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
              selectedIconTheme: const IconThemeData(color: Color(0xFF00F0FF)),
              unselectedIconTheme: const IconThemeData(color: Colors.white60),
              indicatorColor: const Color(0xFF171721),
              destinations: [
                for (int i = 0; i < views.length; i++)
                  NavigationRailDestination(
                    icon: Icon(icons[i]),
                    label: Text(titles[i].replaceAll(' Test', '').replaceAll(' Known Distance ', '')),
                  ),
              ],
            ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: views[_currentIndex],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWideScreen
          ? null
          : BottomNavigationBar(
              currentIndex: getBottomBarIndex(_currentIndex),
              onTap: (index) {
                if (index == 0) {
                  setState(() => _currentIndex = 0);
                } else if (index == 1) {
                  setState(() => _currentIndex = 1);
                } else if (index == 2) {
                  setState(() => _currentIndex = 7);
                } else {
                  // Open Drawer for advanced options
                  Scaffold.of(context).openDrawer();
                }
              },
              backgroundColor: const Color(0xFF171721),
              selectedItemColor: const Color(0xFF00F0FF),
              unselectedItemColor: Colors.white.withOpacity(0.5),
              type: BottomNavigationBarType.fixed,
              items: [
                BottomNavigationBarItem(
                  icon: Icon(icons[0]),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(icons[1]),
                  label: 'Calibration',
                ),
                BottomNavigationBarItem(
                  icon: Icon(icons[7]),
                  label: 'Anchor Map',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.menu_rounded),
                  label: 'More Tests',
                ),
              ],
            ),
    );
  }
}
