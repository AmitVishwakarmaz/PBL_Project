# LIVS: Lightweight Indoor Localization & Verification System

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Python](https://img.shields.io/badge/Python-3.8+-3776AB?logo=python&logoColor=white)](https://www.python.org)
[![Bluetooth Low Energy](https://img.shields.io/badge/BLE-Low_Energy-0082FC?logo=bluetooth)](https://en.wikipedia.org/wiki/Bluetooth_Low_Energy)
[![Architecture](https://img.shields.io/badge/Architecture-Decentralized_Anchors-FF8A3D)]()
[![Design System](https://img.shields.io/badge/Theme-Charcoal_%2B_Orange-1B1B1B)]()
[![Security](https://img.shields.io/badge/Security-Proof_of_Location-green)]()

LIVS is an infrastructure-grade **indoor localization and decentralized physical location verification system** designed for GPS-denied environments and fraud-resistant positioning. By combining smartphone Bluetooth Low Energy (BLE) peripheral broadcasting, adaptive path-loss signal filtering, automated peer-to-peer pairwise coordinate calibration, and central Non-Linear Least Squares (NLLS) multilateration, LIVS pinpoints mobile devices in real time with sub-room precision—without relying on unverified client GPS telemetry.

---

## Table of Contents
- [Executive Summary & Problem Statement](#executive-summary--problem-statement)
  - [The Vulnerability of GPS & Location Spoofing Fraud](#the-vulnerability-of-gps--location-spoofing-fraud)
  - [The LIVS Solution: Decentralized Physical Proof of Location (PoL)](#the-livs-solution-decentralized-physical-proof-of-location-pol)
- [Theoretical & Mathematical Foundations](#theoretical--mathematical-foundations)
  - [1. Log-Distance Path Loss RF Propagation Model](#1-log-distance-path-loss-rf-propagation-model)
  - [2. Multi-Stage Signal Noise Mitigation Pipeline](#2-multi-stage-signal-noise-mitigation-pipeline)
  - [3. Pairwise Anchor Network Auto-Calibration Geometry](#3-pairwise-anchor-network-auto-calibration-geometry)
  - [4. Gauss-Newton Non-Linear Least Squares (NLLS) Multilateration](#4-gauss-newton-non-linear-least-squares-nlls-multilateration)
- [System Architecture & Operational Dataflow](#system-architecture--operational-dataflow)
- [Enterprise Scaling & Industrial Deployment Roadmap](#enterprise-scaling--industrial-deployment-roadmap)
  - [1. Hardware Evolution (BLE 5.1 AoA, UWB, Wi-Fi 6 RTT)](#1-hardware-evolution-ble-51-aoa-uwb-wi-fi-6-rtt)
  - [2. Cryptographic Hardware Attestation & Trust Enclaves](#2-cryptographic-hardware-attestation--trust-enclaves)
  - [3. Decentralized Physical Infrastructure Networks (DePIN) & ZK-Proofs](#3-decentralized-physical-infrastructure-networks-depin--zk-proofs)
  - [4. Hierarchical Edge Compute & Spatial Sharding](#4-hierarchical-edge-compute--spatial-sharding)
- [Design System & Visual Identity](#design-system--visual-identity)
- [Quick Start & Setup Guide](#quick-start--setup-guide)
  - [Prerequisites](#prerequisites)
  - [Step 1: Start Central Server](#step-1-start-central-server)
  - [Step 2: Build & Deploy Flutter App](#step-2-build--deploy-flutter-app)
  - [Step 3: Deploy & Calibrate Anchor Network](#step-3-deploy--calibrate-anchor-network)
  - [Step 4: Track Mobile Clients](#step-4-track-mobile-clients)
- [Dynamic Network & Server IP Configuration](#dynamic-network--server-ip-configuration)
- [Repository Structure](#repository-structure)
- [REST API Reference](#rest-api-reference)
- [Testing & Quality Assurance](#testing--quality-assurance)

---

## Executive Summary & Problem Statement

### The Vulnerability of GPS & Location Spoofing Fraud

Global Positioning System (GPS / GNSS) is the standard for outdoor positioning, but it suffers from two fatal flaws in modern digital infrastructure:

1. **Physical Signals Inability Indoors**: Satellite microwave signals ($1.5 \text{ GHz}$) attenuate sharply through concrete slabs, steel reinforcement, and multi-story structural elements, causing massive dilution of precision (DOP) or complete blackout inside buildings.
2. **Extreme Susceptibility to Location Fraud**: GPS relies on **unverified, client-reported telemetry**. Mobile operating systems expose APIs (e.g., Android `Mock Location`, iOS developer mode) that allow software applications to report arbitrary $(X, Y)$ coordinates. Furthermore, low-cost HackRF/SDR hardware can easily perform **RF GPS Spoofing** by broadcasting fake satellite signals.

#### Real-World Fraud Vectors:
- **Corporate Attendance & Geo-Fencing Fraud**: Employees clocking into work remotely using mock location applications.
- **Financial & Mobile Banking Fraud**: Fraudsters bypassing location-based 2FA or geo-restricted transaction limits.
- **Logistics & High-Value Asset Theft**: Drivers spoofing GPS logs while diverting valuable cargo.
- **Perimeter Access Control**: Unauthorized access to high-security facilities via manipulated coordinates.

```text
TRADITIONAL GPS MODEL (Vulnerable to Fraud)
+-------------------+      Self-Reported GPS (Fake)     +-------------------+
|  Target Client    | --------------------------------> |   Access Server   |
| (GPS Mock App On) |   "I am inside Secure Vault"      | (Blindly Trusts)  |
+-------------------+                                   +-------------------+

LIVS PROOF-OF-LOCATION MODEL (Fraud-Resistant)
+-------------------+          BLE Ping                 +-------------------+
|  Target Client    | ================================> |   Anchor Node A   | --\
| (Cannot Fake RF)  |                                   +-------------------+    \  Independent Sightings
+-------------------+                                                            +--> Central Server
          ||                   BLE Ping                 +-------------------+    /   (Verifies & Solves)
          +===========================================> |   Anchor Node B   | --/
                                                        +-------------------+
```

### The LIVS Solution: Decentralized Physical Proof of Location (PoL)

LIVS replaces **client self-reporting** with **multi-observer physical attestation**:

- **Physical Observer Consensus**: Mobile clients do not claim their position. Instead, surrounding **fixed physical Anchor Nodes** continuously listen for raw radio signals (BLE manufacturer pings) emitted by the client device.
- **Decentralized Multi-Node Triangulation**: The location $(X, Y)$ is computed from the physical signal sightings recorded by multiple independent spatial observers.
- **Anti-Spoofing Guarantee**: A user cannot fake their indoor position via software. Even if the client OS is rooted or running mock location tools, the physical anchor nodes measure the *actual* radio frequency energy arriving at their physical antennas.

---

## Theoretical & Mathematical Foundations

### 1. Log-Distance Path Loss RF Propagation Model

Radio frequency signal power decays logarithmically over distance. The Received Signal Strength Indication (RSSI) in $\text{dBm}$ is modeled using the **Log-Distance Path Loss Model**:

$$RSSI(d) = -10n \log_{10}(d) + A$$

Solving for distance $d$ (in meters):

$$d = 10^{\left( \frac{A - RSSI}{10n} \right)}$$

Where:
- $RSSI$: Measured signal power in $\text{dBm}$ at the receiving anchor.
- $A$ ($RSSI_0$): Calibrated reference RSSI at a distance of $1.0\text{ m}$ (default $-59\text{ dBm}$ for standard smartphone BLE chips).
- $n$: Environmental Path-Loss Exponent representing attenuation factors:
  - $n = 2.0$: Free space / open hallway line-of-sight.
  - $n = 2.4$: Standard furnished office / classroom (*Default*).
  - $n = 2.8 - 3.2$: Dense structural environments with concrete columns, metal partitions, and high human crowding.

### 2. Multi-Stage Signal Noise Mitigation Pipeline

Raw RSSI signals exhibit heavy variance (noise up to $\pm 12\text{ dBm}$) due to multipath reflections, constructive/destructive interference, body shadowing, and antenna gain variations. LIVS applies a 3-stage signal conditioning pipeline before feeding RSSI values to distance solvers:

```text
Raw BLE Packet ---> [ Stage 1: Outlier Rejection ] ---> [ Stage 2: Trailing Median ] ---> [ Stage 3: Moving Average ] ---> Stable RSSI
```

1. **Stage 1: Outlier Rejection**: Filters non-physical RSSI readings outside $[-100\text{ dBm}, -20\text{ dBm}]$.
2. **Stage 2: 5-Sample Trailing Median Filter**: Removes high-amplitude transient impulse spikes without introducing phase delay.
3. **Stage 3: 3-Sample Moving Average Filter**: Smooths subtle thermal noise to yield stable, monotonic distance estimates.

### 3. Pairwise Anchor Network Auto-Calibration Geometry

Traditional indoor localization requires tedious manual surveying of anchor coordinates. LIVS features an **automated P2P pairwise distance matrix calibration protocol**:

Given 3 Anchor Nodes ($A, B, C$) deployed in a room:
1. Anchors measure pairwise RSSI distances $D_{AB}, D_{AC}, D_{BC}$ wirelessly.
2. The coordinate system is established automatically:
   - Anchor A is fixed at the origin: $(x_A, y_A) = (0, 0)$
   - Anchor B defines the horizontal X-axis: $(x_B, y_B) = (D_{AB}, 0)$
   - Anchor C coordinates $(x_C, y_C)$ are solved using law of cosines trilateration:

$$x_C = \frac{D_{AB}^2 + D_{AC}^2 - D_{BC}^2}{2 \cdot D_{AB}}$$

$$y_C = \sqrt{\max\left(0, D_{AC}^2 - x_C^2\right)}$$

### 4. Gauss-Newton Non-Linear Least Squares (NLLS) Multilateration

When $N \ge 3$ anchor nodes report client distance sightings $d_i$, the system over-determines the client position $(x, y)$. LIVS minimizes the sum of weighted squared distance residual errors:

$$S(x, y) = \sum_{i=1}^{N} w_i \cdot \left( \sqrt{(x - x_i)^2 + (y - y_i)^2} - d_i \right)^2$$

Where weight $w_i = \frac{1}{\max(0.3, d_i)}$ gives higher priority to closer, more reliable anchors.

#### Iterative Solver Algorithm:
1. **Initial Estimate**: Calculated via inverse-distance weighted centroid:
   $$x_0 = \frac{\sum \frac{x_i}{d_i^2}}{\sum \frac{1}{d_i^2}}, \quad y_0 = \frac{\sum \frac{y_i}{d_i^2}}{\sum \frac{1}{d_i^2}}$$
2. **Jacobian Matrix Construction**: For each anchor $i$, residual $r_i = \sqrt{(x - x_i)^2 + (y - y_i)^2}$, Jacobian components are:
   $$J_{i,1} = \frac{x - x_i}{r_i}, \quad J_{i,2} = \frac{y - y_i}{r_i}$$
3. **Normal Equations Update**: Computes updates $[\Delta x, \Delta y]^T = (J^T W J + \lambda I)^{-1} J^T W e$ until step delta converges ($< 0.01\text{m}$) or max iterations (10) are reached.

---

## System Architecture & Operational Dataflow

```text
+-----------------------------------------------------------------------------------+
|                            LIVS ECOSYSTEM ARCHITECTURE                            |
+-----------------------------------------------------------------------------------+

     [ MOBILE CLIENT (Tracked Device) ]           [ ANCHOR NODES (Fixed Observers) ]
    +----------------------------------+         +----------------------------------+
    |  - Flutter Mobile Application    |         |  - Flutter App in Anchor Role    |
    |  - BLE Advertiser Service        |         |  - Continuous BLE Scanner        |
    |  - Manufacturer Data Payload:    |         |  - RSSI Processor & Path Loss    |
    |    [UUID | TxPower | DeviceID]   |         |  - Pairwise Auto-Calibration     |
    +----------------------------------+         +----------------------------------+
                     |                                            |
                     | 1. Broadcasts BLE Pings                    | 2. Detects RSSI & Measures
                     +===========================================>|    Distance Sightings
                                                                  |
                                                                  | 3. Posts Telemetry via
                                                                  |    HTTP REST API
                                                                  v
+-----------------------------------------------------------------------------------+
|                       CENTRAL LOCALIZATION SERVER (Python)                        |
|                                                                                   |
|  +---------------------------+  +------------------------+  +------------------+  |
|  | Multi-Threaded HTTP API   |  | NLLS Gauss-Newton      |  | Real-Time Web    |  |
|  | Ingests Sightings & Maps  |  | Multilateration Engine |  | Dashboard Canvas |  |
|  +---------------------------+  +------------------------+  +------------------+  |
+-----------------------------------------------------------------------------------+
                                          |
                                          | 4. Returns Solved (X,Y) & Confidence
                                          v
                         [ REAL-TIME CANVAS BLUEPRINT MAP ]
                         - Mobile App View & Web Dashboard
```

---

## Enterprise Scaling & Industrial Deployment Roadmap

While the LIVS prototype uses standard Android smartphones with BLE RSSI for rapid deployment and testing, scaling this concept into an enterprise-grade, high-accuracy, anti-fraud infrastructure requires key technological upgrades:

```text
PROTOTYPE (LIVS Current)               ENTERPRISE PRODUCTION ROADMAP
+-----------------------+              +-----------------------------------------+
| Commodity Smartphones |              | Dedicated Hardware Arrays & Anchors     |
| BLE RSSI Ranging      |  --------->  | UWB (802.15.4z) + BLE 5.1 AoA + Wi-Fi FTM|
| 1 - 3m Accuracy       |              | Sub-10cm Precision                      |
| HTTP REST Polling     |              | Hardware Crypto Attestation & DePIN PoL |
+-----------------------+              +-----------------------------------------+
```

### 1. Hardware Evolution (BLE 5.1 AoA, UWB, Wi-Fi 6 RTT)

To transition from room-level accuracy ($1 - 3\text{m}$) to centimeter precision ($< 10\text{cm}$):

| Technology | Signal Property | Typical Accuracy | Advantages | Role in Large-Scale Deployment |
| :--- | :--- | :--- | :--- | :--- |
| **BLE RSSI (Current)** | Signal Power Decay | $1.5\text{m} - 3.0\text{m}$ | Zero hardware cost; works on all phones | Baseline coverage & crowd-sourced anchor pings |
| **BLE 5.1 / 5.2 AoA** | Phase Difference across Antenna Array | $0.3\text{m} - 0.8\text{m}$ | Measures Angle ($\theta, \phi$) & distance; requires fewer anchors | Multi-story building lobbies & hallway tracking |
| **UWB (IEEE 802.15.4z)** | Time-of-Flight (ToF) & SDS-TWR | **$2\text{cm} - 10\text{cm}$** | Impervious to RSSI multipath fading & walls | High-security vaults, cleanrooms, industrial robotics |
| **Wi-Fi 6/6E/7 FTM** | Fine Timing Measurement (802.11mc) | $0.5\text{m} - 1.0\text{m}$ | Native support in enterprise Wi-Fi APs (Cisco/Aruba) | Campus-wide & airport passenger verification |

### 2. Cryptographic Hardware Attestation & Trust Enclaves

To prevent malicious anchor nodes or rogue devices from injecting false sightings into the network:

- **Secure Enclave / TPM Attestation**: Anchor nodes sign every distance measurement using hardware-backed private keys stored within ARM TrustZone / Android StrongBox / Apple Secure Enclave.
- **Nonce-Based Challenge-Response**: Central servers issue cryptographic pings with short-lived nonces to client devices. Clients must respond over radio frequency within nanosecond time windows, preventing relay/replay attacks.

### 3. Decentralized Physical Infrastructure Networks (DePIN) & ZK-Proofs

In large-scale smart cities or multi-tenant commercial complexes, central server reliance can be a single point of failure and a privacy concern.

- **Zero-Knowledge Location Proofs (ZK-PoL)**: Enables users to prove *"I am physically inside office Zone A"* to an authentication server **without revealing their exact continuous $(X,Y)$ coordinate track** or compromising personal privacy.
- **DePIN Consensus**: Anchor nodes operate as decentralized verifiers on an edge ledger, cross-signing location attestations to create immutable audit trails for logistics and high-value compliance.

### 4. Hierarchical Edge Compute & Spatial Sharding

For multi-building campuses with thousands of simultaneous tracked clients:

- **Edge Gateways**: Low-power edge units (e.g., Raspberry Pi 5 / NVIDIA Jetson) process room-level multi-lateration locally, forwarding only solved location events to central brokers via MQTT/gRPC.
- **Spatial Indexing (Uber H3 / QuadTree)**: Floor plans are partitioned into dynamic spatial tiles, enabling sub-millisecond query performance across millions of square feet.

---

## Design System & Visual Identity

LIVS features a **Charcoal + Industrial Orange** dark theme built for high contrast and tactical clarity:

| Token Name | Hex Code | Visual Preview | Operational Role |
| :--- | :--- | :--- | :--- |
| `scaffoldBackground` | `#111111` | ![#111111](https://via.placeholder.com/12/111111/111111.png) | Deep dark charcoal field |
| `cardColor` | `#1B1B1B` | ![#1B1B1B](https://via.placeholder.com/12/1B1B1B/1B1B1B.png) | Elevated surface cards & modal sheets |
| `primaryAccent` | `#FF8A3D` | ![#FF8A3D](https://via.placeholder.com/12/FF8A3D/FF8A3D.png) | Active target location pin & primary buttons |
| `anchorBeacon` | `#F2C14E` | ![#F2C14E](https://via.placeholder.com/12/F2C14E/F2C14E.png) | Calibrated fixed anchor nodes |
| `textPrimary` | `#F5F5F5` | ![#F5F5F5](https://via.placeholder.com/12/F5F5F5/F5F5F5.png) | Crisp off-white typography |
| `textMuted` | `#9CA3AF` | ![#9CA3AF](https://via.placeholder.com/12/9CA3AF/9CA3AF.png) | Slate neutral gray for subtext & telemetry |
| `borderOutline` | `#2E2E2E` | ![#2E2E2E](https://via.placeholder.com/12/2E2E2E/2E2E2E.png) | Blueprint canvas grid lines & dividers |

---

## Quick Start & Setup Guide

### Prerequisites
1. **Flutter SDK**: Version `3.19+` ([Install Flutter](https://docs.flutter.dev/get-started/install)).
2. **Android Devices**: Minimum Android 8.0+ (API 26+) with Bluetooth Low Energy (BLE) advertising support.
3. **Python**: Version `3.8+` (Uses standard library; zero external `pip` dependencies).
4. **Local Network**: All devices must be connected to the same Wi-Fi router or mobile hotspot.

---

### Step 1: Start Central Server

1. Open a terminal and navigate to the `server/` directory:
   ```bash
   cd server
   ```
2. Launch the multi-threaded localization server:
   ```bash
   python central_server.py 8080
   ```
3. Terminal displays active binding configuration:
   ```text
   =================================================================
     LIVS Central Indoor Localization Server (Multi-Threaded)
     Web Dashboard:    http://192.168.1.50:8080/
     API Status:       http://192.168.1.50:8080/api/status
     API Location:     http://192.168.1.50:8080/api/location?deviceId=TEST-C001
     Anchor Network:   http://192.168.1.50:8080/api/anchor/network
   =================================================================
   ```
4. Access the web dashboard in your browser: [http://localhost:8080](http://localhost:8080).

---

### Step 2: Build & Deploy Flutter App

1. Fetch dependencies from root directory:
   ```bash
   flutter pub get
   ```
2. Connect your test smartphone via USB and run:
   ```bash
   flutter run
   ```
3. Accept runtime permission prompts:
   - **Bluetooth Scan & Advertise / Nearby Devices**
   - **Fine Location Permission** (OS requirement for BLE discovery)

---

### Step 3: Deploy & Calibrate Anchor Network

Deploy 2 or 3 smartphones as fixed **Anchor Nodes** in the physical room:
1. Open app -> Select **Option 1: Anchor Node**.
2. Configure computer's server IP in settings (e.g., `192.168.1.50:8080`).
3. Tap **ACTIVATE ANCHOR (ROOM A)** and place the phone at a fixed position.
4. Once all room anchors are active, tap **AUTO-CALIBRATE & LOCK FIXED POINTS**. The anchors automatically execute pairwise ranging and upload relative $(X,Y)$ coordinates to the central server.

---

### Step 4: Track Mobile Clients

Deploy a smartphone as the **Tracked Target**:
1. Select **Option 2: Locate Me**.
2. Tap **START LOCATION TRACKING**.
3. View real-time position on the aspect-locked 2D room canvas.
4. Observe synchronized movements on the central server web dashboard.

---

## Dynamic Network & Server IP Configuration

When switching between Wi-Fi networks, router subnets, or mobile phone hotspots:

```text
[ Mobile App UI ] ---> Tap Server Settings Icon ---> Enter New Server IP:Port ---> Tap "Save & Apply"
```

The app updates its HTTP sync target dynamically without app restarts or rebuilding binaries.

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
| `GET` | `/` | Web Dashboard with live aspect-locked 2D Blueprint Canvas |
| `GET` | `/api/status` | Real-time state of registered anchors, reports, and active clients |
| `GET` | `/api/location?deviceId=<ID>` | Solved $(X, Y)$ coordinate and room assignment for target client |
| `GET` | `/api/anchor/network` | Current active solved anchor network coordinates |
| `POST` | `/api/anchor/heartbeat` | Anchor node keep-alive ping with room & coordinate identity |
| `POST` | `/api/anchor/network` | Upload auto-calibrated anchor coordinate layout |
| `POST` | `/api/report` | Anchors submit client BLE distance sightings |

---

## Testing & Quality Assurance

LIVS includes a complete unit test suite covering path loss math, signal filtering pipelines, trilateration geometry, and UI tokens.

Run the test suite:
```bash
flutter test
```

Expected output:
```text
00:01 +10: All tests passed!
```

---

## License & Project Context

Developed under the **Problem Based Learning (PBL)** curriculum for research and engineering in indoor positioning systems, radio frequency signal processing, and fraud-resistant decentralized location verification.
