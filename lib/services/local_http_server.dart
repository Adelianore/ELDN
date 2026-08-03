import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'local_database.dart';

class LocalHttpServer {
  LocalHttpServer(this.database);

  final LocalDatabase database;
  HttpServer? _server;
  Uint8List? _latestCameraImage;

  bool get isRunning => _server != null;

  Future<void> start({String address = '0.0.0.0', int port = 8080}) async {
    final router = Router();

    router.get('/api/mobile/nodes', (Request request) async {
      final nodes = await database.queryNodes();
      return Response.ok(jsonEncode({'nodes': nodes}), headers: _jsonHeaders);
    });

    router.get('/api/mobile/chart-data', (Request request) async {
      final logs = await database.queryLogs(limit: 200);
      final soundSeries = <Map<String, Object>>[];
      final vibrationSeries = <Map<String, Object>>[];

      for (final log in logs.reversed) {
        final timestamp = log['timestamp']?.toString() ?? '';
        soundSeries.add({
          'timestamp': timestamp,
          'value': log['suara_val'] ?? 0,
        });
        vibrationSeries.add({
          'timestamp': timestamp,
          'value': log['getaran_count'] ?? 0,
        });
      }

      return Response.ok(
        jsonEncode({
          'sound_series': soundSeries,
          'vibration_series': vibrationSeries,
        }),
        headers: _jsonHeaders,
      );
    });

    router.get('/api/mobile/camera/latest', (Request request) async {
      if (_latestCameraImage == null) {
        return Response.notFound(
          jsonEncode({'error': 'No latest camera image available'}),
          headers: _jsonHeaders,
        );
      }

      final format = request.url.queryParameters['format'];
      if (format == 'base64') {
        return Response.ok(
          jsonEncode({'imageBase64': base64Encode(_latestCameraImage!)}),
          headers: _jsonHeaders,
        );
      }

      return Response.ok(
        _latestCameraImage!,
        headers: {'content-type': 'image/jpeg'},
      );
    });

    router.post('/api/mobile/camera/latest', (Request request) async {
      final contentType = request.headers['content-type'] ?? '';
      if (contentType.contains('application/json')) {
        final payload =
            jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final base64Image = payload['imageBase64']?.toString();
        if (base64Image == null || base64Image.isEmpty) {
          return Response(
            400,
            body: jsonEncode({'error': 'imageBase64 is required'}),
            headers: _jsonHeaders,
          );
        }
        _latestCameraImage = base64Decode(base64Image);
        return Response.ok(
          jsonEncode({'success': true}),
          headers: _jsonHeaders,
        );
      }

      final bytes = await request.read().expand((chunk) => chunk).toList();
      if (bytes.isEmpty) {
        return Response(
          400,
          body: jsonEncode({'error': 'Image bytes are required'}),
          headers: _jsonHeaders,
        );
      }
      _latestCameraImage = Uint8List.fromList(bytes);
      return Response.ok(jsonEncode({'success': true}), headers: _jsonHeaders);
    });

    final handler = Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_jsonResponseMiddleware())
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, address, port);
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Middleware _jsonResponseMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        final response = await innerHandler(request);
        return response.change(headers: _jsonHeaders);
      };
    };
  }
}

const Map<String, String> _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
};
