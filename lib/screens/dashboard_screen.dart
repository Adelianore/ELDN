import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/local_database.dart';
import '../services/local_http_server.dart';
import '../services/serial_listener.dart';

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
  String? _lastRawLine;
  String? _lastSerialError;
  StreamSubscription<String>? _rawSub;
  StreamSubscription<String>? _errSub;
  final List<String> _rawHistory = [];

  @override
  void initState() {
    super.initState();
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
        _lastRawLine = line;
        _rawHistory.insert(0, line);
        if (_rawHistory.length > 10) _rawHistory.removeLast();
      });
    });
    _errSub = _serialListener.onError.listen((err) {
      if (!mounted) return;
      setState(() {
        _lastSerialError = err;
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

  Widget _buildStatusTile(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.12),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
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
        title: const Text('ELDN Local Edge Dashboard'),
        centerTitle: true,
        elevation: 0,
        backgroundColor: const Color(0xFF0b1730),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _buildStatusTile(
                      'Server HTTP',
                      _serverStatus,
                      Colors.greenAccent,
                    ),
                    const SizedBox(width: 12),
                    _buildStatusTile(
                      'Serial Port',
                      _serialStatus,
                      Colors.cyanAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0d1a31),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedPort,
                          decoration: InputDecoration(
                            labelText: 'Nama Port Serial',
                            hintText: 'Pilih port serial aktif',
                            hintStyle: const TextStyle(color: Colors.white30),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.transparent,
                          ),
                          dropdownColor: const Color(0xFF0D1321),
                          style: const TextStyle(color: Colors.white),
                          iconEnabledColor: Colors.white,
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
                              if (v != null) _portController.text = v;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF12233d),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _availablePorts =
                                  SerialPortListener.availablePorts;
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
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isCompact = constraints.maxWidth < 1200;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: isCompact ? 1 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: _buildLogsCard()),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 130,
                                  child: _buildSerialDebugCard(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: isCompact ? 2 : 2,
                            child: _buildTelemetryMapCard(),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: isCompact ? 1 : 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: 240, child: _buildNodesCard()),
                                const SizedBox(height: 14),
                                Expanded(child: _buildTelemetryChartCard()),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSerialDebugCard() {
    return Card(
      color: const Color(0xFF141C29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Debug Serial',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Last raw line: ${_lastRawLine ?? '-'}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'Recent lines:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _rawHistory.isEmpty
                  ? const Center(
                      child: Text('-', style: TextStyle(color: Colors.white38)),
                    )
                  : ListView.separated(
                      itemCount: _rawHistory.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 4),
                      itemBuilder: (context, index) => Text(
                        _rawHistory[index],
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'Last error: ${_lastSerialError ?? '-'}',
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return Card(
      color: const Color(0xFF141C29),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Status',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Live',
                    style: TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Tidak ada data status yang tersedia.',
                        style: TextStyle(color: Colors.white60),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 780),
                        child: DataTable(
                          headingRowColor: WidgetStateColor.resolveWith(
                            (states) => Colors.white12,
                          ),
                          dataRowColor: WidgetStateColor.resolveWith(
                            (states) => const Color(0xFF111827),
                          ),
                          columnSpacing: 14,
                          horizontalMargin: 8,
                          columns: const [
                            DataColumn(
                              label: Text(
                                'Node ID',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Status',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Latitude',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Longitude',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Sound',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Vibration Cnt',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Vibration Status',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Sound Status',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Timestamp',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          rows: _logs.map((row) {
                            return DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    row['node_id']?.toString() ?? '-',
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    (row['status_sys']?.toString() ?? 'unknown')
                                        .trim(),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    (row['latitude'] ?? 0).toString(),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    (row['longitude'] ?? 0).toString(),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row['suara_val']?.toString() ?? '0',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row['getaran_count']?.toString() ?? '0',
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row['vibration_status']?.toString() ?? '-',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row['sound_status']?.toString() ?? '-',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    row['timestamp']?.toString() ?? '-',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
            ),
          ],
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
              'Node Status',
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
                        final status =
                            node['status_alat']?.toString() ?? 'unknown';
                        final lastSeen = node['last_seen']?.toString() ?? '-';

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0d1a31),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                node['node_id']?.toString() ?? '-',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Status: $status',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Terakhir: $lastSeen',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                ),
                              ),
                            ],
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
    final chartLogs = _logs.take(24).toList().reversed.toList();
    if (chartLogs.isEmpty) {
      return Card(
        color: const Color(0xFF141C29),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'Belum ada data chart sensor.',
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
            Expanded(
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
            Expanded(
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
