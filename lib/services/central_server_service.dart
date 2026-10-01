import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/anchor_network.dart';
import 'storage_service.dart';

class AnchorReport {
  final String anchorId;
  final String roomName;
  final double anchorX;
  final double anchorY;
  final String targetDeviceId;
  final int rssi;
  final double distance;
  final DateTime timestamp;

  AnchorReport({
    required this.anchorId,
    required this.roomName,
    required this.anchorX,
    required this.anchorY,
    required this.targetDeviceId,
    required this.rssi,
    required this.distance,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'anchorId': anchorId,
    'roomName': roomName,
    'anchorX': anchorX,
    'anchorY': anchorY,
    'targetDeviceId': targetDeviceId,
    'rssi': rssi,
    'distance': distance,
    'timestamp': timestamp.toIso8601String(),
  };

  factory AnchorReport.fromJson(Map<String, dynamic> json) => AnchorReport(
    anchorId: json['anchorId'] as String? ?? '',
    roomName: json['roomName'] as String? ?? 'Room A',
    anchorX: (json['anchorX'] as num?)?.toDouble() ?? 0.0,
    anchorY: (json['anchorY'] as num?)?.toDouble() ?? 0.0,
    targetDeviceId: json['targetDeviceId'] as String? ?? '',
    rssi: (json['rssi'] as num?)?.toInt() ?? -70,
    distance: (json['distance'] as num?)?.toDouble() ?? 2.0,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}

class CentralServerService extends ChangeNotifier {
  final StorageService _storageService;
  HttpServer? _server;
  bool _isServerRunning = false;
  String _serverIp = '127.0.0.1';
  int _serverPort = 8080;

  // Active reports on server: maps targetDeviceId -> list of recent AnchorReports
  final Map<String, List<AnchorReport>> _deviceReports = {};
  final Map<String, TrackedLocation> _serverSolvedLocations = {};

  // Client sync state
  Timer? _clientSyncTimer;
  bool _isClientConnected = false;
  TrackedLocation? _latestSyncedLocation;
  String _clientStatusMessage = 'Disconnected';

  bool get isServerRunning => _isServerRunning;
  String get serverIp => _serverIp;
  int get serverPort => _serverPort;
  String get serverUrl => 'http://$_serverIp:$_serverPort';
  bool get isClientConnected => _isClientConnected;
  TrackedLocation? get latestSyncedLocation => _latestSyncedLocation;
  String get clientStatusMessage => _clientStatusMessage;
  Map<String, TrackedLocation> get serverSolvedLocations => _serverSolvedLocations;

  CentralServerService(this._storageService) {
    _serverPort = _storageService.getServerPort();
    _fetchLocalIp();
  }

  Future<void> _fetchLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            _serverIp = addr.address;
            notifyListeners();
            return;
          }
        }
      }
    } catch (e) {
      debugPrint("Error fetching local IP: $e");
    }
  }

  // --- EMBEDDED HTTP SERVER (Hosted by any phone or anchor) ---

  Future<bool> startServer({int? port}) async {
    if (_isServerRunning) return true;
    _serverPort = port ?? _storageService.getServerPort();
    await _fetchLocalIp();

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, _serverPort);
      _isServerRunning = true;
      notifyListeners();

      _server!.listen((HttpRequest request) async {
        // Enable CORS
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        try {
          final path = request.uri.path;
          if (path == '/api/status' && request.method == 'GET') {
            await _handleStatus(request);
          } else if (path == '/api/anchor/report' && request.method == 'POST') {
            await _handleAnchorReport(request);
          } else if (path == '/api/anchor/network') {
            await _handleAnchorNetwork(request);
          } else if (path == '/api/location' && request.method == 'GET') {
            await _handleGetLocation(request);
          } else {
            request.response.statusCode = HttpStatus.notFound;
            request.response.write(json.encode({'error': 'Not found'}));
            await request.response.close();
          }
        } catch (e) {
          debugPrint("Server request error: $e");
          request.response.statusCode = HttpStatus.internalServerError;
          request.response.write(json.encode({'error': e.toString()}));
          await request.response.close();
        }
      });

      return true;
    } catch (e) {
      debugPrint("Failed to start embedded central server: $e");
      _isServerRunning = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _isServerRunning = false;
    _deviceReports.clear();
    _serverSolvedLocations.clear();
    notifyListeners();
  }

  Future<void> _handleStatus(HttpRequest request) async {
    final status = {
      'status': 'online',
      'serverIp': _serverIp,
      'port': _serverPort,
      'trackedDevicesCount': _serverSolvedLocations.length,
      'devices': _serverSolvedLocations.map((k, v) => MapEntry(k, v.toJson())),
    };
    request.response.headers.contentType = ContentType.json;
    request.response.write(json.encode(status));
    await request.response.close();
  }

  /// Direct in-process submission when server is hosted on the same phone
  void addDirectReport(AnchorReport report) {
    _deviceReports.putIfAbsent(report.targetDeviceId, () => []);
    final reports = _deviceReports[report.targetDeviceId]!;
    reports.removeWhere((r) => r.anchorId == report.anchorId);
    reports.add(report);

    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    reports.removeWhere((r) => r.timestamp.isBefore(cutoff));

    _solveLocationForDevice(report.targetDeviceId, reports);
    notifyListeners();
  }

  Future<void> _handleAnchorReport(HttpRequest request) async {
    final content = await utf8.decoder.bind(request).join();
    final data = json.decode(content) as Map<String, dynamic>;
    final report = AnchorReport.fromJson(data);

    // Add report
    _deviceReports.putIfAbsent(report.targetDeviceId, () => []);
    final reports = _deviceReports[report.targetDeviceId]!;
    // Remove older reports from same anchor
    reports.removeWhere((r) => r.anchorId == report.anchorId);
    reports.add(report);

    // Keep reports within last 20 seconds
    final cutoff = DateTime.now().subtract(const Duration(seconds: 20));
    reports.removeWhere((r) => r.timestamp.isBefore(cutoff));

    // Solve location for target device
    _solveLocationForDevice(report.targetDeviceId, reports);

    request.response.headers.contentType = ContentType.json;
    request.response.write(json.encode({'status': 'success', 'deviceId': report.targetDeviceId}));
    await request.response.close();
    notifyListeners();
  }

  AnchorMap? _activeAnchorMap;
  AnchorMap? get activeAnchorMap => _activeAnchorMap;

  void registerAnchorNetwork(AnchorMap map) {
    _activeAnchorMap = map;
    notifyListeners();
  }

  Future<void> _handleAnchorNetwork(HttpRequest request) async {
    if (request.method == 'POST') {
      final content = await utf8.decoder.bind(request).join();
      final data = json.decode(content) as Map<String, dynamic>;
      _activeAnchorMap = AnchorMap.fromJson(data);
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'status': 'success', 'anchorCount': _activeAnchorMap!.anchors.length}));
      await request.response.close();
      notifyListeners();
    } else if (request.method == 'GET') {
      request.response.headers.contentType = ContentType.json;
      if (_activeAnchorMap != null) {
        request.response.write(json.encode(_activeAnchorMap!.toJson()));
      } else {
        request.response.write(json.encode({'status': 'none'}));
      }
      await request.response.close();
    }
  }

  void _solveLocationForDevice(String targetId, List<AnchorReport> reports) {
    if (reports.isEmpty) return;

    // 1. Determine Room Name by majority voting of reporting anchors
    final Map<String, int> roomCounts = {};
    for (var r in reports) {
      roomCounts[r.roomName] = (roomCounts[r.roomName] ?? 0) + 1;
    }
    String resolvedRoom = 'Room A';
    int maxCount = 0;
    roomCounts.forEach((room, count) {
      if (count > maxCount) {
        maxCount = count;
        resolvedRoom = room;
      }
    });

    // 2. Match anchor coordinates from calibrated anchor network or reports
    final List<({double x, double y, double d, String id})> anchorPoints = [];
    for (var r in reports) {
      double ax = r.anchorX;
      double ay = r.anchorY;
      if (_activeAnchorMap != null) {
        final match = _activeAnchorMap!.anchors.where((a) => a.anchorId == r.anchorId);
        if (match.isNotEmpty) {
          ax = match.first.x;
          ay = match.first.y;
        }
      }
      anchorPoints.add((x: ax, y: ay, d: max(0.2, r.distance), id: r.anchorId));
    }

    anchorPoints.sort((a, b) => a.d.compareTo(b.d));
    final nearest = anchorPoints.first;

    double solvedX = nearest.x;
    double solvedY = nearest.y;

    if (anchorPoints.length >= 3) {
      // Step A: Initial estimate using weighted centroid
      double totalW = 0.0;
      double wx = 0.0;
      double wy = 0.0;
      for (var pt in anchorPoints) {
        final double w = 1.0 / (pt.d * pt.d);
        wx += pt.x * w;
        wy += pt.y * w;
        totalW += w;
      }
      solvedX = totalW > 0 ? wx / totalW : nearest.x;
      solvedY = totalW > 0 ? wy / totalW : nearest.y;

      // Step B: Gauss-Newton Non-Linear Least Squares Optimization
      // Minimizes Sum( (sqrt((x-xi)^2 + (y-yi)^2) - di)^2 )
      const int maxIter = 10;
      const double lambda = 0.01; // Levenberg-Marquardt damping
      for (int iter = 0; iter < maxIter; iter++) {
        double a00 = lambda;
        double a01 = 0.0;
        double a11 = lambda;
        double b0 = 0.0;
        double b1 = 0.0;

        for (var pt in anchorPoints) {
          final double dx = solvedX - pt.x;
          final double dy = solvedY - pt.y;
          final double r = max(0.05, sqrt(dx * dx + dy * dy));
          final double j0 = dx / r;
          final double j1 = dy / r;
          final double error = pt.d - r;
          final double w = 1.0 / max(0.3, pt.d);

          a00 += w * j0 * j0;
          a01 += w * j0 * j1;
          a11 += w * j1 * j1;
          b0 += w * j0 * error;
          b1 += w * j1 * error;
        }

        final double det = a00 * a11 - a01 * a01;
        if (det.abs() < 1e-7) break;

        final double stepX = (a11 * b0 - a01 * b1) / det;
        final double stepY = (a00 * b1 - a01 * b0) / det;

        // Apply damped step
        solvedX += stepX.clamp(-2.5, 2.5);
        solvedY += stepY.clamp(-2.5, 2.5);

        if (stepX.abs() < 0.01 && stepY.abs() < 0.01) break;
      }
    } else if (anchorPoints.length == 2) {
      final a = anchorPoints[0];
      final b = anchorPoints[1];
      final double totalD = a.d + b.d;
      if (totalD > 0) {
        solvedX = a.x * (b.d / totalD) + b.x * (a.d / totalD);
        solvedY = a.y * (b.d / totalD) + b.y * (a.d / totalD);
      }
    }

    final double confidence = min(98.0, 55.0 + anchorPoints.length * 14.0);

    final loc = TrackedLocation(
      deviceId: targetId,
      x: solvedX,
      y: solvedY,
      roomName: resolvedRoom,
      confidence: confidence,
      nearestAnchorId: nearest.id,
      nearestDistance: nearest.d,
      timestamp: DateTime.now(),
      source: 'CENTRAL_SERVER',
    );

    _serverSolvedLocations[targetId] = loc;
  }

  Future<void> _handleGetLocation(HttpRequest request) async {
    final deviceId = request.uri.queryParameters['deviceId'];
    if (deviceId == null || !_serverSolvedLocations.containsKey(deviceId)) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(json.encode({'error': 'Location not calculated yet'}));
      await request.response.close();
      return;
    }

    final loc = _serverSolvedLocations[deviceId]!;
    final Map<String, dynamic> locJson = loc.toJson();
    if (_activeAnchorMap != null) {
      locJson['anchorMap'] = _activeAnchorMap!.toJson();
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(json.encode(locJson));
    await request.response.close();
  }

  // --- CLIENT SYNC (Used by Central Device to receive resolved Room info from server) ---

  void startClientSync({required String targetDeviceId, String? host, int? port}) {
    stopClientSync();
    final serverHost = host ?? _storageService.getServerHost();
    final serverPort = port ?? _storageService.getServerPort();

    _clientSyncTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      await _pollLocationFromServer(targetDeviceId, serverHost, serverPort);
    });
  }

  void stopClientSync() {
    _clientSyncTimer?.cancel();
    _clientSyncTimer = null;
    _isClientConnected = false;
    notifyListeners();
  }

  Future<void> _pollLocationFromServer(String targetDeviceId, String host, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse('http://$host:$port/api/location?deviceId=$targetDeviceId');
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode == HttpStatus.ok) {
        final responseBody = await utf8.decoder.bind(response).join();
        final data = json.decode(responseBody) as Map<String, dynamic>;
        _latestSyncedLocation = TrackedLocation.fromJson(data);
        if (data.containsKey('anchorMap') && data['anchorMap'] != null) {
          try {
            _activeAnchorMap = AnchorMap.fromJson(data['anchorMap'] as Map<String, dynamic>);
          } catch (_) {}
        }
        _isClientConnected = true;
        _clientStatusMessage = 'Connected to Server ($host:$port)';
        notifyListeners();
      } else {
        _isClientConnected = false;
        _clientStatusMessage = 'Waiting for anchor reports...';
        notifyListeners();
      }
    } catch (e) {
      _isClientConnected = false;
      _clientStatusMessage = 'Server Offline (Using Local BLE)';
      notifyListeners();
    } finally {
      client.close();
    }
  }

  /// Sends periodic heartbeat registration of this anchor to central server
  Future<bool> sendAnchorHeartbeat({
    required String serverHost,
    required int serverPort,
    required String anchorId,
    required String friendlyName,
    required String roomName,
    required double x,
    required double y,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/anchor/heartbeat');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final payload = json.encode({
        'anchorId': anchorId,
        'friendlyName': friendlyName,
        'roomName': roomName,
        'x': x,
        'y': y,
      });
      request.headers.contentLength = utf8.encode(payload).length;
      request.write(payload);
      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint("Failed to send anchor heartbeat to server: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Sends the solved anchor network geometry to the central server
  Future<bool> sendAnchorNetworkToServer({
    required String serverHost,
    required int serverPort,
    required AnchorMap map,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/anchor/network');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final payload = json.encode(map.toJson());
      request.headers.contentLength = utf8.encode(payload).length;
      request.write(payload);
      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint("Failed to send anchor network to server: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Sends an anchor sighting report to the central server
  Future<bool> sendAnchorReportToServer({
    required String serverHost,
    required int serverPort,
    required AnchorReport report,
  }) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final uri = Uri.parse('http://$serverHost:$serverPort/api/anchor/report');
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      final payload = json.encode(report.toJson());
      request.headers.contentLength = utf8.encode(payload).length;
      request.write(payload);
      final response = await request.close();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      debugPrint("Failed to send anchor report to server: $e");
      return false;
    } finally {
      client.close();
    }
  }

  /// Pings the server at host:port to verify Wi-Fi reachability
  Future<({bool success, String message, String? serverIp})> pingServer(String host, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final uri = Uri.parse('http://$host:$port/api/status');
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        final data = json.decode(body) as Map<String, dynamic>;
        final ip = data['serverIp'] as String? ?? host;
        return (success: true, message: 'Online • Connected to http://$host:$port', serverIp: ip);
      } else {
        return (success: false, message: 'Server returned HTTP ${response.statusCode}', serverIp: null);
      }
    } catch (e) {
      return (success: false, message: 'Cannot connect: $e', serverIp: null);
    } finally {
      client.close();
    }
  }

  @override
  void dispose() {
    stopServer();
    stopClientSync();
    super.dispose();
  }
}
