# LIVS: Lightweight Indoor Localization & Verification System

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.8+-3776AB?logo=python&logoColor=white)](https://www.python.org)
[![Bluetooth Low Energy](https://img.shields.io/badge/BLE-Low_Energy-0082FC?logo=bluetooth)](https://en.wikipedia.org/wiki/Bluetooth_Low_Energy)
[![Architecture](https://img.shields.io/badge/Architecture-Decentralized_Anchors-FF8A3D)]()
[![Design System](https://img.shields.io/badge/Theme-Charcoal_%2B_Orange-1B1B1B)]()

LIVS is a high-precision, infrastructure-grade **indoor localization and positioning system** built for GPS-denied indoor environments. By combining smartphone Bluetooth Low Energy (BLE) peripheral broadcasting, adaptive path-loss signal filtering, automated peer-to-peer pairwise coordinate calibration, and central server Non-Linear Least Squares (NLLS) multilateration, LIVS pinpoints mobile devices in real time with sub-room precision.

---

## Table of Contents
- [Why LIVS?](#why-livs)
- [System Architecture](#system-architecture)
- [Design Identity](#design-identity)
- [Quick Start Guide](#quick-start-guide)
  - [Prerequisites](#prerequisites)
  - [Step 1: Start Central Server](#step-1-start-central-server)
  - [Step 2: Run Flutter App](#step-2-run-flutter-app)
  - [Step 3: Setup Anchor Nodes](#step-3-setup-anchor-nodes)
  - [Step 4: Locate Mobile Clients](#step-4-locate-mobile-clients)
- [Dynamic Wi-Fi & Hotspot Switching](#dynamic-wi-fi--hotspot-switching)
- [Signal Processing & Math Models](#signal-processing--math-models)
- [Repository Structure](#repository-structure)
- [REST API Reference](#rest-api-reference)
- [Testing & Quality Assurance](#testing--quality-assurance)

---

## Why LIVS?

Global Positioning System (GPS) fails indoors because satellite microwave signals cannot penetrate concrete, steel structural framing, and multiple building floors. Proprietary Ultra-Wideband (UWB) and specialized beacon hardware are expensive and difficult to scale.

**LIVS solves this using everyday hardware:**
- **Zero Proprietary Hardware**: Standard Android smartphones act as both fixed anchor beacons and tracked mobile clients.
- **Auto-Calibrating Anchor Grid**: Anchors measure peer distances wirelessly to calculate their own relative $(X, Y)$ room coordinates—eliminating manual tape measures.
- **Pure Local Network**: Runs entirely over local Wi-Fi or mobile hotspots with zero cloud dependency and zero external telemetry.
- **Aspect-Locked 2D Blueprint**: Real-time 2D floor plans on both mobile devices and desktop web browser dashboards.

---

## System Architecture

```text
               +--------------------------------------------------+
               |          Central Localization Server             |
               |        (Python Multi-Threaded HTTP Server)       |
               |  - NLLS Multilateration Engine (Gauss-Newton)    |
               |  - Real-time Aspect-Locked 2D Web Dashboard      |
               +--------------------------------------------------+
                        ^               ^               ^
     Anchor Heartbeats  |               | Reports       | Sync Position
     & Distance Matrices|               |               |
       +----------------+               |               +---------------+
       |                                |                               |
+---------------+               +---------------+               +---------------+
|  Anchor Node  |<--BLE Ping--->|  Anchor Node  |               | Tracked Phone |
|   (Room A)    |  (Pairwise)   |   (Room A)    |               |  (Locate Me)  |
|  Fixed Beacon |               |  Fixed Beacon |               | Mobile Client |
+---------------+               +---------------+               +---------------+
       \                               /                                /
        \--- Detects Client BLE Sighting ------------------------------/
```

1. **Fixed Anchor Nodes**: Placed at key positions in the room. They broadcast custom BLE manufacturer packets and continuously listen to other anchors and mobile devices.
2. **Mobile Clients ("Locate Me")**: Carried by users walking through the building. Broadcasts lightweight BLE identification packets.
3. **Central Server**: Ingests anchor signal sightings and computes precise $(X, Y)$ coordinates using Gauss-Newton Non-Linear Least Squares multilateration.

---

## Design Identity

LIVS features a **Charcoal + Industrial Orange** visual identity across mobile screens and the web dashboard:

| Element | Color Hex | Role |
| :--- | :--- | :--- |
| **Primary Background** | `#111111` | Deep field charcoal scaffold & body background |
| **Surface / Cards** | `#1B1B1B` | Elevated panels, cards, and modal sheets |
| **Primary Accent** | `#FF8A3D` | Vibrant industrial orange for active location pins & action buttons |
| **Secondary Accent** | `#F2C14E` | Warm amber/gold for anchor beacons and warnings |
| **Text Primary** | `#F5F5F5` | Crisp off-white typography for maximum readability |
| **Text Muted** | `#9CA3AF` | Slate neutral gray for subtext and dimensions |
| **Borders** | `#2E2E2E` | Subtle dividers and blueprint grid boundaries |

---

## Quick Start Guide

### Prerequisites
1. **Flutter SDK**: Version 3.19+ ([Install Flutter](https://docs.flutter.dev/get-started/install)).
2. **Android Devices**: Android 8.0+ (API 26+) with Bluetooth Low Energy (BLE) peripheral/advertising support.
3. **Python**: Version 3.8+ (Uses standard library; zero `pip` packages required).
4. **Network**: Computer and Android phones connected to the **same Wi-Fi network** or **phone mobile hotspot**.

---

### Step 1: Start Central Server

1. Open a terminal and navigate to the `server/` directory:
   ```bash
   cd server
   ```
2. Start the localization server (default port `8080`):
   ```bash
   python central_server.py 8080
   ```
3. The server prints its active local IP address:
   ```text
   =================================================================
     LIVS Central Indoor Localization Server (Multi-Threaded)
     Web Dashboard:    http://192.168.0.100:8080/
     API Status:       http://192.168.0.100:8080/api/status
     API Location:     http://192.168.0.100:8080/api/location?deviceId=TEST-C001
     Anchor Network:   http://192.168.0.100:8080/api/anchor/network
   =================================================================
   ```
4. Open the Web Dashboard in your browser: [http://localhost:8080](http://localhost:8080) (or using the local Wi-Fi IP).

---

### Step 2: Run Flutter App

1. In the project root, fetch dependencies:
   ```bash
   flutter pub get
   ```
2. Connect your Android phone via USB (with USB Debugging enabled) and run:
   ```bash
   flutter run
   ```
3. Grant the required permissions when prompted:
   - **Nearby Devices / Bluetooth Scan & Advertise**
   - **Location Permission** (required by Android OS for BLE discovery)

---

### Step 3: Setup Anchor Nodes

Deploy 2 or more phones as **Anchor Nodes** in the room (e.g. Room A):
1. On the first screen ("Choose Device Role"), tap **Option 1: Anchor Node**.
2. Expand **Advanced Server Settings (Optional)** and type the computer's server IP (e.g. `192.168.0.100:8080`).
3. Tap **ACTIVATE ANCHOR (ROOM A)**.
4. Place the phone in a fixed location.
5. Once 2 or 3 anchors are active in the same room, tap **AUTO-CALIBRATE & LOCK FIXED POINTS** on the Anchor screen to automatically calculate relative room coordinates and sync the anchor grid with the server.

---

### Step 4: Locate Mobile Clients

Deploy a phone as the **Tracked Device**:
1. On the role selection screen, tap **Option 2: Locate Me**.
2. Tap **START LOCATION TRACKING**.
3. The phone displays the real-time **2D Indoor Room Map**:
   - **Amber Dots (`#F2C14E`)**: Fixed Anchor Beacons with distances.
   - **Pulsing Orange Pin (`#FF8A3D`)**: Your real-time $(X, Y)$ position and active room.
4. The central server web dashboard simultaneously displays the tracked device moving across the blueprint floor plan.

---

## Dynamic Wi-Fi & Hotspot Switching

When moving between different Wi-Fi routers, campus networks, or mobile hotspots:
1. Note the new IP address printed in the server terminal (e.g. `10.13.225.58`).
2. In the mobile app, tap the **Server Config Icon** (or edit button on the Server Target card).
3. Enter the new IP address and tap **Test Connection**.
4. Tap **Save & Apply**—the app immediately reconnects without restarting.

---

## Signal Processing & Math Models

### 1. Log-Distance Path Loss Model
Distance $d$ is estimated from Received Signal Strength Indication (RSSI) using:
$$RSSI = -10n \log_{10}(d) + A$$
$$d = 10^{\frac{A - RSSI}{10n}}$$

- $A$ (or $RSSI_0$): Measured RSSI reference at 1.0 meter (calibrated per device, default $-59 \text{ dBm}$).
- $n$: Path Loss Exponent:
  - $n = 2.0$: Open halls / corridors
  - $n = 2.4$: Standard classrooms / labs with furniture *(Default)*
  - $n = 2.8$: Dense spaces with concrete pillars or human crowding

### 2. Signal Filtering Pipeline
Raw RSSI fluctuates due to multipath reflection and antenna orientation. LIVS stabilizes measurements with:
- **Outlier Rejection**: Rejects non-physical samples ($> -20 \text{ dBm}$ or $< -100 \text{ dBm}$).
- **Trailing Median Filter**: 5-sample sliding median eliminates impulse noise.
- **Moving Average Smoothing**: 3-sample window computes stable distance estimates.

### 3. Gauss-Newton NLLS Multilateration
The central server solves the client position $(x, y)$ by minimizing the sum of squared residuals across $N \ge 3$ anchors:
$$S(x, y) = \sum_{i=1}^N \left( \sqrt{(x - x_i)^2 + (y - y_i)^2} - d_i \right)^2$$
Iteratively refined via Jacobian matrix inversion until convergence ($\Delta < 0.001\text{m}$).

---

## Repository Structure

```text
livs/
├── lib/
│   ├── main.dart                          # App entry point & role shell router
│   ├── models/
│   │   ├── anchor_network.dart            # Anchor network topology & coordinate models
│   │   └── ble_device.dart                # BLE device telemetry & signal history
│   ├── services/
│   │   ├── ble_advertiser.dart            # BLE custom manufacturer packet advertising
│   │   ├── ble_scanner.dart               # BLE discovery & RSSI packet parsing
│   │   ├── central_server_service.dart    # HTTP sync client for central localization server
│   │   ├── measurement_repository.dart    # Signal aggregation & relative coordinate solver
│   │   └── storage_service.dart           # Persistent preferences & config management
│   ├── utils/
│   │   ├── app_theme.dart                 # Centralized Charcoal + Orange design system
│   │   ├── distance_estimator.dart        # Log-distance path loss implementation
│   │   └── rssi_processor.dart            # Median filter & moving average algorithms
│   └── views/
│       ├── role_selection_view.dart       # Device role selector (Anchor vs Client)
│       ├── anchor_node_view.dart          # Anchor management & peer grid auto-calibration
│       ├── tracked_map_view.dart          # Client 2D blueprint map with live pulsing pin
│       ├── calibration_view.dart          # 1-meter RSSI reference & n-exponent calibration
│       ├── dashboard_view.dart            # Raw BLE diagnostic monitor & scanner toggle
│       └── widgets/
│           ├── custom_chart.dart          # Real-time RSSI signal oscilloscope
│           ├── server_config_dialog.dart  # Dynamic IP configuration modal
│           └── expandable_text.dart       # Collapsible documentation cards
├── server/
│   └── central_server.py                  # Standalone multi-threaded Python server & web UI
├── test/
│   ├── unit_test.dart                     # Math, filter, and trilateration unit tests
│   └── widget_test.dart                   # UI theme & color token verification tests
└── pubspec.yaml                           # Flutter dependencies & metadata
```

---

## REST API Reference

The central server exposes the following endpoints:

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/` | Web Dashboard with aspect-locked 2D Blueprint Canvas |
| `GET` | `/api/status` | Current server state, registered anchors, and tracked clients |
| `GET` | `/api/location?deviceId=<ID>` | Solved $(X, Y)$ position and active room for a client |
| `GET` | `/api/anchor/network` | Active solved anchor network coordinates |
| `POST` | `/api/anchor/heartbeat` | Anchor keep-alive with coordinates and room identity |
| `POST` | `/api/anchor/network` | Upload calibrated anchor relative coordinate matrix |
| `POST` | `/api/report` | Anchors submit client BLE distance sightings |

---

## Testing & Quality Assurance

LIVS includes a comprehensive unit and widget test suite covering signal filtering, path loss calculations, trilateration geometry, and UI tokens.

Run the test suite:
```bash
flutter test
```

Expected output:
```text
00:01 +10: All tests passed!
```

---

## License

This project is developed for educational and research purposes under the Problem Based Learning (PBL) curriculum.
