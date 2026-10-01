import 'package:flutter/material.dart';
import '../../services/storage_service.dart';
import '../../services/central_server_service.dart';
import '../../utils/app_theme.dart';

class ServerConfigDialog extends StatefulWidget {
  final StorageService storageService;
  final CentralServerService centralServerService;
  final VoidCallback onSaved;

  const ServerConfigDialog({
    super.key,
    required this.storageService,
    required this.centralServerService,
    required this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    required StorageService storageService,
    required CentralServerService centralServerService,
    required VoidCallback onSaved,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ServerConfigDialog(
        storageService: storageService,
        centralServerService: centralServerService,
        onSaved: onSaved,
      ),
    );
  }

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;

  bool _isTesting = false;
  String? _testMessage;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _hostCtrl = TextEditingController(text: widget.storageService.getServerHost());
    _portCtrl = TextEditingController(text: widget.storageService.getServerPort().toString());
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });

    final parsed = StorageService.parseServerAddress(
      _hostCtrl.text,
      defaultPort: int.tryParse(_portCtrl.text.trim()) ?? 8080,
    );

    // Update controllers to cleaned values
    _hostCtrl.text = parsed.host;
    _portCtrl.text = parsed.port.toString();

    final result = await widget.centralServerService.pingServer(parsed.host, parsed.port);

    if (mounted) {
      setState(() {
        _isTesting = false;
        _testSuccess = result.success;
        _testMessage = result.message;
      });
    }
  }

  Future<void> _saveConfig() async {
    final parsed = StorageService.parseServerAddress(
      _hostCtrl.text,
      defaultPort: int.tryParse(_portCtrl.text.trim()) ?? 8080,
    );

    await widget.storageService.setServerHost(parsed.host);
    await widget.storageService.setServerPort(parsed.port);

    widget.onSaved();
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Target server updated to ${parsed.host}:${parsed.port}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: const BorderSide(color: AppColors.border, width: 1.0),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryAccentSubtle,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: const Icon(Icons.dns_rounded, color: AppColors.primaryAccent, size: 20),
          ),
          const SizedBox(width: 12),
          const Text(
            'Central Server Target',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the Wi-Fi IP address printed by python central_server.py when switching to a new Wi-Fi or hotspot:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _hostCtrl,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Server IP or Hostname',
                hintText: 'e.g. 192.168.1.50 or 192.168.0.100',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _portCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Port (default: 8080)',
              ),
            ),
            const SizedBox(height: 14),

            // Test Connection Button
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryAccent),
                      )
                    : const Icon(Icons.wifi_find_rounded, size: 16, color: AppColors.primaryAccent),
                label: Text(
                  _isTesting ? 'Testing Connectivity...' : 'Test Connection',
                  style: const TextStyle(color: AppColors.primaryAccent, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.border, width: 1.0),
                  backgroundColor: AppColors.surfaceHighlight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                ),
              ),
            ),

            // Test Result Feedback
            if (_testMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess == true ? AppColors.successSubtle : AppColors.errorSubtle,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  border: Border.all(
                    color: _testSuccess == true
                        ? AppColors.success.withValues(alpha: 0.3)
                        : AppColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _testSuccess == true ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: _testSuccess == true ? AppColors.success : AppColors.error,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testMessage!,
                        style: TextStyle(
                          fontSize: 12,
                          color: _testSuccess == true ? AppColors.success : AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
        ),
        ElevatedButton(
          onPressed: _saveConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
          ),
          child: const Text('Save & Apply'),
        ),
      ],
    );
  }
}
