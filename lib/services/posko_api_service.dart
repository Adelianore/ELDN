import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class PoskoApiService {
  final String baseUrl;

  PoskoApiService({required this.baseUrl});

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<Map<String, dynamic>> fetchNodeStatus() async {
    final response = await http.get(_uri('/api/mobile/nodes'));
    if (response.statusCode != 200) {
      throw Exception('Gagal mengambil status node: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> fetchChartData() async {
    final response = await http.get(_uri('/api/mobile/chart-data'));
    if (response.statusCode != 200) {
      throw Exception('Gagal mengambil data chart: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Uint8List?> fetchCameraImageBytes() async {
    final response = await http.get(_uri('/api/mobile/camera/latest'));
    if (response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw Exception('Gagal mengambil gambar kamera: ${response.statusCode}');
    }
    return response.bodyBytes;
  }
}
