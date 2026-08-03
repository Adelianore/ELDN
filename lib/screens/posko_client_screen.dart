import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../services/posko_api_service.dart';

class PoskoClientScreen extends StatefulWidget {
  static const String routeName = '/posko-client';

  const PoskoClientScreen({super.key});

  @override
  State<PoskoClientScreen> createState() => _PoskoClientScreenState();
}

class _PoskoClientScreenState extends State<PoskoClientScreen> {
  final TextEditingController _ipController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;
  String? _baseUrl;
  Map<String, dynamic>? _nodeData;
  Map<String, dynamic>? _chartData;
  Uint8List? _cameraImageBytes;

  Future<void> _connect() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _showError('Masukkan IP Posko terlebih dahulu.');
      return;
    }

    final baseUrl = 'http://$ip:8080';
    final api = PoskoApiService(baseUrl: baseUrl);

    setState(() {
      _isLoading = true;
      _errorText = null;
      _baseUrl = baseUrl;
      _nodeData = null;
      _chartData = null;
      _cameraImageBytes = null;
    });

    try {
      final nodeResponse = await api.fetchNodeStatus();
      final chartResponse = await api.fetchChartData();
      final imageBytes = await api.fetchCameraImageBytes();

      if (!mounted) return;
      setState(() {
        _nodeData = nodeResponse;
        _chartData = chartResponse;
        _cameraImageBytes = imageBytes;
      });
      _showMessage('Terhubung ke Posko: $baseUrl');
    } catch (error) {
      _showError(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorText = message;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildInfoCard(String label, String value, {Color? color}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 12, bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color ?? const Color(0xFF10223c),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF10223c),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Koneksi Posko Bencana',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Masukkan IP perangkat posko dan sambungkan untuk melihat status dan telemetri.',
            style: TextStyle(color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ipController,
            decoration: InputDecoration(
              labelText: 'IP Posko',
              hintText: '192.168.43.1',
              prefixIcon: const Icon(Icons.wifi, color: Colors.white70),
              filled: true,
              fillColor: const Color(0xFF0f1b33),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _isLoading ? null : _connect,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1f74ff),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(_isLoading ? 'Menghubungkan...' : 'Hubungkan'),
                ),
              ),
              if (_baseUrl != null) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _isLoading ? null : _connect,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Ulangi',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
          if (_baseUrl != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  color: Colors.greenAccent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Terhubung ke $_baseUrl',
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                ),
              ],
            ),
          ],
          if (_errorText != null) ...[
            const SizedBox(height: 12),
            Text(_errorText!, style: const TextStyle(color: Colors.redAccent)),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF10223c),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoCard(
          'IP Lokal Posko',
          _baseUrl ?? 'Belum terhubung',
          color: _baseUrl != null
              ? const Color(0xFF122e4d)
              : const Color(0xFF1a2130),
        ),
        _buildInfoCard(
          'Status Server',
          _baseUrl != null ? 'Terhubung' : 'Tidak terhubung',
          color: _baseUrl != null
              ? const Color(0xFF143b2e)
              : const Color(0xFF1a2130),
        ),
      ],
    );
  }

  Widget _buildNodeStatus() {
    if (_nodeData == null) {
      return _buildSectionCard(
        title: 'Status Node',
        child: const Text(
          'Tidak ada data status node. Sambungkan ke posko untuk menampilkan.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final nodes = (_nodeData?['nodes'] as List<dynamic>? ?? []);
    if (nodes.isEmpty) {
      return _buildSectionCard(
        title: 'Status Node',
        child: const Text(
          'Tidak ada node terdeteksi.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Status Node',
      child: Column(
        children: nodes.map((node) {
          final row = node as Map<String, dynamic>;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0f1b33),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['node_id']?.toString() ?? '-',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${row['status_alat'] ?? '-'} • ${row['last_seen'] ?? '-'}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChartSection() {
    if (_chartData == null) {
      return _buildSectionCard(
        title: 'Chart Telemetri',
        child: const Text(
          'Data chart belum tersedia. Sambungkan ke posko untuk melihat data.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final soundSeries = List<Map<String, dynamic>>.from(
      _chartData?['sound_series'] as List<dynamic>? ?? [],
    );
    final vibrationSeries = List<Map<String, dynamic>>.from(
      _chartData?['vibration_series'] as List<dynamic>? ?? [],
    );

    return _buildSectionCard(
      title: 'Chart Telemetri',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Suara', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          ...soundSeries.take(4).map((point) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${point['timestamp']}: ${point['value']}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }),
          const SizedBox(height: 12),
          const Text('Getaran', style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 10),
          ...vibrationSeries.take(4).map((point) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${point['timestamp']}: ${point['value']}',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_cameraImageBytes == null) {
      return _buildSectionCard(
        title: 'Preview Kamera',
        child: const Text(
          'Tidak ada gambar kamera tersedia.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Preview Kamera',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          _cameraImageBytes!,
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06111f),
      appBar: AppBar(
        title: const Text('ELDN Mobile Client'),
        backgroundColor: const Color(0xFF081322),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF07101d), Color(0xFF06111f)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(),
                _buildSummaryCards(),
                const SizedBox(height: 10),
                _buildNodeStatus(),
                _buildChartSection(),
                _buildCameraPreview(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
