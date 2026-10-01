#!/usr/bin/env python3
"""
LIVS Central Indoor Localization Server
Standalone Multi-Threaded Python HTTP Server for aggregating anchor reports
and calculating client device indoor room location via Gauss-Newton NLLS Multilateration.
Zero external dependencies (uses standard library).

Usage:
    python central_server.py [port]
Example:
    python central_server.py 8080
"""

import sys
import json
import math
import socket
from datetime import datetime, timedelta
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

# In-memory database of registered anchors, anchor reports, network layout, and solved locations
registered_anchors = {}  # anchorId -> dict(anchorId, friendlyName, roomName, x, y, lastSeen)
device_reports = {}      # targetDeviceId -> list of reports
solved_locations = {}    # targetDeviceId -> location dict
active_anchor_map = None # Solved anchor network geometry

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'

HTML_DASHBOARD = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>LIVS Central Indoor Localization Server</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; }
    body { background-color: #111111; color: #F5F5F5; min-height: 100vh; padding: 24px; line-height: 1.5; }
    
    /* Header */
    .header { display: flex; justify-content: space-between; align-items: center; border-bottom: 1px solid #2E2E2E; padding-bottom: 16px; margin-bottom: 24px; flex-wrap: wrap; gap: 12px; }
    .title-group h1 { font-size: 20px; font-weight: 800; color: #F5F5F5; letter-spacing: -0.3px; display: flex; align-items: center; gap: 10px; }
    .title-group h1 .accent-icon { width: 10px; height: 10px; border-radius: 50%; background: #FF8A3D; display: inline-block; }
    .title-group p { font-size: 13px; color: #9CA3AF; margin-top: 3px; }
    
    .status-badge { display: inline-flex; align-items: center; gap: 8px; padding: 6px 14px; border-radius: 9999px; font-size: 12px; font-weight: 600; background: #1B1B1B; color: #F5F5F5; border: 1px solid #2E2E2E; }
    .status-badge .dot { width: 8px; height: 8px; border-radius: 50%; background: #34D399; animation: pulse 1.8s infinite; }
    @keyframes pulse { 0%, 100% { opacity: 1; transform: scale(1); } 50% { opacity: 0.4; transform: scale(0.85); } }
    
    /* Grid Layout */
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(340px, 1fr)); gap: 20px; margin-bottom: 24px; }
    .card { background: #1B1B1B; border: 1px solid #2E2E2E; border-radius: 12px; padding: 20px; }
    .card-title { font-size: 12px; font-weight: 800; color: #FF8A3D; text-transform: uppercase; letter-spacing: 1.0px; margin-bottom: 14px; display: flex; justify-content: space-between; align-items: center; }
    .card-title span.count { background: #242424; color: #F5F5F5; padding: 2px 8px; border-radius: 6px; font-size: 11px; font-weight: 600; border: 1px solid #2E2E2E; }
    
    /* Tables */
    .table-container { overflow-x: auto; }
    table { width: 100%; border-collapse: collapse; font-size: 13px; }
    th { text-align: left; padding: 10px 12px; color: #9CA3AF; font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.5px; border-bottom: 1px solid #2E2E2E; }
    td { padding: 12px; border-bottom: 1px solid #222222; }
    tr:last-child td { border-bottom: none; }
    tr:hover td { background-color: #202020; }
    .empty-state { text-align: center; padding: 28px; color: #6B7280; font-size: 13px; }
    
    /* Tags & Pills */
    .room-pill { background: rgba(255, 138, 61, 0.12); color: #FF8A3D; padding: 3px 8px; border-radius: 4px; font-size: 11px; font-weight: 600; border: 1px solid rgba(255, 138, 61, 0.3); }
    .anchor-badge { color: #F2C14E; font-weight: 600; }
    .active-pill { color: #34D399; font-weight: 600; font-size: 12px; display: inline-flex; align-items: center; gap: 4px; }
    .active-pill::before { content: "●"; font-size: 10px; }
    
    /* 2D Canvas & HUD */
    .canvas-card { background: #1B1B1B; border: 1px solid #2E2E2E; border-radius: 12px; padding: 20px; }
    .canvas-wrapper { position: relative; width: 100%; height: 520px; background: #141414; border-radius: 8px; border: 1px solid #262626; overflow: hidden; }
    canvas { width: 100%; height: 100%; display: block; }
    
    /* HUD Overlays */
    .hud-top-left { position: absolute; top: 12px; left: 12px; display: flex; flex-direction: column; gap: 6px; pointer-events: none; }
    .hud-top-right { position: absolute; top: 12px; right: 12px; display: flex; gap: 8px; pointer-events: none; flex-wrap: wrap; }
    .hud-pill { background: rgba(27, 27, 27, 0.92); border: 1px solid #2E2E2E; padding: 5px 10px; border-radius: 6px; font-size: 11px; color: #F5F5F5; display: flex; align-items: center; gap: 6px; backdrop-filter: blur(4px); }
    .legend-item { background: rgba(27, 27, 27, 0.92); border: 1px solid #2E2E2E; padding: 5px 10px; border-radius: 6px; font-size: 11px; color: #9CA3AF; display: flex; align-items: center; gap: 6px; }
    .legend-dot { width: 8px; height: 8px; border-radius: 50%; }
    
    /* Links */
    .links { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; font-size: 12px; align-items: center; }
    .links a { color: #9CA3AF; text-decoration: none; background: #222222; padding: 6px 12px; border-radius: 6px; border: 1px solid #2E2E2E; transition: all 0.15s ease; }
    .links a:hover { color: #FF8A3D; border-color: #FF8A3D; background: #282828; }
  </style>
</head>
<body>
  <div class="header">
    <div class="title-group">
      <h1><span class="accent-icon"></span> LIVS Indoor Positioning Server</h1>
      <p>Decentralized Multi-Anchor BLE Localization • NLLS Multilateration Engine</p>
    </div>
    <div class="status-badge">
      <div class="dot"></div>
      <span id="server-status">ONLINE • HOST: <span id="host-ip">...</span></span>
    </div>
  </div>

  <div class="grid">
    <!-- Anchors Card -->
    <div class="card">
      <div class="card-title">
        <span>Active Anchor Nodes (Beacons)</span>
        <span class="count" id="anchor-count">0</span>
      </div>
      <div class="table-container">
        <table>
          <thead>
            <tr>
              <th>Anchor ID</th>
              <th>Room</th>
              <th>Fixed Position</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody id="anchors-tbody">
            <tr><td colspan="4" class="empty-state">No anchors registered yet. Configure server target IP in the Flutter app.</td></tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Tracked Devices Card -->
    <div class="card">
      <div class="card-title">
        <span>Locate Me (Tracked Mobile Devices)</span>
        <span class="count" id="tracked-count">0</span>
      </div>
      <div class="table-container">
        <table>
          <thead>
            <tr>
              <th>Device ID</th>
              <th>Room</th>
              <th>Estimated Position (X, Y)</th>
              <th>Confidence</th>
            </tr>
          </thead>
          <tbody id="tracked-tbody">
            <tr><td colspan="4" class="empty-state">Waiting for client device in "Locate Me" mode...</td></tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- 2D Real-time Indoor Map Canvas -->
  <div class="canvas-card">
    <div class="card-title">
      <span>Real-Time 2D Indoor Room Blueprint Map</span>
      <span style="font-size: 11px; color: #9CA3AF; text-transform: none; font-weight: normal;">Aspect-locked • 1m Grid System • Auto-sync</span>
    </div>
    
    <div class="canvas-wrapper">
      <canvas id="mapCanvas"></canvas>
      
      <div class="hud-top-left">
        <div class="hud-pill">
          <span style="color:#FF8A3D; font-weight:bold;">SPACE:</span>
          <span>Room A (6.0m × 5.0m)</span>
        </div>
        <div class="hud-pill">
          <span style="color:#9CA3AF;">SCALE:</span>
          <span>1 Grid Square = 1.0 Meter</span>
        </div>
      </div>

      <div class="hud-top-right">
        <div class="legend-item">
          <span class="legend-dot" style="background:#F2C14E;"></span>
          <span>Anchor Beacons</span>
        </div>
        <div class="legend-item">
          <span class="legend-dot" style="background:#FF8A3D;"></span>
          <span>Tracked Mobile Client</span>
        </div>
      </div>
    </div>

    <div class="links">
      <span style="color:#9CA3AF; font-size: 11px; text-transform: uppercase; font-weight: 700; letter-spacing: 0.5px;">API Quick Links:</span>
      <a href="/api/status" target="_blank">GET /api/status</a>
      <a href="/api/anchor/network" target="_blank">GET /api/anchor/network</a>
      <a href="/api/location?deviceId=TEST-C001" target="_blank">GET /api/location</a>
    </div>
  </div>

  <script>
    const canvas = document.getElementById('mapCanvas');
    const ctx = canvas.getContext('2d');

    let currentAnchors = [];
    let currentDevices = [];

    // Periodic Server State Polling (Every 1s)
    async function updateDashboard() {
      try {
        const res = await fetch('/api/status');
        if (!res.ok) return;
        const data = await res.json();

        document.getElementById('host-ip').textContent = `${data.serverIp}:${data.port}`;
        document.getElementById('anchor-count').textContent = data.anchorsCount || 0;
        document.getElementById('tracked-count').textContent = data.trackedDevicesCount || 0;

        currentAnchors = data.anchors || [];
        currentDevices = Object.values(data.devices || {});

        // Render Anchors Table
        const aTbody = document.getElementById('anchors-tbody');
        if (currentAnchors.length === 0) {
          aTbody.innerHTML = '<tr><td colspan="4" class="empty-state">No anchors registered yet. Configure server target IP in the Flutter app.</td></tr>';
        } else {
          aTbody.innerHTML = currentAnchors.map(a => `
            <tr>
              <td>
                <strong style="color:#F5F5F5;">${escapeHtml(a.friendlyName || a.anchorId)}</strong><br>
                <span style="color:#6B7280; font-size:11px; font-family: monospace;">${escapeHtml(a.anchorId)}</span>
              </td>
              <td><span class="room-pill">${escapeHtml(a.roomName || 'Room A')}</span></td>
              <td class="anchor-badge">(${Number(a.x).toFixed(2)}m, ${Number(a.y).toFixed(2)}m)</td>
              <td><span class="active-pill">Online</span></td>
            </tr>
          `).join('');
        }

        // Render Tracked Devices Table
        const tTbody = document.getElementById('tracked-tbody');
        if (currentDevices.length === 0) {
          tTbody.innerHTML = '<tr><td colspan="4" class="empty-state">Waiting for client device in "Locate Me" mode...</td></tr>';
        } else {
          tTbody.innerHTML = currentDevices.map(d => `
            <tr>
              <td>
                <strong style="color:#FF8A3D;">${escapeHtml(d.deviceId)}</strong>
              </td>
              <td><span class="room-pill">${escapeHtml(d.roomName)}</span></td>
              <td><strong style="color:#F5F5F5;">(${Number(d.x).toFixed(2)}m, ${Number(d.y).toFixed(2)}m)</strong></td>
              <td>
                <span style="color:#34D399; font-weight:600;">${Math.round(d.confidence)}%</span>
                <span style="color:#6B7280; font-size:11px;">(Nearest: ${escapeHtml(d.nearestAnchorId || 'N/A')} ~${Number(d.nearestDistance || 0).toFixed(1)}m)</span>
              </td>
            </tr>
          `).join('');
        }
      } catch (err) {
        console.error("Dashboard poll error:", err);
      }
    }

    function escapeHtml(str) {
      if (!str) return '';
      return String(str).replace(/[&<>"']/g, function(m) {
        return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[m];
      });
    }

    // 60FPS Aspect-Locked Canvas Rendering Loop
    function renderFrame() {
      // 1. Maintain sharp HiDPI resolution matching container rect
      const rect = canvas.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      const displayW = rect.width;
      const displayH = rect.height;

      const targetW = Math.round(displayW * dpr);
      const targetH = Math.round(displayH * dpr);
      if (canvas.width !== targetW || canvas.height !== targetH) {
        canvas.width = targetW;
        canvas.height = targetH;
      }

      ctx.save();
      ctx.scale(dpr, dpr);
      ctx.clearRect(0, 0, displayW, displayH);

      // 2. Compute World Coordinate Bounding Box (Default Room A: 6.0m x 5.0m)
      let minX = 0.0, maxX = 6.0, minY = 0.0, maxY = 5.0;
      currentAnchors.forEach(a => {
        minX = Math.min(minX, Number(a.x) || 0);
        maxX = Math.max(maxX, Number(a.x) || 0);
        minY = Math.min(minY, Number(a.y) || 0);
        maxY = Math.max(maxY, Number(a.y) || 0);
      });
      currentDevices.forEach(d => {
        minX = Math.min(minX, Number(d.x) || 0);
        maxX = Math.max(maxX, Number(d.x) || 0);
        minY = Math.min(minY, Number(d.y) || 0);
        maxY = Math.max(maxY, Number(d.y) || 0);
      });

      // 1.5m outer padding around room
      const padMeters = 1.4;
      const worldW = (maxX - minX) + 2 * padMeters;
      const worldH = (maxY - minY) + 2 * padMeters;

      const padPx = 45;
      const availW = Math.max(100, displayW - padPx * 2);
      const availH = Math.max(100, displayH - padPx * 2);

      // CRITICAL: STRICT EQUAL-ASPECT SCALE (scaleX == scaleY). ZERO STRETCHING!
      const scale = Math.min(availW / (worldW > 0 ? worldW : 1), availH / (worldH > 0 ? worldH : 1));

      const offsetX = (displayW - worldW * scale) / 2 - (minX - padMeters) * scale;
      const offsetY = (displayH - worldH * scale) / 2 - (minY - padMeters) * scale;

      function toScreen(x, y) {
        return {
          sx: offsetX + x * scale,
          sy: displayH - (offsetY + y * scale) // Invert Y so (0,0) is bottom-left
        };
      }

      // 3. Draw 1-Meter Grid Lines
      const startX = Math.floor(minX - padMeters);
      const endX = Math.ceil(maxX + padMeters);
      const startY = Math.floor(minY - padMeters);
      const endY = Math.ceil(maxY + padMeters);

      ctx.lineWidth = 1.0;
      for (let x = startX; x <= endX; x++) {
        const p1 = toScreen(x, minY - padMeters);
        const p2 = toScreen(x, maxY + padMeters);
        ctx.strokeStyle = (x === 0 || x === 6) ? '#2E2E2E' : '#1C1C1C';
        ctx.beginPath();
        ctx.moveTo(p1.sx, p1.sy);
        ctx.lineTo(p2.sx, p2.sy);
        ctx.stroke();

        // Meter labels along bottom
        ctx.fillStyle = '#6B7280';
        ctx.font = '9px monospace';
        ctx.textAlign = 'center';
        ctx.fillText(`${x}m`, p1.sx, Math.min(displayH - 10, p1.sy - 6));
      }

      for (let y = startY; y <= endY; y++) {
        const p1 = toScreen(minX - padMeters, y);
        const p2 = toScreen(maxX + padMeters, y);
        ctx.strokeStyle = (y === 0 || y === 5) ? '#2E2E2E' : '#1C1C1C';
        ctx.beginPath();
        ctx.moveTo(p1.sx, p1.sy);
        ctx.lineTo(p2.sx, p2.sy);
        ctx.stroke();

        // Meter labels along left
        ctx.fillStyle = '#6B7280';
        ctx.font = '9px monospace';
        ctx.textAlign = 'left';
        ctx.fillText(`${y}m`, Math.max(10, p1.sx + 6), p1.sy - 3);
      }

      // 4. Draw Room Blueprint Boundary (Room A: 0,0 to 6.0, 5.0)
      const rTopLeft = toScreen(0.0, 5.0);
      const rBottomRight = toScreen(6.0, 0.0);
      const rWidth = rBottomRight.sx - rTopLeft.sx;
      const rHeight = rBottomRight.sy - rTopLeft.sy;

      // Subtle filled blueprint floor
      ctx.fillStyle = 'rgba(27, 27, 27, 0.55)';
      ctx.fillRect(rTopLeft.sx, rTopLeft.sy, rWidth, rHeight);
      ctx.strokeStyle = '#383838';
      ctx.lineWidth = 1.5;
      ctx.strokeRect(rTopLeft.sx, rTopLeft.sy, rWidth, rHeight);

      // Blueprint Center Watermark
      ctx.fillStyle = 'rgba(46, 46, 46, 0.8)';
      ctx.font = 'bold 22px -apple-system, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('ROOM A • 6.0m × 5.0m', rTopLeft.sx + rWidth / 2, rTopLeft.sy + rHeight / 2);

      // 5. Draw Radial Dashed Distance Lines from Tracked Devices to Anchors
      currentDevices.forEach(d => {
        const devPos = toScreen(Number(d.x) || 0, Number(d.y) || 0);
        currentAnchors.forEach(a => {
          const ancPos = toScreen(Number(a.x) || 0, Number(a.y) || 0);
          const dist = Math.hypot((Number(d.x) || 0) - (Number(a.x) || 0), (Number(d.y) || 0) - (Number(a.y) || 0));

          ctx.save();
          ctx.setLineDash([3, 4]);
          ctx.strokeStyle = 'rgba(255, 138, 61, 0.3)';
          ctx.lineWidth = 1.0;
          ctx.beginPath();
          ctx.moveTo(devPos.sx, devPos.sy);
          ctx.lineTo(ancPos.sx, ancPos.sy);
          ctx.stroke();
          ctx.restore();

          // Distance Pill Tag
          if (dist > 0) {
            const midX = (devPos.sx + ancPos.sx) / 2;
            const midY = (devPos.sy + ancPos.sy) / 2;
            ctx.fillStyle = '#1B1B1B';
            ctx.fillRect(midX - 16, midY - 9, 32, 18);
            ctx.strokeStyle = '#2E2E2E';
            ctx.lineWidth = 1;
            ctx.strokeRect(midX - 16, midY - 9, 32, 18);

            ctx.fillStyle = '#FF8A3D';
            ctx.font = 'bold 10px monospace';
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.fillText(`${dist.toFixed(1)}m`, midX, midY);
          }
        });
      });

      // 6. Draw Anchor Nodes (Warm Amber #F2C14E)
      currentAnchors.forEach(a => {
        const pt = toScreen(Number(a.x) || 0, Number(a.y) || 0);

        // Halo
        ctx.fillStyle = 'rgba(242, 193, 78, 0.16)';
        ctx.beginPath();
        ctx.arc(pt.sx, pt.sy, 14, 0, Math.PI * 2);
        ctx.fill();

        // Core Dot
        ctx.fillStyle = '#F2C14E';
        ctx.beginPath();
        ctx.arc(pt.sx, pt.sy, 6, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#111111';
        ctx.lineWidth = 2.0;
        ctx.stroke();

        // Anchor Label Tag
        ctx.textAlign = 'center';
        ctx.textBaseline = 'top';
        const title = a.friendlyName || a.anchorId;
        const coords = `(${Number(a.x).toFixed(1)}m, ${Number(a.y).toFixed(1)}m)`;

        ctx.font = 'bold 11px -apple-system, sans-serif';
        const tagW = Math.max(ctx.measureText(title).width, ctx.measureText(coords).width) + 16;

        ctx.fillStyle = 'rgba(27, 27, 27, 0.95)';
        ctx.fillRect(pt.sx - tagW / 2, pt.sy + 10, tagW, 28);
        ctx.strokeStyle = '#2E2E2E';
        ctx.lineWidth = 1.0;
        ctx.strokeRect(pt.sx - tagW / 2, pt.sy + 10, tagW, 28);

        ctx.fillStyle = '#F5F5F5';
        ctx.fillText(title, pt.sx, pt.sy + 12);
        ctx.font = '9px monospace';
        ctx.fillStyle = '#F2C14E';
        ctx.fillText(coords, pt.sx, pt.sy + 24);
      });

      // 7. Draw Tracked Client Device with Animated Radar Pulse (Vibrant Orange #FF8A3D)
      const now = performance.now();
      const pulsePhase = (now % 2200) / 2200; // 0.0 to 1.0

      currentDevices.forEach(d => {
        const pt = toScreen(Number(d.x) || 0, Number(d.y) || 0);

        // Animated Pulse Waves
        for (let r = 0; r < 2; r++) {
          const phase = (pulsePhase + r * 0.5) % 1.0;
          const rRadius = 12 + phase * 34;
          const rOpacity = Math.max(0, (1.0 - phase) * 0.7);
          ctx.strokeStyle = `rgba(255, 138, 61, ${rOpacity})`;
          ctx.lineWidth = 2.0;
          ctx.beginPath();
          ctx.arc(pt.sx, pt.sy, rRadius, 0, Math.PI * 2);
          ctx.stroke();
        }

        // Location Pin Core Dot
        ctx.fillStyle = 'rgba(255, 138, 61, 0.3)';
        ctx.beginPath();
        ctx.arc(pt.sx, pt.sy, 12, 0, Math.PI * 2);
        ctx.fill();

        ctx.fillStyle = '#FF8A3D';
        ctx.beginPath();
        ctx.arc(pt.sx, pt.sy, 7.5, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = '#FFFFFF';
        ctx.lineWidth = 2.0;
        ctx.stroke();

        // Floating Device Status Tag
        ctx.textAlign = 'center';
        ctx.textBaseline = 'bottom';
        const title = `${d.deviceId} [${d.roomName}]`;
        const coords = `Pos: (${Number(d.x).toFixed(2)}m, ${Number(d.y).toFixed(2)}m)`;

        ctx.font = 'bold 11px -apple-system, sans-serif';
        const tagW = Math.max(ctx.measureText(title).width, ctx.measureText(coords).width) + 18;

        ctx.fillStyle = 'rgba(27, 27, 27, 0.95)';
        ctx.fillRect(pt.sx - tagW / 2, pt.sy - 42, tagW, 30);
        ctx.strokeStyle = '#FF8A3D';
        ctx.lineWidth = 1.0;
        ctx.strokeRect(pt.sx - tagW / 2, pt.sy - 42, tagW, 30);

        ctx.fillStyle = '#FF8A3D';
        ctx.fillText(title, pt.sx, pt.sy - 27);
        ctx.font = '10px monospace';
        ctx.fillStyle = '#F5F5F5';
        ctx.fillText(coords, pt.sx, pt.sy - 15);
      });

      ctx.restore();
      requestAnimationFrame(renderFrame);
    }

    // Start Animation & Polling Loops
    setInterval(updateDashboard, 1000);
    updateDashboard();
    requestAnimationFrame(renderFrame);
  </script>
</body>
</html>
"""

class CentralServerHandler(BaseHTTPRequestHandler):
    def _send_cors_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Connection', 'close')

    def _send_json(self, status_code, data):
        response_bytes = json.dumps(data, indent=2).encode('utf-8')
        self.send_response(status_code)
        self._send_cors_headers()
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response_bytes)))
        self.end_headers()
        self.wfile.write(response_bytes)

    def _send_html(self, status_code, html_content):
        response_bytes = html_content.encode('utf-8')
        self.send_response(status_code)
        self._send_cors_headers()
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(response_bytes)))
        self.end_headers()
        self.wfile.write(response_bytes)

    def do_OPTIONS(self):
        self.send_response(200)
        self._send_cors_headers()
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        global active_anchor_map, registered_anchors, solved_locations
        path = self.path.split('?')[0]

        # Purge stale anchors (no heartbeat in 60s)
        cutoff = datetime.now() - timedelta(seconds=60)
        active_anchors_list = []
        for aid, a in list(registered_anchors.items()):
            try:
                if datetime.fromisoformat(a['lastSeen']) > cutoff:
                    active_anchors_list.append(a)
                else:
                    del registered_anchors[aid]
            except Exception:
                active_anchors_list.append(a)

        if path == '/' or path == '/dashboard':
            self._send_html(200, HTML_DASHBOARD)

        elif path == '/api/status':
            status = {
                'status': 'online',
                'serverIp': get_local_ip(),
                'port': PORT,
                'hasAnchorNetwork': active_anchor_map is not None,
                'anchorsCount': len(active_anchors_list),
                'anchors': active_anchors_list,
                'trackedDevicesCount': len(solved_locations),
                'devices': solved_locations,
            }
            self._send_json(200, status)

        elif path == '/api/anchor/network':
            if active_anchor_map:
                self._send_json(200, active_anchor_map)
            else:
                self._send_json(200, {'status': 'none', 'message': 'No anchor network calibrated yet'})

        elif path == '/api/location':
            query = {}
            if '?' in self.path:
                parts = self.path.split('?')[1].split('&')
                for p in parts:
                    if '=' in p:
                        k, v = p.split('=', 1)
                        query[k] = v

            device_id = query.get('deviceId')
            if not device_id or device_id not in solved_locations:
                self._send_json(404, {'error': f'Location for {device_id} not calculated yet'})
                return

            loc = dict(solved_locations[device_id])
            if active_anchor_map:
                loc['anchorMap'] = active_anchor_map
            self._send_json(200, loc)

        else:
            self._send_json(404, {'error': 'Not found'})

    def do_POST(self):
        global active_anchor_map, registered_anchors
        path = self.path.split('?')[0]

        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)
        try:
            data = json.loads(body.decode('utf-8')) if body else {}
        except Exception as e:
            self._send_json(400, {'error': f'Invalid JSON: {e}'})
            return

        if path in ['/api/anchor/heartbeat', '/api/anchor/register']:
            anchor_id = data.get('anchorId', 'ANCHOR-UNKNOWN')
            friendly_name = data.get('friendlyName', anchor_id)
            room_name = data.get('roomName', 'Room A')
            ax = float(data.get('x', data.get('anchorX', 0.0)))
            ay = float(data.get('y', data.get('anchorY', 0.0)))

            registered_anchors[anchor_id] = {
                'anchorId': anchor_id,
                'friendlyName': friendly_name,
                'roomName': room_name,
                'x': ax,
                'y': ay,
                'lastSeen': datetime.now().isoformat(),
            }
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Heartbeat from Anchor: {anchor_id} ({friendly_name}) @ ({ax}m, {ay}m) [{room_name}]")
            self._send_json(200, {'status': 'registered', 'anchorId': anchor_id})

        elif path == '/api/anchor/network':
            active_anchor_map = data
            anchor_count = len(active_anchor_map.get('anchors', []))
            print(f"[{datetime.now().strftime('%H:%M:%S')}] Saved Anchor Network geometry with {anchor_count} anchors!")
            
            # Auto-register anchors from the network
            for a in active_anchor_map.get('anchors', []):
                aid = a.get('anchorId')
                if aid:
                    registered_anchors[aid] = {
                        'anchorId': aid,
                        'friendlyName': aid,
                        'roomName': a.get('roomName', 'Room A'),
                        'x': float(a.get('x', 0.0)),
                        'y': float(a.get('y', 0.0)),
                        'lastSeen': datetime.now().isoformat(),
                    }

            self._send_json(200, {'status': 'success', 'anchorCount': anchor_count})

        elif path == '/api/anchor/report':
            target_id = data.get('targetDeviceId', 'UNKNOWN')
            anchor_id = data.get('anchorId', 'ANCHOR')
            room_name = data.get('roomName', 'Room A')
            anchor_x = float(data.get('anchorX', 0.0))
            anchor_y = float(data.get('anchorY', 0.0))
            rssi = int(data.get('rssi', -70))
            distance = float(data.get('distance', 2.0))

            # Auto-register this anchor if not yet registered
            registered_anchors[anchor_id] = {
                'anchorId': anchor_id,
                'friendlyName': anchor_id,
                'roomName': room_name,
                'x': anchor_x,
                'y': anchor_y,
                'lastSeen': datetime.now().isoformat(),
            }

            report = {
                'anchorId': anchor_id,
                'roomName': room_name,
                'anchorX': anchor_x,
                'anchorY': anchor_y,
                'targetDeviceId': target_id,
                'rssi': rssi,
                'distance': distance,
                'timestamp': datetime.now().isoformat(),
            }

            if target_id not in device_reports:
                device_reports[target_id] = []

            # Remove previous report from this anchor
            device_reports[target_id] = [r for r in device_reports[target_id] if r['anchorId'] != anchor_id]
            device_reports[target_id].append(report)

            # Purge reports older than 20 seconds
            cutoff = datetime.now() - timedelta(seconds=20)
            device_reports[target_id] = [
                r for r in device_reports[target_id]
                if datetime.fromisoformat(r['timestamp']) > cutoff
            ]

            # Solve location via Non-Linear Least Squares
            self._solve_device_location(target_id, device_reports[target_id])

            self._send_json(200, {'status': 'success', 'deviceId': target_id})

        else:
            self._send_json(404, {'error': 'Not found'})

    def _solve_device_location(self, target_id, reports):
        global active_anchor_map
        if not reports:
            return

        # 1. Majority voting for room name
        room_counts = {}
        for r in reports:
            rm = r['roomName']
            room_counts[rm] = room_counts.get(rm, 0) + 1

        resolved_room = max(room_counts, key=room_counts.get)

        # 2. Extract anchor points from calibrated network if available
        anchor_points = []
        for r in reports:
            ax = r['anchorX']
            ay = r['anchorY']
            if active_anchor_map and 'anchors' in active_anchor_map:
                for a in active_anchor_map['anchors']:
                    if a.get('anchorId') == r['anchorId']:
                        ax = float(a.get('x', ax))
                        ay = float(a.get('y', ay))
                        break
            anchor_points.append({
                'id': r['anchorId'],
                'x': ax,
                'y': ay,
                'd': max(0.2, r['distance']),
            })

        anchor_points.sort(key=lambda p: p['d'])
        nearest = anchor_points[0]

        solved_x = nearest['x']
        solved_y = nearest['y']

        if len(anchor_points) >= 3:
            # Step A: Initial weighted centroid estimate
            total_w = sum(1.0 / (p['d'] ** 2) for p in anchor_points)
            if total_w > 0:
                solved_x = sum(p['x'] / (p['d'] ** 2) for p in anchor_points) / total_w
                solved_y = sum(p['y'] / (p['d'] ** 2) for p in anchor_points) / total_w

            # Step B: Gauss-Newton Non-Linear Least Squares Optimization
            max_iter = 10
            lm_lambda = 0.01

            for _ in range(max_iter):
                a00 = lm_lambda
                a01 = 0.0
                a11 = lm_lambda
                b0 = 0.0
                b1 = 0.0

                for pt in anchor_points:
                    dx = solved_x - pt['x']
                    dy = solved_y - pt['y']
                    r = max(0.05, math.sqrt(dx * dx + dy * dy))
                    j0 = dx / r
                    j1 = dy / r
                    error = pt['d'] - r
                    w = 1.0 / max(0.3, pt['d'])

                    a00 += w * j0 * j0
                    a01 += w * j0 * j1
                    a11 += w * j1 * j1
                    b0 += w * j0 * error
                    b1 += w * j1 * error

                det = a00 * a11 - a01 * a01
                if abs(det) < 1e-7:
                    break

                step_x = (a11 * b0 - a01 * b1) / det
                step_y = (a00 * b1 - a01 * b0) / det

                step_x = max(-2.5, min(2.5, step_x))
                step_y = max(-2.5, min(2.5, step_y))

                solved_x += step_x
                solved_y += step_y

                if abs(step_x) < 0.01 and abs(step_y) < 0.01:
                    break

        elif len(anchor_points) == 2:
            a = anchor_points[0]
            b = anchor_points[1]
            tot = a['d'] + b['d']
            if tot > 0:
                solved_x = a['x'] * (b['d'] / tot) + b['x'] * (a['d'] / tot)
                solved_y = a['y'] * (b['d'] / tot) + b['y'] * (a['d'] / tot)

        confidence = min(98.0, 55.0 + len(anchor_points) * 14.0)

        loc = {
            'deviceId': target_id,
            'x': round(solved_x, 2),
            'y': round(solved_y, 2),
            'roomName': resolved_room,
            'confidence': confidence,
            'nearestAnchorId': nearest['id'],
            'nearestDistance': round(nearest['d'], 2),
            'timestamp': datetime.now().isoformat(),
            'source': 'CENTRAL_SERVER',
        }

        solved_locations[target_id] = loc
        print(f"[{datetime.now().strftime('%H:%M:%S')}] Solved {target_id} -> {resolved_room} (X={loc['x']}m, Y={loc['y']}m, Conf={loc['confidence']}%) via {len(reports)} anchors")

def run():
    ip = get_local_ip()
    server_address = ('0.0.0.0', PORT)
    httpd = ThreadingHTTPServer(server_address, CentralServerHandler)
    httpd.daemon_threads = True
    print("=" * 65)
    print("  LIVS Central Indoor Localization Server (Multi-Threaded)")
    print(f"  Web Dashboard:    http://{ip}:{PORT}/")
    print(f"  API Status:       http://{ip}:{PORT}/api/status")
    print(f"  API Location:     http://{ip}:{PORT}/api/location?deviceId=TEST-C001")
    print(f"  Anchor Network:   http://{ip}:{PORT}/api/anchor/network")
    print("=" * 65)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer shutting down.")
        httpd.server_close()

if __name__ == '__main__':
    run()
