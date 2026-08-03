import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'local_database.dart';

class SerialPortListener {
  SerialPortListener(this.database);

  static const int _expectedFieldCount = 8;

  final LocalDatabase database;
  final StreamController<Map<String, dynamic>> _onLogController =
      StreamController.broadcast();
  final StreamController<String> _onRawController =
      StreamController.broadcast();
  final StreamController<String> _onErrorController =
      StreamController.broadcast();

  SerialPort? _port;
  Timer? _pollTimer;
  final StringBuffer _buffer = StringBuffer();

  Stream<Map<String, dynamic>> get onNewLog => _onLogController.stream;
  Stream<String> get onRawLine => _onRawController.stream;
  Stream<String> get onError => _onErrorController.stream;

  bool get isRunning => _pollTimer != null && _port != null;

  static List<String> get availablePorts => SerialPort.availablePorts;
  static const int defaultBaudRate = 115200;

  Future<void> start({
    required String portName,
    int baudRate = defaultBaudRate,
  }) async {
    stop();

    // Emit available ports for debugging
    try {
      final ports = SerialPort.availablePorts;
      _onRawController.add('PORTS:${ports.join(',')}');
    } catch (e) {
      _onErrorController.add('Failed to list ports: $e');
    }

    // Validate that the requested port exists
    if (!SerialPort.availablePorts.contains(portName)) {
      final msg = 'Serial port not found: $portName';
      _onErrorController.add(msg);
      throw StateError(msg);
    }

    _onRawController.add('OPENING:$portName');
    _port = SerialPort(portName);
    final opened = _port!.openReadWrite();
    if (!opened) {
      final msg = 'Unable to open serial port: $portName';
      _onErrorController.add(msg);
      throw StateError(msg);
    }
    _onRawController.add('OPEN_OK:$portName');

    _port!.config.baudRate = baudRate;
    _port!.config.bits = 8;
    _port!.config.parity = SerialPortParity.none;
    _port!.config.stopBits = 1;
    _port!.config.rts = 0;

    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _pollSerialPort();
    });

    // notify that port was opened
    _onRawController.add('PORT_OPENED:$portName');
  }

  Future<void> stop() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _port?.close();
    _port = null;
    _buffer.clear();
  }

  void _pollSerialPort() {
    if (_port == null) {
      return;
    }

    try {
      final available = _port!.bytesAvailable;
      if (available <= 0) {
        return;
      }

      final chunk = _port!.read(available);
      if (chunk.isEmpty) {
        return;
      }

      _handleIncomingData(chunk);
    } catch (error, stackTrace) {
      final errorText = error.toString().toLowerCase();
      if (errorText.contains('operation completed successfully')) {
        debugPrint('Ignoring benign Windows serial-read startup error.');
        return;
      }

      final msg = 'Serial read error: $error';
      debugPrint(msg);
      debugPrint('$stackTrace');
      _onErrorController.add(msg);
    }
  }

  void _handleIncomingData(Uint8List data) {
    try {
      final decoded = utf8.decode(data, allowMalformed: true);
      _buffer.write(decoded);
    } catch (e) {
      debugPrint('Failed to decode serial data chunk: $e');
      return;
    }

    final rawText = _buffer.toString();
    final lines = rawText.split(RegExp(r'[\r\n]+'));

    if (lines.isEmpty) {
      return;
    }

    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) {
        _processLine(line);
      }
    }

    _buffer.clear();
    if (rawText.endsWith('\n') || rawText.endsWith('\r')) {
      final lastLine = lines.last.trim();
      if (lastLine.isNotEmpty) {
        _processLine(lastLine);
      }
    } else {
      _buffer.write(lines.last);
    }
  }

  static String normalizeStatusForUi(String rawStatus) {
    final normalized = rawStatus.trim().toLowerCase();
    if (normalized == 'standby') {
      return 'Safe / Normal / Standby';
    }
    if (normalized == 'mendeteksi') {
      return 'Alert / Danger';
    }
    return rawStatus.trim().isEmpty ? 'unknown' : rawStatus.trim();
  }

  static Map<String, dynamic>? parseSensorLine(String line) {
    final trimmedLine = line.trim();
    if (trimmedLine.isEmpty) {
      return null;
    }

    debugPrint('RAW SERIAL: $trimmedLine');

    var cleaned = trimmedLine;
    final arrowIndex = cleaned.indexOf('->');
    if (arrowIndex != -1) {
      cleaned = cleaned.substring(arrowIndex + 2).trim();
    }

    if (cleaned.isEmpty || cleaned.startsWith('SYSTEM:')) {
      debugPrint('PACKET REJECTED: SYSTEM packet ignored -> $trimmedLine');
      return null;
    }

    final csvParts = cleaned.split(',');
    if (csvParts.length >= _expectedFieldCount) {
      final id = csvParts[0].trim();
      final status = csvParts[1].trim();
      final lat = double.tryParse(csvParts[2].trim()) ?? 0.0;
      final lng = double.tryParse(csvParts[3].trim()) ?? 0.0;
      final soundValue = int.tryParse(csvParts[4].trim()) ?? 0;
      final vibrationCount = int.tryParse(csvParts[5].trim()) ?? 0;
      final vibrationStatus = csvParts[6].trim();
      final soundStatus = csvParts[7].trim();

      if (id.isEmpty) {
        debugPrint('PACKET REJECTED: missing node id -> $trimmedLine');
        return null;
      }

      debugPrint('PARSED PACKET: id=$id status=$status lat=$lat lng=$lng');

      return <String, dynamic>{
        'node_id': id,
        'status_sys': status,
        'latitude': lat,
        'longitude': lng,
        'sound_value': soundValue,
        'vibration_count': vibrationCount,
        'vibration_status': vibrationStatus,
        'sound_status': soundStatus,
      };
    }

    debugPrint('PACKET REJECTED: unsupported payload -> $trimmedLine');

    final semicolonParts = cleaned.split(';');
    if (semicolonParts.length >= _expectedFieldCount) {
      final values = <String, String>{};
      for (final part in semicolonParts) {
        final separatorIndex = part.indexOf('=');
        if (separatorIndex == -1) {
          continue;
        }
        final key = part.substring(0, separatorIndex).trim().toLowerCase();
        final value = part.substring(separatorIndex + 1).trim();
        values[key] = value;
      }

      final nodeId = values['node_id'] ?? values['node'] ?? values['id'];
      final statusSys = values['status'] ?? values['status_sys'] ?? '';
      final latitude =
          double.tryParse(values['lat'] ?? values['latitude'] ?? '') ?? 0.0;
      final longitude =
          double.tryParse(values['lng'] ?? values['longitude'] ?? '') ?? 0.0;
      final soundValue =
          int.tryParse(values['sound'] ?? values['sound_value'] ?? '') ?? 0;
      final vibrationCount =
          int.tryParse(
            values['vibration'] ?? values['vibration_count'] ?? '',
          ) ??
          0;
      final vibrationStatus = values['vibration_status'] ?? '';
      final soundStatus = values['sound_status'] ?? '';

      if (nodeId == null || nodeId.isEmpty) {
        return null;
      }

      return <String, dynamic>{
        'node_id': nodeId,
        'status_sys': statusSys,
        'latitude': latitude,
        'longitude': longitude,
        'sound_value': soundValue,
        'vibration_count': vibrationCount,
        'vibration_status': vibrationStatus,
        'sound_status': soundStatus,
      };
    }

    return null;
  }

  Future<void> _processLine(String line) async {
    _onRawController.add(line);

    if (line.startsWith('SYSTEM:')) {
      return;
    }

    // Preprocess line: remove any leading timestamp and arrow (e.g. "05:12:39.026 -> ")
    final parsed = parseSensorLine(line);
    if (parsed == null) {
      final msg = 'Skipped line: unsupported format -> $line';
      debugPrint(msg);
      _onErrorController.add(msg);
      return;
    }

    final nodeId = parsed['node_id'] as String;
    final statusSys = parsed['status_sys'] as String;
    final latitude = parsed['latitude'] as double;
    final longitude = parsed['longitude'] as double;
    final soundValue = parsed['sound_value'] as int;
    final vibrationCount = parsed['vibration_count'] as int;
    final vibrationStatus = parsed['vibration_status'] as String;
    final soundStatus = parsed['sound_status'] as String;
    final timestamp = DateTime.now().toIso8601String();

    final data = <String, dynamic>{
      'node_id': nodeId,
      'latitude': latitude,
      'longitude': longitude,
      'suara_val': soundValue,
      'getaran_count': vibrationCount,
      'status_sys': statusSys,
      'vibration_status': vibrationStatus,
      'sound_status': soundStatus,
      'timestamp': timestamp,
    };

    try {
      final existingNode = await database.findNode(nodeId);
      await database.insertSensorLog(data);
      await database.upsertNodeStatus(
        nodeId: nodeId,
        statusAlat: statusSys.isEmpty
            ? 'unknown'
            : normalizeStatusForUi(statusSys),
        lastSeen: timestamp,
      );

      if (existingNode == null) {
        debugPrint('NODE CREATED: $nodeId');
      } else {
        debugPrint('NODE UPDATED: $nodeId');
      }
    } catch (e, st) {
      final msg = 'DB error when inserting node $nodeId: $e';
      debugPrint(msg);
      debugPrint('$st');
      _onErrorController.add(msg);
      return;
    }

    _onLogController.add(<String, dynamic>{
      'node_id': nodeId,
      'status_sys': statusSys,
      'latitude': latitude,
      'longitude': longitude,
      'sound_value': soundValue,
      'vibration_count': vibrationCount,
      'vibration_status': vibrationStatus,
      'sound_status': soundStatus,
      'timestamp': timestamp,
    });
  }

  void dispose() {
    _onLogController.close();
    _onRawController.close();
    _onErrorController.close();
  }
}
