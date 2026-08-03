import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'local_database.dart';

class LocalHttpServer {
  LocalHttpServer(this.database);

  final LocalDatabase database;
  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> start({String address = '0.0.0.0', int port = 8080}) async {
    final router = Router();

    router.get('/api/mobile/nodes', (Request request) async {
      final nodes = await database.queryNodes();
      return Response.ok(jsonEncode({'nodes': nodes}), headers: _jsonHeaders);
    });

    router.get('/api/mobile/logs', (Request request) async {
      final logs = await database.queryLogs(limit: 200);
      return Response.ok(jsonEncode({'logs': logs}), headers: _jsonHeaders);
    });

    router.get('/api/mobile/logs/latest', (Request request) async {
      final logs = await database.queryLogs(limit: 1);
      return Response.ok(jsonEncode({'latest': logs}), headers: _jsonHeaders);
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
