import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/local_database.dart';
import '../services/local_http_server.dart';
import '../services/network_info.dart';
import '../services/serial_listener.dart';
import 'posko_client_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.database});

  final LocalDatabase database;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _portController = TextEditingController();
  final _serialListener = SerialPortListener(LocalDatabase.instance);
  final _httpServer = LocalHttpServer(LocalDatabase.instance);
  List<String> _availablePorts = [];
  String? _selectedPort;
  final List<Map<String, dynamic>> _logs = [];
  final List<Map<String, dynamic>> _nodes = [];
  String? selectedNodeId;
  String _localIp = 'Memuat...';

  bool get _supportsSerial {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  String get _serialSupportHint => _supportsSerial
      ? 'Serial tersedia pada desktop.'
      : 'Serial hanya tersedia di desktop (Windows/Linux/macOS).';
  Timer? _refreshTimer;
  String _serverStatus = 'Memulai...';
  String _serialStatus = 'Belum terhubung';
  bool _isConnecting = false;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<String>? _errSub;
  final List<String> _rawHistory = [];

  @override
  void initState() {
    super.initState();
    _loadLocalIp();
    _startServer();
    if (_supportsSerial) {
      _availablePorts = SerialPortListener.availablePorts;
      if (_availablePorts.isNotEmpty) {
        _selectedPort = _availablePorts.first;
        _portController.text = _selectedPort!;
      }
    } else {
      _serialStatus = _serialSupportHint;
    }
    _refreshData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => _refreshData(),
    );
    _serialListener.onNewLog.listen((_) {
      _refreshData();
    });
    _rawSub = _serialListener.onRawLine.listen((line) {
      if (!mounted) return;
      // handle special control messages from listener
      if (line.startsWith('PORT_OPENED:')) {
        final port = line.split(':').length > 1 ? line.split(':')[1] : '';
        if (mounted) {
          setState(() {
            _serialStatus = 'Terhubung ke $port';
            _isConnecting = false;
          });
        }
        return;
      }

      setState(() {
        _rawHistory.insert(0, line);
        if (_rawHistory.length > 10) _rawHistory.removeLast();
      });
    });
    _errSub = _serialListener.onError.listen((err) {
      if (!mounted) return;
      setState(() {
        // Serial error state not tracked in UI.
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _serialListener.stop();
    _rawSub?.cancel();
    _errSub?.cancel();
    _serialListener.dispose();
    _httpServer.stop();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalIp() async {
    final ip = await NetworkInfo.getLocalIpv4Address();
    if (!mounted) return;
    setState(() {
      _localIp = ip ?? 'Tidak terdeteksi';
    });
  }

  Future<void> _startServer() async {
    try {
      await _httpServer.start();
      if (!mounted) return;
      setState(() {
        _serverStatus = 'Berjalan di 0.0.0.0:8080';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverStatus = 'Gagal memulai server: $error';
      });
    }
  }

  Future<void> _refreshData() async {
    final logs = await widget.database.queryLogs(limit: 100);
    final nodes = await widget.database.queryNodes();
    if (!mounted) return;
    setState(() {
      _logs
        ..clear()
        ..addAll(logs);
      _nodes
        ..clear()
        ..addAll(nodes);
      if (selectedNodeId == null && _nodes.isNotEmpty) {
        selectedNodeId = _nodes.first['node_id']?.toString();
      }
    });
  }

  Future<void> _connectSerial() async {
    final portName = (_selectedPort ?? _portController.text).trim();
    if (portName.isEmpty) {
      setState(() {
        _serialStatus = 'Masukkan nama port serial terlebih dahulu.';
      });
      return;
    }

    // immediate feedback
    if (mounted) {
      setState(() {
        _serialStatus = 'Mencoba menghubungkan ke $portName...';
        _rawHistory.insert(0, 'Attempting connect -> $portName');
        if (_rawHistory.length > 10) _rawHistory.removeLast();
      });
    }

    try {
      if (!_supportsSerial) {
        if (mounted) {
          setState(() {
            _serialStatus = _serialSupportHint;
            _isConnecting = false;
            _rawHistory.insert(0, 'Serial tidak didukung pada perangkat ini.');
            if (_rawHistory.length > 10) _rawHistory.removeLast();
          });
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_serialSupportHint)));
        }
        return;
      }
      if (mounted) {
        setState(() {
          _isConnecting = true;
        });
      }
      await _serialListener.start(portName: portName);
      if (!mounted) return;
    } catch (error) {
      if (mounted) {
        setState(() {
          _serialStatus = 'Gagal terhubung: $error';
          _isConnecting = false;
          _rawHistory.insert(0, 'Connect failed: $error');
          if (_rawHistory.length > 10) _rawHistory.removeLast();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal terhubung ke $portName: $error')),
        );
      }
    }
  }

  Future<void> _disconnectSerial() async {
    await _serialListener.stop();
    if (!mounted) return;
    setState(() {
      _serialStatus = 'Terputus';
    });
  }

  List<Map<String, dynamic>> _logsForSelectedNode() {
    if (selectedNodeId == null) {
      return _logs;
    }
    return _logs
        .where((log) => log['node_id']?.toString() == selectedNodeId)
        .toList();
  }

  Widget _buildCompactStatusBadge(String label, String value, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 100, maxWidth: 260),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBadgesInline() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: _buildCompactStatusBadge(
            'IP',
            _localIp == 'Tidak terdeteksi' ? '-' : _localIp,
            Colors.blueAccent,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: _buildCompactStatusBadge(
            'Server',
            _serverStatus,
            Colors.greenAccent,
          ),
        ),
        _buildCompactStatusBadge('Serial', _serialStatus, Colors.cyanAccent),
      ],
    );
  }

  Widget _buildSerialControlCard(bool isWide) {
    return Card(
      color: const Color(0xFF101725),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: isWide
            ? Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedPort,
                      decoration: InputDecoration(
                        labelText: 'Port Serial',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF0D1321),
                      ),
                      dropdownColor: const Color(0xFF0D1321),
                      style: const TextStyle(color: Colors.white),
                      items: _availablePorts.isEmpty
                          ? [
                              const DropdownMenuItem(
                                value: null,
                                child: Text(
                                  'Tidak ada port tersedia',
                                  style: TextStyle(color: Colors.white60),
                                ),
                              ),
                            ]
                          : _availablePorts
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(
                                      p,
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedPort = v;
                          if (v != null) {
                            _portController.text = v;
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _availablePorts = SerialPortListener.availablePorts;
                        if (_availablePorts.isNotEmpty) {
                          _selectedPort = _availablePorts.first;
                          _portController.text = _selectedPort!;
                        } else {
                          _selectedPort = null;
                          _portController.clear();
                        }
                      });
                    },
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF12233d),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isConnecting
                        ? null
                        : (_serialListener.isRunning
                              ? _disconnectSerial
                              : _connectSerial),
                    icon: Icon(
                      _serialListener.isRunning
                          ? Icons.close_rounded
                          : Icons.link_rounded,
                      color: Colors.white,
                    ),
                    label: Text(
                      _serialListener.isRunning ? 'Putuskan' : 'Hubungkan',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFef4444),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 16,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selectedPort,
                    decoration: InputDecoration(
                      labelText: 'Port Serial',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0D1321),
                    ),
                    dropdownColor: const Color(0xFF0D1321),
                    style: const TextStyle(color: Colors.white),
                    items: _availablePorts.isEmpty
                        ? [
                            const DropdownMenuItem(
                              value: null,
                              child: Text(
                                'Tidak ada port tersedia',
                                style: TextStyle(color: Colors.white60),
                              ),
                            ),
                          ]
                        : _availablePorts
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p,
                                  child: Text(
                                    p,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                              )
                              .toList(),
                    onChanged: (v) {
                      setState(() {
                        _selectedPort = v;
                        if (v != null) {
                          _portController.text = v;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            _availablePorts = SerialPortListener.availablePorts;
                            if (_availablePorts.isNotEmpty) {
                              _selectedPort = _availablePorts.first;
                              _portController.text = _selectedPort!;
                            } else {
                              _selectedPort = null;
                              _portController.clear();
                            }
                          });
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF12233d),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isConnecting
                              ? null
                              : (_serialListener.isRunning
                                    ? _disconnectSerial
                                    : _connectSerial),
                          icon: Icon(
                            _serialListener.isRunning
                                ? Icons.close_rounded
                                : Icons.link_rounded,
                            color: Colors.white,
                          ),
                          label: Text(
                            _serialListener.isRunning
                                ? 'Putuskan'
                                : 'Hubungkan',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFef4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07101d),
      appBar: AppBar(
        toolbarHeight: 118,
        backgroundColor: const Color(0xFF0b1730),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
        title: Row(
          children: [
            // Left inline badges
            _buildHeaderBadgesInline(),
            Expanded(child: Center(child: const Text('VITALIS DASHBOARD'))),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pushNamed(PoskoClientScreen.routeName);
            },
            child: const Text(
              'Mobile Client',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF07101d), Color(0xFF09182c)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // header moved into AppBar.bottom
                    _buildSerialControlCard(isWide),
                    const SizedBox(height: 18),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SizedBox(
                              height: 760,
                              child: _buildTelemetryChartCard(),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: SizedBox(
                              height: 760,
                              child: _buildTelemetryMapCard(),
                            ),
                          ),
                          SizedBox(
                            width: 300,
                            child: SizedBox(
                              height: 760,
                              child: _buildNodesCard(),
                            ),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          SizedBox(
                            height: 320,
                            child: _buildTelemetryChartCard(),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 360,
                            child: _buildTelemetryMapCard(),
                          ),
                          const SizedBox(height: 14),
                          SizedBox(height: 320, child: _buildNodesCard()),
                        ],
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNodesCard() {
    return Card(
      color: const Color(0xFF141C29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daftar Node',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _nodes.isEmpty
                  ? const Center(
                      child: Text(
                        'Tidak ada node yang terdaftar.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _nodes.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final node = _nodes[index];
                        final nodeId = node['node_id']?.toString() ?? '-';
                        final isSelected = nodeId == selectedNodeId;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              selectedNodeId = nodeId;
                            });
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF1f2c47)
                                  : const Color(0xFF0d1a31),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blueAccent
                                    : Colors.white10,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        nodeId,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Terakhir: ${node['last_seen']?.toString() ?? '-'}',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blueAccent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'Aktif',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryChartCard() {
    final chartLogs = _logsForSelectedNode()
        .take(24)
        .toList()
        .reversed
        .toList();
    if (chartLogs.isEmpty) {
      return Card(
        color: const Color(0xFF141C29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Belum ada data chart sensor untuk node terpilih.',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        ),
      );
    }

    final soundSpots = <FlSpot>[];
    final vibrationSpots = <FlSpot>[];

    for (var i = 0; i < chartLogs.length; i++) {
      final row = chartLogs[i];
      soundSpots.add(
        FlSpot(i.toDouble(), (row['suara_val'] as num?)?.toDouble() ?? 0),
      );
      vibrationSpots.add(
        FlSpot(i.toDouble(), (row['getaran_count'] as num?)?.toDouble() ?? 0),
      );
    }

    return Card(
      color: const Color(0xFF141C29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Live Sensor Fluctuation',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: const [
                _LegendChip(color: Colors.greenAccent, label: 'Sound'),
                SizedBox(width: 10),
                _LegendChip(color: Colors.amberAccent, label: 'Vibration'),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 220,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: _calculateMaxChartY(soundSpots, vibrationSpots),
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) =>
                          FlLine(color: Colors.white12, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: soundSpots,
                        isCurved: true,
                        color: Colors.greenAccent,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.greenAccent.withValues(alpha: 0.16),
                        ),
                      ),
                      LineChartBarData(
                        spots: vibrationSpots,
                        isCurved: true,
                        color: Colors.amberAccent,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: Colors.amberAccent.withValues(alpha: 0.14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  double _calculateMaxChartY(
    List<FlSpot> soundSpots,
    List<FlSpot> vibrationSpots,
  ) {
    final allY = <double>[
      ...soundSpots.map((s) => s.y),
      ...vibrationSpots.map((s) => s.y),
    ];
    if (allY.isEmpty) {
      return 10.0;
    }
    final maxValue = allY.reduce(
      (value, element) => value > element ? value : element,
    );
    final paddedMax = (maxValue * 1.2).clamp(10.0, 4095.0);
    return paddedMax < 10.0 ? 10.0 : paddedMax.toDouble();
  }

  Widget _buildTelemetryMapCard() {
    final latestLogsByNode = <String, Map<String, dynamic>>{};

    for (final log in _logs) {
      final latitude = (log['latitude'] as num?)?.toDouble();
      final longitude = (log['longitude'] as num?)?.toDouble();
      final nodeId = log['node_id']?.toString() ?? 'unknown';
      final timestampText = log['timestamp']?.toString() ?? '';
      final timestamp =
          DateTime.tryParse(timestampText) ??
          DateTime.fromMillisecondsSinceEpoch(0);

      if (selectedNodeId != null && nodeId != selectedNodeId) {
        continue;
      }

      if (latitude == null || longitude == null) {
        continue;
      }

      final existing = latestLogsByNode[nodeId];
      if (existing == null) {
        latestLogsByNode[nodeId] = log;
      } else {
        final existingTime =
            DateTime.tryParse(existing['timestamp']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        if (timestamp.isAfter(existingTime)) {
          latestLogsByNode[nodeId] = log;
        }
      }
    }

    final markers = latestLogsByNode.values.map((log) {
      final latitude = (log['latitude'] as num?)?.toDouble() ?? 0.0;
      final longitude = (log['longitude'] as num?)?.toDouble() ?? 0.0;
      final nodeId = log['node_id']?.toString() ?? 'unknown';
      return Marker(
        width: 40,
        height: 40,
        point: LatLng(latitude, longitude),
        child: Tooltip(
          message: nodeId,
          child: const Icon(Icons.location_on, color: Colors.redAccent),
        ),
      );
    }).toList();

    final firstMarker = markers.isNotEmpty
        ? markers.first.point
        : LatLng(-6.2, 106.8);

    return Card(
      color: const Color(0xFF141C29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Telemetry Map',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 280,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white10),
                ),
                clipBehavior: Clip.antiAlias,
                child: markers.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada titik telemetri GPS.',
                          style: TextStyle(color: Colors.white60),
                        ),
                      )
                    : FlutterMap(
                        options: MapOptions(
                          initialCenter: firstMarker,
                          initialZoom: 10,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.olivia',
                          ),
                          MarkerLayer(markers: markers),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
