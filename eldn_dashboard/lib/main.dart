import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OLIVIA Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF07111F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFD54F),
          secondary: Color(0xFF2E3A4D),
          surface: Color(0xFF0F172A),
          onSurface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'OLIVIA Dashboard'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final List<_NodeDevice> _nodes = const [
    _NodeDevice(id: 'KORBAN_1', label: 'KORBAN_1', location: 'Warehouse A'),
    _NodeDevice(id: 'ELYATIM', label: 'ELYATIM', location: 'Field B'),
    _NodeDevice(id: 'NODE_3', label: 'NODE_3', location: 'Garage C'),
  ];

  late String _selectedNodeId;
  final Map<String, List<double>> _sensorReadings = {};
  final Random _random = Random();
  Timer? _liveTimer;

  @override
  void initState() {
    super.initState();
    _selectedNodeId = _nodes.first.id;
    for (final node in _nodes) {
      _sensorReadings[node.id] = List.generate(
        50,
        (index) => (900 + (index % 8) * 70 + _random.nextInt(80))
            .clamp(0, 4095)
            .toDouble(),
      );
    }
    _liveTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() {
        for (final node in _nodes) {
          final values = _sensorReadings[node.id]!;
          final nextValue = (700 + _random.nextInt(3000))
              .clamp(0, 4095)
              .toDouble();
          values.add(nextValue);
          if (values.length > 50) {
            values.removeAt(0);
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  void _selectNode(String nodeId) {
    setState(() {
      _selectedNodeId = nodeId;
    });
  }

  List<double> _selectedReadings() {
    return _sensorReadings[_selectedNodeId] ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final selectedNode = _nodes.firstWhere(
      (node) => node.id == _selectedNodeId,
    );
    final readings = _selectedReadings();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: const Color(0xFF0B1220),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: _buildNodeColumn(selectedNode)),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: _buildStatusColumn(selectedNode, readings),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: _buildVisualsColumn(selectedNode, readings),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNodeColumn(_NodeDevice selectedNode) {
    return Card(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available Nodes',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFFFFD54F),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: _nodes.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final node = _nodes[index];
                  final isActive = node.id == selectedNode.id;

                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _selectNode(node.id),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF1F2937)
                            : const Color(0xFF111827),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFFFFD54F)
                              : const Color(0xFF334155),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.sensors,
                            color: isActive
                                ? const Color(0xFFFFD54F)
                                : Colors.white70,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  node.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  node.location,
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
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

  Widget _buildStatusColumn(_NodeDevice selectedNode, List<double> readings) {
    final latest = readings.isEmpty ? 0 : readings.last.round();

    return Card(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selected Node',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFFFFD54F),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              selectedNode.label,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Location: ${selectedNode.location}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            _metricTile('Last Sensor Reading', '$latest', Icons.timeline),
            const SizedBox(height: 12),
            _metricTile('Live Status', 'Online', Icons.wifi_tethering),
            const SizedBox(height: 12),
            _metricTile('Signal', 'Strong', Icons.signal_wifi_4_bar),
          ],
        ),
      ),
    );
  }

  Widget _buildVisualsColumn(_NodeDevice selectedNode, List<double> readings) {
    final latest = readings.isEmpty ? 0 : readings.last.round();

    return Card(
      color: const Color(0xFF0F172A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sensor Suara • ${selectedNode.label}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: const Color(0xFFFFD54F),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: LineChart(
                  LineChartData(
                    minY: 0,
                    maxY: 4095,
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
                        spots: List.generate(
                          readings.length,
                          (index) => FlSpot(index.toDouble(), readings[index]),
                        ),
                        isCurved: true,
                        color: const Color(0xFFFFD54F),
                        barWidth: 2.5,
                        dotData: const FlDotData(show: false),
                        belowBarData: BarAreaData(
                          show: true,
                          color: const Color(
                            0xFFFFD54F,
                          ).withValues(alpha: 0.18),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.videocam,
                      color: Color(0xFFFFD54F),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ESP32-CAM Feed',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '$latest • ${selectedNode.label} live preview',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricTile(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFFD54F)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeDevice {
  const _NodeDevice({
    required this.id,
    required this.label,
    required this.location,
  });

  final String id;
  final String label;
  final String location;
}
