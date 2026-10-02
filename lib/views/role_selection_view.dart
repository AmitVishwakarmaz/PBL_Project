import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/storage_service.dart';
import '../services/ble_advertiser.dart';
import '../services/ble_scanner.dart';
import '../services/central_server_service.dart';
import '../utils/app_theme.dart';
import 'widgets/expandable_text.dart';

class RoleSelectionView extends StatefulWidget {
  final StorageService storageService;
  final BleAdvertiser bleAdvertiser;
  final BleScanner bleScanner;
  final CentralServerService centralServerService;
  final VoidCallback onRoleSelected;

  const RoleSelectionView({
    super.key,
    required this.storageService,
    required this.bleAdvertiser,
    required this.bleScanner,
    required this.centralServerService,
    required this.onRoleSelected,
  });

  @override
  State<RoleSelectionView> createState() => _RoleSelectionViewState();
}

class _RoleSelectionViewState extends State<RoleSelectionView> {
  DeviceRole _selectedRole = DeviceRole.anchor;
  late TextEditingController _nameController;
  late TextEditingController _serverHostController;
  bool _showAdvancedSettings = false;
  bool _isActivating = false;

  @override
  void initState() {
    super.initState();
    _selectedRole = widget.storageService.getDeviceRole() ?? DeviceRole.anchor;
    _nameController = TextEditingController(text: widget.storageService.getFriendlyName());
    _serverHostController = TextEditingController(
      text: widget.storageService.getServerHost(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _serverHostController.dispose();
    super.dispose();
  }

  Future<void> _confirmSelection() async {
    setState(() => _isActivating = true);

    try {
      // 1. Request Bluetooth permissions cleanly across platforms (no location/GPS requested)
      if (Platform.isIOS) {
        await [
          Permission.bluetooth,
        ].request();
      } else {
        await [
          Permission.bluetoothScan,
          Permission.bluetoothAdvertise,
          Permission.bluetoothConnect,
        ].request();
      }

      // 2. Persist user configuration
      const String room = 'Room A';
      final String name = _nameController.text.trim().isEmpty
          ? (_selectedRole == DeviceRole.anchor ? 'Anchor' : 'Client Phone')
          : _nameController.text.trim();
      final parsed = StorageService.parseServerAddress(_serverHostController.text);

      await widget.storageService.setDeviceRole(_selectedRole);
      await widget.storageService.setAssignedRoom(room);
      await widget.storageService.setFriendlyName(name);
      await widget.storageService.setServerHost(parsed.host);
      await widget.storageService.setServerPort(parsed.port);

      // 3. Start BLE services safely
      try {
        if (!widget.bleScanner.isScanning) {
          await widget.bleScanner.startScanning();
        }
        if (!widget.bleAdvertiser.isAdvertising) {
          await widget.bleAdvertiser.startAdvertising();
        }
      } catch (e) {
        debugPrint("BLE startup notice: $e");
      }

      // 4. If tracked client, start sync to central server if host provided
      if (_selectedRole == DeviceRole.tracked && parsed.host.isNotEmpty) {
        widget.centralServerService.startClientSync(
          targetDeviceId: widget.storageService.getDeviceId(),
          host: parsed.host,
          port: parsed.port,
        );
      }

      widget.onRoleSelected();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting role: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isActivating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryAccentSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                ),
                child: const Text(
                  'INDOOR POSITIONING • PBL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Title
              const Text(
                'Choose Device Role',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pure BLE signals with pairwise distance calibration. Zero GPS.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Option 1: Anchor Node Card
              _buildRoleCard(
                role: DeviceRole.anchor,
                title: 'Option 1: Anchor Node',
                subtitle:
                    'Fixed reference beacon placed in a room. Communicates with other anchors to auto-calibrate coordinates and detects nearby mobile devices.',
                icon: Icons.cell_tower_rounded,
                badgeText: 'FIXED',
              ),
              const SizedBox(height: AppSpacing.md),

              // Option 2: Client Device Card
              _buildRoleCard(
                role: DeviceRole.tracked,
                title: 'Option 2: Locate Me',
                subtitle:
                    'Mobile client looking for its location. Broadcasts BLE signals so anchors detect you and the central server displays your exact room & 2D position.',
                icon: Icons.my_location_rounded,
                badgeText: 'CLIENT',
              ),
              const SizedBox(height: AppSpacing.lg),

              // Contextual Settings based on chosen role
              if (_selectedRole == DeviceRole.anchor) ...[
                _buildAnchorQuickConfig(),
              ] else ...[
                _buildClientQuickConfig(),
              ],

              const SizedBox(height: AppSpacing.md),

              // Expandable Advanced Server Settings
              InkWell(
                onTap: () => setState(() => _showAdvancedSettings = !_showAdvancedSettings),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvancedSettings ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Advanced Server Settings (Optional)',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              if (_showAdvancedSettings) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CENTRAL SERVER IP',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextField(
                        controller: _serverHostController,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'e.g. 192.168.1.50 or 192.168.0.100',
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Anchors send sightings to this IP. Client fetches its calculated position from here.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              // Action Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isActivating ? null : _confirmSelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                    elevation: 0,
                  ),
                  child: _isActivating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(
                          _selectedRole == DeviceRole.anchor
                              ? 'ACTIVATE ANCHOR (ROOM A)'
                              : 'START LOCATION TRACKING',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required DeviceRole role,
    required String title,
    required String subtitle,
    required IconData icon,
    required String badgeText,
  }) {
    final bool isSelected = _selectedRole == role;

    return InkWell(
      onTap: () => setState(() => _selectedRole = role),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceHighlight : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: isSelected ? AppColors.primaryAccent : AppColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primaryAccentSubtle : AppColors.surfaceSubtle,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primaryAccent : AppColors.textSecondary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primaryAccentSubtle : AppColors.surfaceSubtle,
                          borderRadius: BorderRadius.circular(AppRadii.sm),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isSelected ? AppColors.primaryAccent : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ExpandableText(
                    text: subtitle,
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      height: 1.35,
                    ),
                    linkColor: AppColors.primaryAccent,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnchorQuickConfig() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.primaryAccent, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Text(
                'ANCHOR NODE • ROOM A',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: AppColors.primaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Anchor Friendly Name (Optional)',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientQuickConfig() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Text(
                'READY TO LOCATE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const ExpandableText(
            text:
                'This phone will broadcast a lightweight BLE signal. Nearby anchors will report your RSSI to the Central Server to pinpoint your room and 2D coordinates.',
            maxLines: 2,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
            linkColor: AppColors.primaryAccent,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Device Name (Optional)',
            ),
          ),
        ],
      ),
    );
  }
}


